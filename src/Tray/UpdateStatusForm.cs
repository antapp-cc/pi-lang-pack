using System.Drawing;
using System.Windows.Forms;

namespace PiLang.Tray;

/// <summary>检查更新时显示的小窗口：阶段文字 + 进度条，让用户看得到在干什么。</summary>
internal sealed class UpdateStatusForm : Form
{
    private readonly Label _label;
    private readonly ProgressBar _bar;

    public UpdateStatusForm()
    {
        Text = "Pi 多语言包 · 检查更新";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        ClientSize = new Size(440, 116);

        _label = new Label
        {
            Text = "正在检查更新…",
            AutoSize = false,
            Left = 16,
            Top = 16,
            Width = 408,
            Height = 24,
        };
        _bar = new ProgressBar
        {
            Left = 16,
            Top = 52,
            Width = 408,
            Height = 20,
            Minimum = 0,
            Maximum = 100,
            Style = ProgressBarStyle.Continuous,
        };
        Controls.Add(_label);
        Controls.Add(_bar);
    }

    public void Report(string stage, int percent)
    {
        if (IsDisposed) return;
        if (InvokeRequired)
        {
            try { BeginInvoke(new Action(() => Report(stage, percent))); } catch { }
            return;
        }
        _label.Text = stage;
        _bar.Value = Math.Max(0, Math.Min(100, percent));
    }
}
