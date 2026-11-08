using PiLang.Lang;
using PiLang.Patch;

namespace PiLang.Guard;

/// <summary>
/// 常驻守护：只盯 app.asar 的大小和修改时间，变了才做完整检查。
/// 平时每 2 秒一次 stat，几乎不占 CPU；官方更新替换 asar 后立即重打。
/// </summary>
internal sealed class GuardService
{
    private Config _cfg;
    private (long Size, long Ticks) _fingerprint = (-1, -1);
    private bool _first = true;
    private string _lastMessage = "";

    public string LastMessage => _lastMessage;
    public event Action<string> Changed;

    public GuardService(Config cfg) => _cfg = cfg;

    public void Tick()
    {
        try
        {
            // CLI（--restore / --lang）可能在另一个进程里改过配置，这里必须重新读磁盘，
            // 否则会把用户刚做的还原又自动打回去。
            _cfg = ConfigStore.Load();

            // 词表在线更新后，等 Pi Node 退出再把新词表打进界面
            if (_cfg.PendingRepatch && !PatchEngine.IsAppRunning())
            {
                var pendingPack = LangPack.Load(_cfg.Locale);
                var repatch = PatchEngine.Install(_cfg, pendingPack);
                if (repatch.Ok)
                {
                    _cfg.PendingRepatch = false;
                    ConfigStore.Save(_cfg);
                    Log.Write("词表更新后已重新打补丁");
                }
            }

            var dir = InstallLocator.Find(_cfg);
            if (!InstallLocator.IsValidInstall(dir)) return;

            var asarPath = InstallLocator.AsarPath(dir);
            var info = new FileInfo(asarPath);
            var fp = (info.Length, info.LastWriteTimeUtc.Ticks);
            if (!_first && fp == _fingerprint) return;
            _fingerprint = fp;
            _first = false;

            var pack = LangPack.Load(_cfg.Locale);
            var result = PatchEngine.Ensure(_cfg, pack);
            var message = result.Ok
                ? (result.Message == "已汉化" ? "已汉化" : result.Message)
                : "自动汉化失败：" + result.Message;
            if (message != _lastMessage)
            {
                _lastMessage = message;
                if (result.Ok && result.Message.StartsWith("已安装", StringComparison.Ordinal))
                    Log.Write("守护自动重打：" + result.Message);
                Changed?.Invoke(message);
            }
        }
        catch (Exception ex)
        {
            Log.Write("守护异常: " + ex.Message);
        }
    }
}
