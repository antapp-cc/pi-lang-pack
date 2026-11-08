using System.Reflection;
using System.Text.Json;

namespace PiLang.Lang;

internal sealed class LangPattern
{
    public string Pattern { get; set; } = "";
    public string Replacement { get; set; } = "";
}

/// <summary>
/// 一份语言包。词表是"英文原文 → 译文"的整句映射，danger 里的词条只允许整句精确
/// 匹配（新版应用换了说法就保留英文，不冒险套用），防止危险操作被误翻。
/// </summary>
internal sealed class LangPack
{
    public string Locale { get; set; } = "zh-CN";
    public string Name { get; set; } = "简体中文";
    public string Version { get; set; } = "";
    public Dictionary<string, string> Entries { get; set; } = new(StringComparer.Ordinal);
    public List<string> Danger { get; set; } = new();
    public List<LangPattern> Patterns { get; set; } = new();

    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    public static LangPack LoadBuiltIn()
    {
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("PiLang.Resources.zh-CN.json")
            ?? throw new FileNotFoundException("内置语言包缺失");
        using var reader = new StreamReader(stream);
        return JsonSerializer.Deserialize<LangPack>(reader.ReadToEnd(), Json) ?? new LangPack();
    }

    /// <summary>首次运行把内置词表释放到 %APPDATA%\PiLang\langs，方便之后单独替换词表。</summary>
    public static void SeedIfMissing()
    {
        try
        {
            Directory.CreateDirectory(ConfigStore.LangDir);
            var target = Path.Combine(ConfigStore.LangDir, "zh-CN.json");
            if (File.Exists(target)) return;
            using var stream = Assembly.GetExecutingAssembly()
                .GetManifestResourceStream("PiLang.Resources.zh-CN.json");
            if (stream == null) return;
            using var file = File.Create(target);
            stream.CopyTo(file);
        }
        catch (Exception ex)
        {
            Log.Write("释放语言包失败: " + ex.Message);
        }
    }

    /// <summary>
    /// 内置词表打底 + 用户目录里的词表覆盖（用户优先）。
    /// 这样工具升级带的新词条会自动生效，用户自己补/改的条目也不会丢。
    /// </summary>
    public static LangPack Load(string locale)
    {
        SeedIfMissing();

        var builtIn = string.Equals(locale, "zh-CN", StringComparison.OrdinalIgnoreCase)
            ? LoadBuiltIn()
            : new LangPack { Locale = locale };

        LangPack external = null;
        try
        {
            var path = Path.Combine(ConfigStore.LangDir, locale + ".json");
            if (File.Exists(path))
                external = JsonSerializer.Deserialize<LangPack>(File.ReadAllText(path), Json);
        }
        catch (Exception ex)
        {
            Log.Write("读取外部语言包失败，用内置词表: " + ex.Message);
        }

        if (external == null) return builtIn;

        var merged = new LangPack
        {
            Locale = locale,
            Name = string.IsNullOrEmpty(external.Name) ? builtIn.Name : external.Name,
            Version = string.IsNullOrEmpty(external.Version) ? builtIn.Version : external.Version,
            Entries = new Dictionary<string, string>(builtIn.Entries, StringComparer.Ordinal),
            Danger = builtIn.Danger.Union(external.Danger).Distinct().ToList(),
            Patterns = builtIn.Patterns.Concat(external.Patterns).ToList(),
        };
        foreach (var kv in external.Entries) merged.Entries[kv.Key] = kv.Value;
        return merged;
    }
}
