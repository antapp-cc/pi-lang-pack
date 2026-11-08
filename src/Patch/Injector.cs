using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using PiLang.Lang;

namespace PiLang.Patch;

/// <summary>
/// 往 asar 里塞翻译脚本、改 index.html。所有路径都是 asar 内部路径。
/// </summary>
internal static class Injector
{
    public const string ScriptPath = "dist/renderer/pi-lang.js";
    public const string IndexPath = "dist/renderer/index.html";
    private const string ScriptTag = "<script defer=defer src=./pi-lang.js></script>";

    public static string BuildScript(LangPack pack)
    {
        var template = ReadResource("PiLang.Resources.pi-lang.js.template");
        var data = new JsonObject
        {
            ["locale"] = pack.Locale,
            ["version"] = pack.Version,
            ["entries"] = BuildEntries(pack),
            ["danger"] = new JsonArray(pack.Danger.Select(d => (JsonNode)JsonValue.Create(d)!).ToArray()),
            ["patterns"] = BuildPatterns(pack),
        };
        // JSON 直接嵌进脚本字面量；语言包里的反斜杠等由序列化处理
        return template.Replace("__PI_LANG_DATA__", data.ToJsonString());
    }

    private static JsonObject BuildEntries(LangPack pack)
    {
        var entries = new JsonObject();
        foreach (var kv in pack.Entries)
            entries[kv.Key] = kv.Value;
        return entries;
    }

    private static JsonArray BuildPatterns(LangPack pack)
    {
        var list = new JsonArray();
        foreach (var p in pack.Patterns)
        {
            list.Add(new JsonObject { ["p"] = p.Pattern, ["r"] = p.Replacement });
        }
        return list;
    }

    /// <summary>在 renderer.js 之前插入脚本（defer 按文档顺序执行，先执行我们的）。</summary>
    public static string PatchIndexHtml(string html)
    {
        if (html.Contains("pi-lang.js", StringComparison.Ordinal)) return html;

        var anchor = html.IndexOf("<script", StringComparison.Ordinal);
        if (anchor < 0) throw new InvalidDataException("index.html 里找不到 script 标签，版本结构可能变了");
        return html.Insert(anchor, ScriptTag);
    }

    public static string UnpatchIndexHtml(string html) =>
        html.Replace(ScriptTag, "", StringComparison.Ordinal);

    private static string ReadResource(string name)
    {
        using var stream = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
            ?? throw new FileNotFoundException("嵌入资源缺失: " + name);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }
}
