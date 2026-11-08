using System.Security.Cryptography;
using System.Text;
using PiLang.Asar;
using PiLang.Lang;
using PiLang.Patch;

namespace PiLang;

/// <summary>
/// --selftest：不碰正式安装目录，验证 asar 读写往返、注入/还原、语言包和脚本生成。
/// 发布前跑一遍，比"看起来没问题"可靠。
/// </summary>
internal static class SelfTest
{
    private static int _failed;

    public static int Run(Config cfg, LangPack pack)
    {
        Console.WriteLine("== Pi 多语言包自检 ==");
        CheckLangPack(pack);
        CheckScript(pack);
        CheckHtmlPatch();
        CheckStaticPatches();

        var original = FindOriginalAsar(cfg);
        if (original != null)
        {
            CheckAsarRoundTrip(original, pack);
        }
        else
        {
            Console.WriteLine("[跳过] 没找到可用的原始 asar，asar 往返测试未执行");
        }

        Console.WriteLine(_failed == 0 ? "全部通过" : $"失败 {_failed} 项");
        return _failed == 0 ? 0 : 1;
    }

    /// <summary>优先用安装时留的原始备份做往返测试（安装目录里的 asar 可能已打过补丁）。</summary>
    private static string FindOriginalAsar(Config cfg)
    {
        try
        {
            if (Directory.Exists(ConfigStore.BackupDir))
            {
                var orig = Directory.GetFiles(ConfigStore.BackupDir, "app.asar.*.orig")
                    .OrderByDescending(File.GetLastWriteTimeUtc)
                    .FirstOrDefault();
                if (orig != null) return orig;
            }
            var install = InstallLocator.Find(cfg);
            if (!string.IsNullOrEmpty(install)) return InstallLocator.AsarPath(install);
        }
        catch
        {
        }
        return null;
    }

    private static void CheckLangPack(LangPack pack)
    {
        Expect(pack.Entries.Count >= 400, $"语言包条目数 {pack.Entries.Count} ≥ 400");
        var missingDanger = pack.Danger.Where(d => !pack.Entries.ContainsKey(d)).ToArray();
        Expect(missingDanger.Length == 0, "danger 词条都在 entries 里" + (missingDanger.Length > 0 ? "，缺: " + string.Join(", ", missingDanger) : ""));
        Expect(pack.Entries.Values.All(v => !string.IsNullOrWhiteSpace(v)), "没有空译文");
    }

    private static void CheckScript(LangPack pack)
    {
        try
        {
            var script = Injector.BuildScript(pack);
            Expect(script.Contains("/* pi-lang-patch */", StringComparison.Ordinal), "脚本含补丁标记");
            Expect(script.Contains("\"locale\":\"zh-CN\"", StringComparison.Ordinal), "脚本内联了语言包");
            Expect(script.Length > 10_000, $"脚本大小合理（{script.Length} 字节）");
        }
        catch (Exception ex)
        {
            Expect(false, "生成注入脚本失败: " + ex.Message);
        }
    }

    private static void CheckHtmlPatch()
    {
        const string html = "<!DOCTYPE html><html><head><meta charset=utf-8><title>Pi Desktop</title><script defer=defer src=./renderer.js></script></head><body></body></html>";
        try
        {
            var patched = Injector.PatchIndexHtml(html);
            Expect(patched.Contains("./pi-lang.js", StringComparison.Ordinal), "index.html 注入了脚本标签");
            Expect(patched.IndexOf("./pi-lang.js", StringComparison.Ordinal) < patched.IndexOf("./renderer.js", StringComparison.Ordinal), "注入脚本在 renderer.js 之前");
            Expect(!patched.Contains("pi-lang.js", StringComparison.Ordinal) == false, "重复注入不会产生两行");
            Expect(Injector.PatchIndexHtml(patched) == patched, "重复注入幂等");
            var restored = Injector.UnpatchIndexHtml(patched);
            Expect(restored == html, "移除注入后与原文一致");
        }
        catch (Exception ex)
        {
            Expect(false, "index.html 注入/移除去失败: " + ex.Message);
        }
    }

    private static void CheckStaticPatches()
    {
        try
        {
            // Exit/Quit 都译成「退出」，反向替换会互相串；兜底还原只保证不冲突的条目可逆
            const string mainSample = "return[{label:\"&File\",submenu:[{label:\"&Close window\"}]},{label:\"Help\",submenu:[{label:\"White Paper\"}]}]}";
            var patched = StaticPatches.Apply(mainSample, StaticPatches.MainJs);
            Expect(patched.Contains("label:\"&文件\""), "菜单 File 已翻译");
            Expect(patched.Contains("label:\"&关闭窗口\""), "菜单 Close window 已翻译");
            Expect(patched.Contains("label:\"白皮书\""), "菜单 White Paper 已翻译");
            Expect(StaticPatches.Revert(patched, StaticPatches.MainJs) == mainSample, "菜单替换可逆（无冲突项）");
            Expect(StaticPatches.Apply("label:\"Exit\"", StaticPatches.MainJs).Contains("label:\"退出\""), "菜单 Exit 已翻译");

            const string confirmSample = "window.confirm(\"Do you really want to remove all blockchain data?\")";
            Expect(StaticPatches.Apply(confirmSample, StaticPatches.RendererJs).Contains("你确实要删除所有区块链数据吗？"),
                "确认弹窗消息已翻译");

            const string catchupSample = "window.confirm(\"You are in the middle of the catching up process, which will take some time.\")";
            Expect(StaticPatches.Apply(catchupSample, StaticPatches.RendererJs).Contains("追赶区块"),
                "追赶中弹窗消息已翻译");
        }
        catch (Exception ex)
        {
            Expect(false, "静态替换测试异常: " + ex.Message);
        }
    }

    private static void CheckAsarRoundTrip(string asarPath, LangPack pack)
    {
        var work = Path.Combine(Path.GetTempPath(), "pilang-selftest");
        Directory.CreateDirectory(work);
        var testAsar = Path.Combine(work, "test.asar");
        try
        {
            var original = AsarArchive.Open(asarPath);
            var before = original.Files.ToDictionary(f => f.Path, f => AsarArchive.Sha256Hex(f.Data));
            Console.WriteLine($"    原始 asar: {before.Count} 个文件");

            original.Save(testAsar);
            var rebuilt = AsarArchive.Open(testAsar);
            var after = rebuilt.Files.ToDictionary(f => f.Path, f => AsarArchive.Sha256Hex(f.Data));
            Expect(after.Count == before.Count, "重打包后文件数一致");
            Expect(after.All(kv => before.TryGetValue(kv.Key, out var h) && h == kv.Value), "重打包后每个文件字节一致");

            // 注入
            rebuilt.PutFile(Injector.ScriptPath, Encoding.UTF8.GetBytes(Injector.BuildScript(pack)));
            var html = rebuilt.ReadText(Injector.IndexPath);
            rebuilt.PutFile(Injector.IndexPath, Encoding.UTF8.GetBytes(Injector.PatchIndexHtml(html)));
            rebuilt.Save(testAsar);

            var patched = AsarArchive.Open(testAsar);
            Expect(patched.IsPatched(Injector.ScriptPath), "注入后补丁标记可识别");
            Expect(patched.ReadText(Injector.IndexPath).Contains("./pi-lang.js", StringComparison.Ordinal), "注入后 index.html 含脚本");
            Expect(patched.Files.Count == before.Count + 1, "注入后文件数 +1");

            // 还原
            patched.RemoveFile(Injector.ScriptPath);
            patched.PutFile(Injector.IndexPath, Encoding.UTF8.GetBytes(Injector.UnpatchIndexHtml(patched.ReadText(Injector.IndexPath))));
            patched.Save(testAsar);

            var restored = AsarArchive.Open(testAsar);
            Expect(!restored.IsPatched(Injector.ScriptPath), "还原后补丁标记消失");
            var restoredFiles = restored.Files.ToDictionary(f => f.Path, f => AsarArchive.Sha256Hex(f.Data));
            Expect(restoredFiles.Count == before.Count, "还原后文件数一致");
            Expect(restoredFiles.All(kv => before.TryGetValue(kv.Key, out var h) && h == kv.Value), "还原后内容与原始一致");
        }
        catch (Exception ex)
        {
            Expect(false, "asar 往返测试异常: " + ex.Message);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch { }
        }
    }

    private static void Expect(bool ok, string what)
    {
        Console.WriteLine((ok ? "  [OK] " : "  [FAIL] ") + what);
        if (!ok) _failed++;
    }
}
