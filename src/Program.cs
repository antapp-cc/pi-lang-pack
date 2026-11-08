using System.Runtime.InteropServices;
using PiLang;
using PiLang.Lang;
using PiLang.Patch;
using PiLang.Tray;
using PiLang.Update;

internal static class Program
{
    private const string MutexName = @"Local\pi-lang-pack";

    [STAThread]
    private static int Main(string[] args)
    {
        // 更新用的批处理按 GBK 写（中文路径），.NET 默认不带 GBK 编码表
        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);

        if (args.Length > 0) return RunCli(args);

        using var mutex = new Mutex(true, MutexName, out var created);
        if (!created) return 0;

        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        var cfg = ConfigStore.Load();
        LangPack.SeedIfMissing();
        if (string.IsNullOrEmpty(cfg.InstallPath) || !InstallLocator.IsValidInstall(cfg.InstallPath))
        {
            var found = InstallLocator.Find(cfg);
            if (!string.IsNullOrEmpty(found))
            {
                cfg.InstallPath = found;
                ConfigStore.Save(cfg);
            }
        }

        using var app = new PiLangApp(cfg);
        Application.Run(app);
        return 0;
    }

    private static int RunCli(string[] args)
    {
        AttachConsole(-1);
        // 控制台默认是 GBK/系统代码页，管道里会被当成乱码；统一按 UTF-8 输出
        try { Console.OutputEncoding = System.Text.Encoding.UTF8; } catch { }
        var cmd = args[0].TrimStart('-').ToLowerInvariant();
        var cfg = ConfigStore.Load();
        LangPack.SeedIfMissing();

        // --dir 临时指定安装目录（验证副本 / 排障用）
        var dirArg = GetOption(args, "--dir");
        if (!string.IsNullOrWhiteSpace(dirArg) && InstallLocator.IsValidInstall(dirArg))
            cfg.InstallPath = dirArg;

        var pack = LangPack.Load(cfg.Locale);

        switch (cmd)
        {
            case "install":
            {
                var r = PatchEngine.Install(cfg, pack);
                Console.WriteLine(r.Message);
                return r.Ok ? 0 : 1;
            }
            case "restore":
            {
                var r = PatchEngine.Restore(cfg);
                Console.WriteLine(r.Message);
                return r.Ok ? 0 : 1;
            }
            case "ensure":
            {
                var r = PatchEngine.Ensure(cfg, pack);
                if (!r.Ok) Console.WriteLine(r.Message);
                return r.Ok ? 0 : 1;
            }
            case "status":
            {
                var dir = InstallLocator.Find(cfg);
                var state = PatchEngine.State(cfg);
                Console.WriteLine("安装目录 : " + (string.IsNullOrEmpty(dir) ? "(未找到)" : dir));
                Console.WriteLine("汉化状态 : " + (state == PatchEngine.StatePatched ? "已汉化" : state == PatchEngine.StateClean ? "未汉化" : state));
                Console.WriteLine("期望状态 : " + cfg.DesiredState);
                Console.WriteLine("守护     : " + (cfg.GuardEnabled ? "开启" : "关闭"));
                Console.WriteLine("语言     : " + cfg.Locale);
                Console.WriteLine("词表     : " + pack.Entries.Count + " 条（" + pack.Version + "）");
                return 0;
            }
            case "lang":
            {
                if (args.Length < 2) { Console.WriteLine("用法: --lang zh-CN | en-US"); return 2; }
                cfg.Locale = args[1];
                ConfigStore.Save(cfg);
                var fresh = LangPack.Load(cfg.Locale);
                if (PatchEngine.State(cfg) == PatchEngine.StatePatched)
                {
                    var r = PatchEngine.Install(cfg, fresh);
                    Console.WriteLine(r.Message + "（重启 Pi Network 生效）");
                    return r.Ok ? 0 : 1;
                }
                Console.WriteLine("语言已设为 " + cfg.Locale);
                return 0;
            }
            case "update":
            {
                var r = UpdateService.CheckAndApplyAsync(cfg).GetAwaiter().GetResult();
                Console.WriteLine(r.Message);
                if (r.AppUpdated) Console.WriteLine("程序更新将在本进程退出后自动替换并重启。");
                return r.Ok ? 0 : 1;
            }
            case "selftest":
                return SelfTest.Run(cfg, pack);
            default:
                Console.WriteLine("未知参数: " + args[0]);
                Console.WriteLine("可用: --install --restore --ensure --status --lang <locale> --selftest");
                return 2;
        }
    }

    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int processId);

    private static string GetOption(string[] args, string name)
    {
        for (int i = 0; i < args.Length - 1; i++)
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        return null;
    }
}
