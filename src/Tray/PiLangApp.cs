using System.Diagnostics;
using Microsoft.Win32;
using PiLang.Guard;
using PiLang.Lang;
using PiLang.Patch;
using PiLang.Update;

namespace PiLang.Tray;

internal sealed class PiLangApp : ApplicationContext
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "PiLang";

    private Config _cfg;
    private readonly NotifyIcon _icon;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly GuardService _guard;
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _installItem;
    private readonly ToolStripMenuItem _restoreItem;
    private readonly ToolStripMenuItem _zhItem;
    private readonly ToolStripMenuItem _enItem;
    private readonly ToolStripMenuItem _autoStartItem;
    private readonly ToolStripMenuItem _updateItem;

    private string _state = PatchEngine.StateUnknown;
    private string _version = "";
    private bool _exiting;
    private bool _checkingUpdate;

    public PiLangApp(Config cfg)
    {
        _cfg = cfg;
        _guard = new GuardService(cfg);

        var menu = new ContextMenuStrip();
        _statusItem = new ToolStripMenuItem("状态") { Enabled = false };
        _installItem = new ToolStripMenuItem("安装中文补丁", null, (_, _) => DoInstall());
        _restoreItem = new ToolStripMenuItem("还原英文原版", null, (_, _) => DoRestore());

        var langMenu = new ToolStripMenuItem("语言");
        _zhItem = new ToolStripMenuItem("简体中文", null, (_, _) => SwitchLang("zh-CN"));
        _enItem = new ToolStripMenuItem("English", null, (_, _) => SwitchLang("en-US"));
        langMenu.DropDownItems.Add(_zhItem);
        langMenu.DropDownItems.Add(_enItem);

        _autoStartItem = new ToolStripMenuItem("开机自动启动", null, (_, _) => ToggleAutoStart());
        _updateItem = new ToolStripMenuItem("检查更新", null, (_, _) => CheckUpdates(true));

        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_installItem);
        menu.Items.Add(_restoreItem);
        menu.Items.Add(langMenu);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_updateItem);
        menu.Items.Add(_autoStartItem);
        menu.Items.Add("打开配置文件目录", null, (_, _) => OpenConfigDir());
        menu.Items.Add("打开日志", null, (_, _) => OpenFile(ConfigStore.LogPath));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => ExitApp());
        menu.Opening += (_, _) => RefreshMenu();

        _icon = new NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "Pi 多语言包",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _icon.DoubleClick += (_, _) => ShowStatusBalloon();

        _guard.Changed += OnGuardChanged;
        _timer = new System.Windows.Forms.Timer { Interval = 2000 };
        _timer.Tick += (_, _) => _guard.Tick();
        _timer.Start();

        PrimeState();
        RefreshMenu();

        // 启动 15 秒后自动检查一次；之后每 30 分钟看一次（实际每 6 小时才真正发请求）
        var startupTimer = new System.Windows.Forms.Timer { Interval = 15000 };
        startupTimer.Tick += (_, _) =>
        {
            startupTimer.Stop();
            startupTimer.Dispose();
            if (UpdateService.ShouldCheckNow(_cfg)) CheckUpdates(false);
        };
        startupTimer.Start();

        var periodicTimer = new System.Windows.Forms.Timer { Interval = 30 * 60 * 1000 };
        periodicTimer.Tick += (_, _) =>
        {
            var fresh = ConfigStore.Load();
            if (UpdateService.ShouldCheckNow(fresh)) CheckUpdates(false);
        };
        periodicTimer.Start();
    }

    private async void CheckUpdates(bool manual)
    {
        if (_checkingUpdate) return;
        _checkingUpdate = true;
        _updateItem.Enabled = false;
        try
        {
            _cfg = ConfigStore.Load();
            var result = await UpdateService.CheckAndApplyAsync(_cfg);
            if (manual)
            {
                MessageBox.Show(result.Message, "Pi 多语言包", MessageBoxButtons.OK,
                    result.Ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
            }
            else if (!result.Ok)
            {
                Log.Write("自动检查更新：" + result.Message);
            }

            if (result.LangUpdated)
            {
                _cfg = ConfigStore.Load();
                _state = PatchEngine.State(_cfg);
                RefreshMenu();
                _icon.ShowBalloonTip(6000, "Pi 多语言包",
                    "词表已更新并重新汉化，重启 Pi Network 后生效。", ToolTipIcon.Info);
            }

            if (result.AppUpdated)
            {
                _icon.ShowBalloonTip(6000, "Pi 多语言包", "程序已更新，正在重启…", ToolTipIcon.Info);
                await Task.Delay(1200);
                ExitApp();
            }
        }
        finally
        {
            _checkingUpdate = false;
            _updateItem.Enabled = true;
        }
    }

    private void PrimeState()
    {
        try
        {
            if (string.IsNullOrEmpty(_cfg.InstallPath) || !InstallLocator.IsValidInstall(_cfg.InstallPath))
            {
                var found = InstallLocator.Find(_cfg);
                if (!string.IsNullOrEmpty(found))
                {
                    _cfg.InstallPath = found;
                    ConfigStore.Save(_cfg);
                }
            }
            // 自启的真实状态在注册表里，同步回配置，避免 config.json 显示过期的值
            _cfg.AutoStart = IsAutoStart();
            ConfigStore.Save(_cfg);

            _state = PatchEngine.State(_cfg);
            if (InstallLocator.IsValidInstall(_cfg.InstallPath))
            {
                var archive = Asar.AsarArchive.Open(InstallLocator.AsarPath(_cfg.InstallPath));
                _version = PatchEngine.ReadAppVersion(archive);
            }
        }
        catch (Exception ex)
        {
            Log.Write("初始化状态失败: " + ex.Message);
        }
    }

    private void RefreshMenu()
    {
        var dir = InstallLocator.Find(_cfg);
        _statusItem.Text = _state switch
        {
            PatchEngine.StatePatched => "已汉化" + (string.IsNullOrEmpty(_version) ? "" : "（Pi Network " + _version + "）"),
            PatchEngine.StateClean => "未汉化",
            _ => string.IsNullOrEmpty(dir) ? "找不到 Pi Network 安装目录" : "状态未知",
        };
        _installItem.Enabled = !string.IsNullOrEmpty(dir) && _state != PatchEngine.StatePatched;
        _restoreItem.Enabled = _state == PatchEngine.StatePatched;
        _zhItem.Checked = _cfg.Locale == "zh-CN";
        _enItem.Checked = _cfg.Locale == "en-US";
        _autoStartItem.Checked = IsAutoStart();
        _icon.Text = "Pi 多语言包：" + (_state == PatchEngine.StatePatched ? "已汉化" : "未汉化");
    }

    private void DoInstall()
    {
        _cfg = ConfigStore.Load();
        var pack = LangPack.Load(_cfg.Locale);
        var r = PatchEngine.Install(_cfg, pack);
        _state = r.Ok ? PatchEngine.StatePatched : _state;
        if (r.Ok && !string.IsNullOrEmpty(r.Version)) _version = r.Version;
        RefreshMenu();
        MessageBox.Show(r.Message, "Pi 多语言包", MessageBoxButtons.OK,
            r.Ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
    }

    private void DoRestore()
    {
        _cfg = ConfigStore.Load();
        var r = PatchEngine.Restore(_cfg);
        if (r.Ok) _state = PatchEngine.StateClean;
        RefreshMenu();
        MessageBox.Show(r.Message, "Pi 多语言包", MessageBoxButtons.OK,
            r.Ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
    }

    private void SwitchLang(string locale)
    {
        _cfg = ConfigStore.Load();
        if (_cfg.Locale == locale) return;
        _cfg.Locale = locale;
        ConfigStore.Save(_cfg);

        if (_state == PatchEngine.StatePatched)
        {
            var pack = LangPack.Load(locale);
            var r = PatchEngine.Install(_cfg, pack);
            MessageBox.Show(r.Ok ? "语言已切换，重启 Pi Network 生效。" : r.Message,
                "Pi 多语言包", MessageBoxButtons.OK, r.Ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
        }
        RefreshMenu();
    }

    private void ToggleAutoStart()
    {
        _cfg = ConfigStore.Load();
        var enable = !IsAutoStart();
        SetAutoStart(enable);
        _cfg.AutoStart = enable;
        ConfigStore.Save(_cfg);
        RefreshMenu();
    }

    private void OnGuardChanged(string message)
    {
        try
        {
            // 守护重新读过磁盘配置，界面这边也要跟上
            _cfg = ConfigStore.Load();
            _state = PatchEngine.State(_cfg);
            if (message.StartsWith("已安装", StringComparison.Ordinal))
            {
                _icon.ShowBalloonTip(6000, "Pi 多语言包",
                    "检测到 Pi Network 更新，已自动重新汉化。重启 Pi Network 后生效。",
                    ToolTipIcon.Info);
            }
            RefreshMenu();
        }
        catch (Exception ex)
        {
            Log.Write("刷新界面失败: " + ex.Message);
        }
    }

    private void ShowStatusBalloon()
    {
        var text = _state == PatchEngine.StatePatched
            ? "Pi Network 界面已汉化" + (string.IsNullOrEmpty(_version) ? "" : "（" + _version + "）")
            : "尚未汉化，右键托盘图标可安装中文补丁";
        _icon.ShowBalloonTip(4000, "Pi 多语言包", text, ToolTipIcon.Info);
    }

    private static bool IsAutoStart()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, false);
            return key?.GetValue(RunValue) != null;
        }
        catch
        {
            return false;
        }
    }

    private static void SetAutoStart(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, true);
            if (key == null) return;
            if (enabled) key.SetValue(RunValue, "\"" + Application.ExecutablePath + "\"");
            else key.DeleteValue(RunValue, false);
        }
        catch (Exception ex)
        {
            Log.Write("设置开机自启失败: " + ex.Message);
        }
    }

    private static void OpenConfigDir()
    {
        try
        {
            Directory.CreateDirectory(ConfigStore.ConfigDir);
            Process.Start("explorer.exe", ConfigStore.ConfigDir);
        }
        catch (Exception ex)
        {
            Log.Write("打开目录失败: " + ex.Message);
        }
    }

    private static void OpenFile(string path)
    {
        try
        {
            if (File.Exists(path)) Process.Start("explorer.exe", "\"" + path + "\"");
        }
        catch (Exception ex)
        {
            Log.Write("打开文件失败: " + ex.Message);
        }
    }

    private static Icon LoadIcon()
    {
        try
        {
            var icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            if (icon != null) return icon;
        }
        catch
        {
        }
        return SystemIcons.Application;
    }

    private void ExitApp()
    {
        if (_exiting) return;
        _exiting = true;
        _timer.Stop();
        _icon.Visible = false;
        _icon.Dispose();
        ExitThread();
    }
}

