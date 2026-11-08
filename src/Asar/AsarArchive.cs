using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace PiLang.Asar;

/// <summary>asar 里的一个文件（内容常驻内存，包共约 25MB，没必要流式）。</summary>
public sealed class AsarEntry
{
    public required string Path { get; init; }
    public required byte[] Data { get; init; }
}

/// <summary>
/// asar 格式：8 字节前缀（4、headerPickle 长度）+ headerPickle + 文件数据区。
/// headerPickle = 4 字节 payload 长度 + 4 字节 JSON 长度 + JSON + 4 字节对齐填充。
/// 每个文件条目的 offset 相对数据区起点，保持原 header 的遍历顺序，让重打包后的
/// 字节差异尽量小（也便于人工对照）。
/// </summary>
public sealed class AsarArchive
{
    private const int BlockSize = 4 * 1024 * 1024;
    private const string Marker = "/* pi-lang-patch */";

    private readonly List<AsarEntry> _entries = new();
    private readonly Dictionary<string, AsarEntry> _byPath = new(StringComparer.Ordinal);

    public IReadOnlyList<AsarEntry> Files => _entries;
    public string SourcePath { get; private set; } = "";

    public static AsarArchive Open(string asarPath)
    {
        var bytes = File.ReadAllBytes(asarPath);
        if (bytes.Length < 8) throw new InvalidDataException("asar 文件太短");
        int headerLen = BitConverter.ToInt32(bytes, 4);
        if (headerLen <= 0 || 8 + headerLen > bytes.Length)
            throw new InvalidDataException("asar header 长度非法: " + headerLen);

        int strLen = BitConverter.ToInt32(bytes, 12);
        if (strLen <= 0 || 16 + strLen > 8 + headerLen)
            throw new InvalidDataException("asar header JSON 长度非法: " + strLen);
        var json = Encoding.UTF8.GetString(bytes, 16, strLen);
        var root = JsonNode.Parse(json) as JsonObject ?? throw new InvalidDataException("asar header 不是对象");

        var archive = new AsarArchive { SourcePath = asarPath };
        int dataStart = 8 + headerLen;
        if (root["files"] is JsonObject files)
            archive.Walk(files, "", bytes, dataStart);
        return archive;
    }

    private void Walk(JsonObject files, string prefix, byte[] bytes, int dataStart)
    {
        foreach (var kv in files)
        {
            if (kv.Value is not JsonObject node) continue;
            var path = prefix + kv.Key;
            if (node["files"] is JsonObject sub)
            {
                Walk(sub, path + "/", bytes, dataStart);
                continue;
            }

            int size = ToInt(node["size"]);
            long offset = ToLong(node["offset"]);
            if (offset < 0 || offset + size > bytes.Length - dataStart)
                throw new InvalidDataException("asar 条目越界: " + path);

            var data = new byte[size];
            Buffer.BlockCopy(bytes, dataStart + (int)offset, data, 0, size);
            AddEntry(new AsarEntry { Path = path, Data = data });
        }
    }

    private void AddEntry(AsarEntry entry)
    {
        _entries.Add(entry);
        _byPath[entry.Path] = entry;
    }

    public bool Contains(string path) => _byPath.ContainsKey(path);

    public byte[] ReadFile(string path) =>
        _byPath.TryGetValue(path, out var e) ? e.Data : throw new FileNotFoundException(path);

    public string ReadText(string path) => Encoding.UTF8.GetString(ReadFile(path));

    /// <summary>新增或替换文件。替换保留原位置，新增追加到末尾。</summary>
    public void PutFile(string path, byte[] data)
    {
        if (_byPath.TryGetValue(path, out var existing))
        {
            var updated = new AsarEntry { Path = path, Data = data };
            int index = _entries.IndexOf(existing);
            _entries[index] = updated;
            _byPath[path] = updated;
        }
        else
        {
            AddEntry(new AsarEntry { Path = path, Data = data });
        }
    }

    public bool RemoveFile(string path)
    {
        if (!_byPath.TryGetValue(path, out var existing)) return false;
        _entries.Remove(existing);
        _byPath.Remove(path);
        return true;
    }

    /// <summary>是否已被打过补丁（注入文件存在且带标记）。</summary>
    public bool IsPatched(string scriptPath) =>
        _byPath.TryGetValue(scriptPath, out var e) &&
        Encoding.UTF8.GetString(e.Data).Contains(Marker, StringComparison.Ordinal);

    /// <summary>原子写入：先写临时文件，再覆盖。目标被占用时抛 IOException，由调用方提示关闭应用。</summary>
    public void Save(string outPath)
    {
        var root = new JsonObject();
        var files = new JsonObject();
        root["files"] = files;

        long offset = 0;
        long total = 0;
        foreach (var entry in _entries)
        {
            var parts = entry.Path.Split('/');
            JsonObject node = files;
            for (int i = 0; i < parts.Length - 1; i++)
            {
                if (node[parts[i]] is not JsonObject next)
                {
                    next = new JsonObject { ["files"] = new JsonObject() };
                    node[parts[i]] = next;
                }
                node = next["files"] as JsonObject ?? throw new InvalidDataException("asar 路径冲突: " + entry.Path);
            }

            node[parts[^1]] = new JsonObject
            {
                ["size"] = entry.Data.Length,
                ["integrity"] = BuildIntegrity(entry.Data),
                ["offset"] = offset.ToString(),
            };
            offset += entry.Data.Length;
            total += entry.Data.Length;
        }

        var jsonBytes = Encoding.UTF8.GetBytes(root.ToJsonString());
        int pad = (4 - jsonBytes.Length % 4) % 4;
        int payloadLen = 4 + jsonBytes.Length + pad;
        int headerPartLen = 4 + payloadLen;
        int dataStart = 8 + headerPartLen;

        // 唯一临时名：托盘守护和命令行可能同时操作，避免撞同一个 tmp 文件
        var tmp = outPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            fs.Write(BitConverter.GetBytes(4));
            fs.Write(BitConverter.GetBytes(headerPartLen));
            fs.Write(BitConverter.GetBytes(payloadLen));
            fs.Write(BitConverter.GetBytes(jsonBytes.Length));
            fs.Write(jsonBytes);
            fs.Write(new byte[pad]);
            foreach (var entry in _entries) fs.Write(entry.Data);
            fs.Flush(flushToDisk: true);
        }

        // 用 File.Replace 做同卷原子替换；临时文件被占用时退化为 删除+移动
        if (File.Exists(outPath))
        {
            try
            {
                File.Replace(tmp, outPath, null);
                return;
            }
            catch (IOException)
            {
                File.Delete(outPath);
            }
        }
        File.Move(tmp, outPath);
    }

    public static string Sha256Hex(byte[] data) => Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();

    public static string Sha256Hex(string filePath) =>
        Sha256Hex(File.ReadAllBytes(filePath));

    private static JsonObject BuildIntegrity(byte[] data)
    {
        var blocks = new JsonArray();
        for (int i = 0; i < data.Length; i += BlockSize)
        {
            var len = Math.Min(BlockSize, data.Length - i);
            var block = new byte[len];
            Buffer.BlockCopy(data, i, block, 0, len);
            blocks.Add(Convert.ToHexString(SHA256.HashData(block)).ToLowerInvariant());
        }
        if (blocks.Count == 0) blocks.Add(Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant());

        return new JsonObject
        {
            ["algorithm"] = "SHA256",
            ["hash"] = Sha256Hex(data),
            ["blockSize"] = BlockSize,
            ["blocks"] = blocks,
        };
    }

    private static int ToInt(JsonNode node)
    {
        if (node is JsonValue v && v.TryGetValue<int>(out var i)) return i;
        throw new InvalidDataException("asar size 类型异常");
    }

    private static long ToLong(JsonNode node)
    {
        if (node is JsonValue v)
        {
            if (v.TryGetValue<long>(out var l)) return l;
            if (v.TryGetValue<string>(out var s) && long.TryParse(s, out var parsed)) return parsed;
        }
        throw new InvalidDataException("asar offset 类型异常");
    }
}
