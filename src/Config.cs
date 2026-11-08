using System.Text.Encodings.Web;
using System.Text.Json;

namespace PiLang;

internal sealed class Config
{
    /// <summary>Pi Network 安装目录（含 resources\app.asar 的上一层）。</summary>
    public string InstallPath { get; set; } = "";

    /// <summary>当前语言，目前只有 zh-CN / en-US。</summary>
    public string Locale { get; set; } = "zh-CN";

    /// <summary>
    /// 期望状态：zh = 应该汉化（守护会在被官方更新覆盖后自动重打）；
    /// restored = 用户主动还原英文，守护不许再打；paused = 守护暂停但仍记住期望。
    /// 没有这个字段就会出现"点还原后两秒被打回中文"的循环。
    /// </summary>
    public string DesiredState { get; set; } = "zh";

    /// <summary>是否启用自动重打（官方更新后恢复中文）。</summary>
    public bool GuardEnabled { get; set; } = true;

    /// <summary>已打补丁后的 asar 指纹，用来发现"文件被外部换掉"。</summary>
    public string AppliedAsarHash { get; set; } = "";

    /// <summary>上次成功打补丁时 asar 内的应用版本。</summary>
    public string LastPatchVersion { get; set; } = "";

    public bool AutoStart { get; set; }

    /// <summary>在线更新清单地址（必须是 https；本地测试允许 http://localhost）。</summary>
    public string UpdateUrl { get; set; } = "https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json";

    /// <summary>是否自动检查更新（启动后和每 6 小时一次）。</summary>
    public bool AutoUpdate { get; set; } = true;

    /// <summary>上次检查更新的时间（UTC ISO），用于控制检查频率。</summary>
    public string LastUpdateCheck { get; set; } = "";

    /// <summary>词表已更新但还没打补丁（等 Pi Node 退出后由守护完成）。</summary>
    public bool PendingRepatch { get; set; }
}

internal static class ConfigStore
{
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public static string ConfigDir =>
        // 环境变量用于验证/排障时把配置隔离到临时目录，不污染真实用户配置
        (Environment.GetEnvironmentVariable("PILANG_CONFIG_DIR") is { Length: > 0 } custom
            ? custom
            : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PiLang"));

    public static string LangDir => Path.Combine(ConfigDir, "langs");
    public static string BackupDir => Path.Combine(ConfigDir, "backup");
    public static string LogPath => Path.Combine(ConfigDir, "PiLang.log");

    private static string FilePath => Path.Combine(ConfigDir, "config.json");

    public static Config Load()
    {
        try
        {
            Directory.CreateDirectory(ConfigDir);
            if (File.Exists(FilePath))
            {
                var json = File.ReadAllText(FilePath);
                var cfg = JsonSerializer.Deserialize<Config>(json, Json);
                if (cfg != null) return cfg;
            }
        }
        catch
        {
            // 配置坏了就用默认值继续，不能让守护因此停摆
        }
        return new Config();
    }

    public static void Save(Config config)
    {
        Directory.CreateDirectory(ConfigDir);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(config, Json));
    }
}

internal static class Log
{
    public static void Write(string message)
    {
        try
        {
            Directory.CreateDirectory(ConfigStore.ConfigDir);
            File.AppendAllText(ConfigStore.LogPath,
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}");
        }
        catch
        {
            // 日志写不了不影响主流程
        }
    }
}

