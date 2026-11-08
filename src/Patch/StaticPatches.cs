namespace PiLang.Patch;

/// <summary>
/// 原生控件翻译：Electron 菜单栏和 window.confirm 弹窗都不在 DOM 里，注入脚本碰不到。
/// 只能改 asar 里的 main.js（菜单模板）和 renderer.js（弹窗消息字符串）。
/// 只替换字符串常量，不动任何逻辑；替换前原文件已整包备份，还原时用备份恢复。
/// </summary>
internal static class StaticPatches
{
    public const string MainJsPath = "dist/main/main.js";
    public const string RendererJsPath = "dist/renderer/renderer.js";

    /// <summary>main.js 菜单 label（含 Windows 默认菜单、mac 菜单和托盘菜单）。长串在前，避免短串先吃掉。</summary>
    public static readonly (string From, string To)[] MainJs =
    {
        ("label:\"Toggle &Full Screen\"", "label:\"&全屏切换\""),
        ("label:\"Toggle Full Screen\"", "label:\"切换全屏\""),
        ("label:\"&Close window\"", "label:\"&关闭窗口\""),
        ("label:\"About Pi Network\"", "label:\"关于 Pi Network\""),
        ("label:\"Hide Pi Network\"", "label:\"隐藏 Pi Network\""),
        ("label:\"Hide Others\"", "label:\"隐藏其他\""),
        ("label:\"Bring All to Front\"", "label:\"全部置于顶层\""),
        ("label:\"&File\"", "label:\"&文件\""),
        ("label:\"&View\"", "label:\"&视图\""),
        ("label:\"&Reload\"", "label:\"&重新加载\""),
        ("label:\"Select All\"", "label:\"全选\""),
        ("label:\"Learn More\"", "label:\"了解更多\""),
        ("label:\"White Paper\"", "label:\"白皮书\""),
        ("label:\"Inspect element\"", "label:\"检查元素\""),
        ("label:\"Show All\"", "label:\"显示全部\""),
        ("label:\"Services\"", "label:\"服务\""),
        ("label:\"Minimize\"", "label:\"最小化\""),
        ("label:\"Window\"", "label:\"窗口\""),
        ("label:\"Help\"", "label:\"帮助\""),
        ("label:\"Exit\"", "label:\"退出\""),
        ("label:\"Quit\"", "label:\"退出\""),
        ("label:\"Edit\"", "label:\"编辑\""),
        ("label:\"Undo\"", "label:\"撤销\""),
        ("label:\"Redo\"", "label:\"重做\""),
        ("label:\"Cut\"", "label:\"剪切\""),
        ("label:\"Copy\"", "label:\"复制\""),
        ("label:\"Paste\"", "label:\"粘贴\""),
        ("label:\"Close\"", "label:\"关闭\""),
        ("label:\"View\"", "label:\"视图\""),
        ("label:\"Open\"", "label:\"打开\""),
    };

    /// <summary>renderer.js 里 window.confirm 的消息字符串（其余文本由注入脚本按 DOM 翻译）。</summary>
    public static readonly (string From, string To)[] RendererJs =
    {
        ("You are in the middle of the catching up process, which will take some time.",
            "你正处于追赶区块的过程中，这会需要一些时间。"),
        ("If you stop or interrupt the process midway, it will cause the process to restart from the beginning  when you turn on the node again.",
            "如果在过程中停止或中断，重新打开节点时进程会从头开始。"),
        ("Do you want to stop?", "要停止吗？"),
        ("Do you really want to remove all blockchain data?", "你确实要删除所有区块链数据吗？"),
        ("It may take a while for you to restore your local blockchain data.",
            "恢复本地区块链数据可能需要一段时间。"),
        ("Migration is required to run the Horizon blockchain API. This process cannot be interrupted and may take time.",
            "运行 Horizon 区块链 API 需要先迁移。此过程不能被中断，可能需要一些时间。"),
        ("Do you want to start now? You will be redirected to the Troubleshooting page.",
            "要现在开始吗？你将被转到疑难解答页面。"),
        ("Do you want to proceed with the Stellar Horizon migration? This process may take up to 15 minutes. Do not turn off your computer or Docker during this time, as it may result in data loss.",
            "要继续进行 Stellar Horizon 迁移吗？此过程最多需要 15 分钟。在此期间请勿关闭计算机或 Docker，否则可能导致数据丢失。"),
    };

    public static string Apply(string text, (string From, string To)[] map)
    {
        foreach (var (from, to) in map)
            text = text.Replace(from, to, StringComparison.Ordinal);
        return text;
    }

    /// <summary>兜底反向替换（只在备份丢失时用；正常还原走整包备份恢复）。</summary>
    public static string Revert(string text, (string From, string To)[] map)
    {
        for (int i = map.Length - 1; i >= 0; i--)
            text = text.Replace(map[i].To, map[i].From, StringComparison.Ordinal);
        return text;
    }

    public static bool HasAny(string text, (string From, string To)[] map) =>
        map.Any(m => text.Contains(m.To, StringComparison.Ordinal));
}
