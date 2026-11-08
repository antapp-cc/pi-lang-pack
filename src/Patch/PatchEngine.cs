using System.Diagnostics;
using System.Text;
using System.Text.Json;
using PiLang.Asar;
using PiLang.Lang;

namespace PiLang.Patch;

internal sealed class PatchResult
{
    public bool Ok { get; init; }
    public string Message { get; init; } = "";
    public string Version { get; init; } = "";
    public static PatchResult Success(string msg, string version = "") => new() { Ok = true, Message = msg, Version = version };
    public static PatchResult Fail(string msg) => new() { Ok = false, Message = msg };
}

internal static class PatchEngine
{
    public const string StatePatched = "patched";
    public const string StateClean = "notpatched";
    public const string StateMissing = "missing";
    public const string StateUnknown = "unknown";

    /// <summary>
    /// 托盘守护和命令行是两个进程，可能同时想改 app.asar。用跨进程互斥锁排队，
    /// 否则会互相覆盖临时文件、写坏界面文件。Windows Mutex 对同一线程可重入，
    /// Ensure 内部再调 Install 不会死锁。
    /// </summary>
    private static readonly Mutex WriteMutex = new(false, @"Local\pi-lang-asar-write");

    public static string State(Config cfg)
    {
        var dir = InstallLocator.Find(cfg);
        if (!InstallLocator.IsValidInstall(dir)) return StateMissing;
        try
        {
            var archive = AsarArchive.Open(InstallLocator.AsarPath(dir));
            return archive.IsPatched(Injector.ScriptPath) ? StatePatched : StateClean;
        }
        catch (Exception ex)
        {
            Log.Write("读取 asar 状态失败: " + ex.Message);
            return StateUnknown;
        }
    }

    public static PatchResult Install(Config cfg, LangPack pack)
    {
        if (!WriteMutex.WaitOne(TimeSpan.FromSeconds(30)))
            return PatchResult.Fail("另一个操作正在进行，请稍后再试");
        try
        {
            return InstallCore(cfg, pack);
        }
        finally
        {
            WriteMutex.ReleaseMutex();
        }
    }

    private static PatchResult InstallCore(Config cfg, LangPack pack)
    {
        var dir = InstallLocator.Find(cfg);
        if (!InstallLocator.IsValidInstall(dir)) return PatchResult.Fail("找不到 Pi Network 安装目录");
        if (IsAppRunning()) return PatchResult.Fail("Pi Network 正在运行，请先完全退出（托盘图标也要退出）");

        var asarPath = InstallLocator.AsarPath(dir);
        AsarArchive archive;
        try
        {
            archive = AsarArchive.Open(asarPath);
        }
        catch (Exception ex)
        {
            return PatchResult.Fail("读取 app.asar 失败：" + ex.Message);
        }

        var version = ReadAppVersion(archive);
        try
        {
            Backup(asarPath, version);
            archive.PutFile(Injector.ScriptPath, Encoding.UTF8.GetBytes(Injector.BuildScript(pack)));
            var html = archive.ReadText(Injector.IndexPath);
            archive.PutFile(Injector.IndexPath, Encoding.UTF8.GetBytes(Injector.PatchIndexHtml(html)));

            // 原生菜单和 confirm 弹窗不在 DOM 里，只能替换字符串常量
            archive.PutFile(StaticPatches.MainJsPath,
                Encoding.UTF8.GetBytes(StaticPatches.Apply(archive.ReadText(StaticPatches.MainJsPath), StaticPatches.MainJs)));
            archive.PutFile(StaticPatches.RendererJsPath,
                Encoding.UTF8.GetBytes(StaticPatches.Apply(archive.ReadText(StaticPatches.RendererJsPath), StaticPatches.RendererJs)));

            archive.Save(asarPath);
        }
        catch (Exception ex)
        {
            return PatchResult.Fail("写入 app.asar 失败：" + ex.Message);
        }

        cfg.InstallPath = dir;
        cfg.AppliedAsarHash = AsarArchive.Sha256Hex(asarPath);
        cfg.LastPatchVersion = version;
        cfg.DesiredState = "zh";
        ConfigStore.Save(cfg);
        Log.Write($"已安装中文补丁，Pi Network {version}，asar 指纹 {cfg.AppliedAsarHash[..12]}");
        return PatchResult.Success("已安装中文补丁（Pi Network " + version + "）", version);
    }

    public static PatchResult Restore(Config cfg)
    {
        if (!WriteMutex.WaitOne(TimeSpan.FromSeconds(30)))
            return PatchResult.Fail("另一个操作正在进行，请稍后再试");
        try
        {
            return RestoreCore(cfg);
        }
        finally
        {
            WriteMutex.ReleaseMutex();
        }
    }

    private static PatchResult RestoreCore(Config cfg)
    {
        var dir = InstallLocator.Find(cfg);
        if (!InstallLocator.IsValidInstall(dir)) return PatchResult.Fail("找不到 Pi Network 安装目录");
        if (IsAppRunning()) return PatchResult.Fail("Pi Network 正在运行，请先完全退出");

        var asarPath = InstallLocator.AsarPath(dir);
        try
        {
            // 优先用整包备份恢复：静态替换过的 main.js/renderer.js 也能一并还原
            var version = "";
            try { version = ReadAppVersion(AsarArchive.Open(asarPath)); } catch { }
            var backup = Path.Combine(ConfigStore.BackupDir,
                "app.asar." + (string.IsNullOrWhiteSpace(version) ? "unknown" : version) + ".orig");

            if (File.Exists(backup))
            {
                File.Copy(backup, asarPath, overwrite: true);
            }
            else
            {
                // 备份丢了就尽量就地还原（菜单/弹窗文案可能残留中文）
                var archive = AsarArchive.Open(asarPath);
                if (archive.IsPatched(Injector.ScriptPath))
                {
                    archive.RemoveFile(Injector.ScriptPath);
                    var html = archive.ReadText(Injector.IndexPath);
                    archive.PutFile(Injector.IndexPath, Encoding.UTF8.GetBytes(Injector.UnpatchIndexHtml(html)));
                    archive.PutFile(StaticPatches.MainJsPath,
                        Encoding.UTF8.GetBytes(StaticPatches.Revert(archive.ReadText(StaticPatches.MainJsPath), StaticPatches.MainJs)));
                    archive.PutFile(StaticPatches.RendererJsPath,
                        Encoding.UTF8.GetBytes(StaticPatches.Revert(archive.ReadText(StaticPatches.RendererJsPath), StaticPatches.RendererJs)));
                    archive.Save(asarPath);
                }
            }
        }
        catch (Exception ex)
        {
            return PatchResult.Fail("还原 app.asar 失败：" + ex.Message);
        }

        cfg.DesiredState = "restored";
        cfg.AppliedAsarHash = "";
        ConfigStore.Save(cfg);
        Log.Write("已还原英文原版");
        return PatchResult.Success("已还原英文原版");
    }

    /// <summary>
    /// 守护用的幂等入口：按 desiredState 决定该不该打。
    /// 用户点过"还原"（restored）就绝不自动打，避免还原和守护互相打架。
    /// </summary>
    public static PatchResult Ensure(Config cfg, LangPack pack)
    {
        var dir = InstallLocator.Find(cfg);
        if (!InstallLocator.IsValidInstall(dir)) return PatchResult.Fail("找不到 Pi Network 安装目录");

        if (cfg.DesiredState == "restored") return PatchResult.Success("已还原英文，守护不自动汉化");
        if (cfg.DesiredState == "paused" || !cfg.GuardEnabled) return PatchResult.Success("守护已暂停");

        var state = State(cfg);
        if (state == StatePatched)
        {
            var asarPath = InstallLocator.AsarPath(dir);
            var hash = AsarArchive.Sha256Hex(asarPath);
            if (!string.IsNullOrEmpty(cfg.AppliedAsarHash) && hash != cfg.AppliedAsarHash)
            {
                // 文件被外部换过（可能是官方更新），重打
                return Install(cfg, pack);
            }
            return PatchResult.Success("已汉化");
        }

        if (state == StateUnknown) return PatchResult.Fail("app.asar 状态异常，跳过自动汉化");
        return Install(cfg, pack);
    }

    public static bool IsAppRunning() =>
        Process.GetProcessesByName(InstallLocator.ProcessName).Length > 0;

    public static string ReadAppVersion(AsarArchive archive)
    {
        try
        {
            using var doc = JsonDocument.Parse(archive.ReadText("package.json"));
            return doc.RootElement.TryGetProperty("version", out var v) ? v.GetString() ?? "" : "";
        }
        catch
        {
            return "";
        }
    }

    private static void Backup(string asarPath, string version)
    {
        Directory.CreateDirectory(ConfigStore.BackupDir);
        var name = "app.asar." + (string.IsNullOrWhiteSpace(version) ? "unknown" : version) + ".orig";
        var target = Path.Combine(ConfigStore.BackupDir, name);
        if (File.Exists(target)) return;

        // 只留 3 份，避免每次官方更新都堆 25MB
        var olds = Directory.GetFiles(ConfigStore.BackupDir, "app.asar.*.orig")
            .OrderByDescending(File.GetLastWriteTimeUtc).Skip(2).ToArray();
        foreach (var old in olds)
        {
            try { File.Delete(old); } catch { }
        }
        File.Copy(asarPath, target);
    }
}
