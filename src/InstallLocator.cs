using Microsoft.Win32;

namespace PiLang;

/// <summary>
/// 找 Pi Network 的安装目录。顺序：配置里记住的路径 → 卸载注册表的 DisplayIcon
/// → 默认安装路径。换机器/换安装位置都能自己找到。
/// </summary>
internal static class InstallLocator
{
    public const string ProcessName = "Pi Network";

    public static bool IsValidInstall(string dir)
    {
        if (string.IsNullOrWhiteSpace(dir)) return false;
        return File.Exists(Path.Combine(dir, "resources", "app.asar"));
    }

    public static string AsarPath(string installDir) => Path.Combine(installDir, "resources", "app.asar");

    public static string Find(Config cfg)
    {
        if (IsValidInstall(cfg.InstallPath)) return cfg.InstallPath;

        foreach (var root in new[] { @"HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                                     @"HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall" })
        {
            var found = FindInRegistry(root);
            if (found != null) return found;
        }

        var fallback = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs", "pi-network-desktop");
        if (IsValidInstall(fallback)) return fallback;

        return "";
    }

    private static string FindInRegistry(string root)
    {
        try
        {
            using var baseKey = RegistryKey.OpenBaseKey(
                root.StartsWith("HKCU", StringComparison.OrdinalIgnoreCase)
                    ? RegistryHive.CurrentUser : RegistryHive.LocalMachine,
                RegistryView.Default);
            using var uninstall = baseKey.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall");
            if (uninstall == null) return null;

            foreach (var name in uninstall.GetSubKeyNames())
            {
                using var sub = uninstall.OpenSubKey(name);
                var displayName = sub?.GetValue("DisplayName") as string;
                if (displayName == null || !displayName.Contains("Pi Network", StringComparison.OrdinalIgnoreCase))
                    continue;

                var icon = sub?.GetValue("DisplayIcon") as string;
                if (string.IsNullOrWhiteSpace(icon)) continue;

                // DisplayIcon 形如 "C:\...\Pi Network.exe,0"
                var exe = icon.Split(',')[0].Trim().Trim('"');
                var dir = Path.GetDirectoryName(exe);
                if (IsValidInstall(dir)) return dir;
            }
        }
        catch
        {
            // 注册表读不到就继续找下一处
        }
        return null;
    }
}
