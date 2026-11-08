using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;
using PiLang.Lang;
using PiLang.Patch;

namespace PiLang.Update;

internal sealed class UpdateManifest
{
    public AppUpdateInfo App { get; set; }
    public LangUpdateInfo Lang { get; set; }
}

internal sealed class AppUpdateInfo
{
    public string Version { get; set; } = "";
    public string Url { get; set; } = "";
    public string Sha256 { get; set; } = "";
}

internal sealed class LangUpdateInfo
{
    public string Version { get; set; } = "";
    public string Url { get; set; } = "";
    public string Sha256 { get; set; } = "";
}

internal sealed class UpdateResult
{
    public bool Ok { get; init; }
    public string Message { get; init; } = "";
    public bool AppUpdated { get; init; }
    public bool LangUpdated { get; init; }
    public static UpdateResult Fail(string msg) => new() { Ok = false, Message = msg };
}

/// <summary>
/// 在线更新：拉最新清单 → 校验 SHA256 → 更新词表（自动重打）或替换程序本体（重启）。
/// 只信任 https 地址；下载的内容必须和清单里的 SHA256 一致，否则拒绝。
/// </summary>
internal static class UpdateService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    public static string CurrentAppVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";

    public static string UpdateDir => Path.Combine(ConfigStore.ConfigDir, "update");

    public static async Task<UpdateResult> CheckAndApplyAsync(Config cfg)
    {
        try
        {
            if (!IsAllowedUrl(cfg.UpdateUrl))
                return UpdateResult.Fail("更新地址必须是 https://（本地测试可用 http://localhost 或 http://127.0.0.1）");

            var json = await Http.GetStringAsync(cfg.UpdateUrl);
            var manifest = JsonSerializer.Deserialize<UpdateManifest>(json, Json);
            if (manifest == null) return UpdateResult.Fail("更新清单格式错误");

            var changed = new List<string>();

            if (manifest.Lang != null && !string.IsNullOrWhiteSpace(manifest.Lang.Url))
            {
                if (await ApplyLangAsync(manifest.Lang, cfg))
                {
                    changed.Add("词表已更新");
                    Log.Write("在线更新：词表已更新到 " + manifest.Lang.Version);
                }
            }

            var appUpdated = false;
            if (manifest.App != null && !string.IsNullOrWhiteSpace(manifest.App.Url) &&
                IsNewer(manifest.App.Version, CurrentAppVersion))
            {
                if (await PrepareAppUpdateAsync(manifest.App))
                {
                    appUpdated = true;
                    changed.Add("程序已更新到 " + manifest.App.Version);
                    Log.Write("在线更新：程序已下载 " + manifest.App.Version + "，等待替换");
                }
            }

            cfg.LastUpdateCheck = DateTime.UtcNow.ToString("O");
            ConfigStore.Save(cfg);

            if (changed.Count == 0)
                return new UpdateResult { Ok = true, Message = "已是最新版本" };

            return new UpdateResult
            {
                Ok = true,
                Message = string.Join("，", changed),
                AppUpdated = appUpdated,
                LangUpdated = changed.Contains("词表已更新"),
            };
        }
        catch (Exception ex)
        {
            Log.Write("检查更新失败: " + ex.Message);
            return UpdateResult.Fail("检查更新失败：" + ex.Message);
        }
    }

    private static async Task<bool> ApplyLangAsync(LangUpdateInfo info, Config cfg)
    {
        var bytes = await Http.GetByteArrayAsync(info.Url);
        VerifySha256(bytes, info.Sha256);

        var path = Path.Combine(ConfigStore.LangDir, "zh-CN.json");
        if (File.Exists(path))
        {
            var current = File.ReadAllBytes(path);
            if (current.Length == bytes.Length &&
                Convert.ToHexString(SHA256.HashData(current)).Equals(info.Sha256, StringComparison.OrdinalIgnoreCase))
                return false;
        }

        Directory.CreateDirectory(ConfigStore.LangDir);
        File.WriteAllBytes(path, bytes);

        // 词表换了，已汉化的界面要重打一次；Pi Node 在跑就等它退出（守护负责）
        cfg.PendingRepatch = true;
        if (!PatchEngine.IsAppRunning())
        {
            var pack = LangPack.Load(cfg.Locale);
            var r = PatchEngine.Install(cfg, pack);
            if (r.Ok) cfg.PendingRepatch = false;
            else Log.Write("词表更新后重打失败: " + r.Message);
        }
        ConfigStore.Save(cfg);
        return true;
    }

    private static async Task<bool> PrepareAppUpdateAsync(AppUpdateInfo info)
    {
        var bytes = await Http.GetByteArrayAsync(info.Url);
        VerifySha256(bytes, info.Sha256);

        Directory.CreateDirectory(UpdateDir);
        var newExe = Path.Combine(UpdateDir, "PiLang.new.exe");
        File.WriteAllBytes(newExe, bytes);

        var target = Environment.ProcessPath ?? Application.ExecutablePath;
        var batch = Path.Combine(UpdateDir, "update-runner.cmd");
        WriteBatch(batch, newExe, target, target + ".old");

        var psi = new ProcessStartInfo("cmd.exe", "/c \"" + batch + "\"")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            WindowStyle = ProcessWindowStyle.Hidden,
        };
        Process.Start(psi);
        return true;
    }

    /// <summary>
    /// 用批处理做自替换：等当前进程退出（copy 失败就重试）→ 备份旧 exe → 换新 → 启动 → 自删。
    /// 批处理用 GBK 写，中文路径在 cmd 里才不出乱码。
    /// </summary>
    private static void WriteBatch(string batchPath, string newExe, string target, string backup)
    {
        var sb = new StringBuilder();
        sb.AppendLine("@echo off");
        sb.AppendLine("chcp 936 >nul");
        sb.AppendLine("timeout /t 3 /nobreak >nul");
        sb.AppendLine(":retry");
        sb.AppendLine($"copy /Y \"{target}\" \"{backup}\" >nul 2>&1");
        sb.AppendLine($"copy /Y \"{newExe}\" \"{target}\" >nul 2>&1");
        sb.AppendLine("if errorlevel 1 (");
        sb.AppendLine("  timeout /t 1 /nobreak >nul");
        sb.AppendLine("  goto retry");
        sb.AppendLine(")");
        sb.AppendLine($"start \"\" \"{target}\"");
        sb.AppendLine($"del \"{newExe}\" >nul 2>&1");
        sb.AppendLine("del \"%~f0\" >nul 2>&1");
        File.WriteAllText(batchPath, sb.ToString(), Encoding.GetEncoding(936));
    }

    private static void VerifySha256(byte[] bytes, string expected)
    {
        if (string.IsNullOrWhiteSpace(expected)) return;
        var actual = Convert.ToHexString(SHA256.HashData(bytes));
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("SHA256 校验失败，已拒绝更新");
    }

    private static bool IsNewer(string remote, string local)
    {
        if (!Version.TryParse(remote, out var r)) return false;
        if (!Version.TryParse(local, out var l)) return false;
        return r > l;
    }

    private static bool IsAllowedUrl(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme == Uri.UriSchemeHttps) return true;
        return uri.Scheme == Uri.UriSchemeHttp && (uri.IsLoopback || uri.Host == "localhost");
    }

    /// <summary>自动检查：启动后一次、之后每 6 小时一次（记录在 config 里）。</summary>
    public static bool ShouldCheckNow(Config cfg)
    {
        if (!cfg.AutoUpdate || string.IsNullOrWhiteSpace(cfg.UpdateUrl)) return false;
        if (string.IsNullOrWhiteSpace(cfg.LastUpdateCheck)) return true;
        if (!DateTime.TryParse(cfg.LastUpdateCheck, null,
                System.Globalization.DateTimeStyles.RoundtripKind, out var last)) return true;
        return DateTime.UtcNow - last > TimeSpan.FromHours(6);
    }
}
