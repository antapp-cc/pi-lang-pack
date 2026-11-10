#include-once
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <ProgressConstants.au3>

; 手动检查更新时的进度小窗。C# 版有 UpdateStatusForm，AU3 版靠这个补上。
;
; 更新是同步阻塞的（Updater 里轮询 InetGet），所以窗口没法进消息循环；
; 每次进度回调只做"改控件 + GUIGetMsg()"透一次消息，够它重绘就行。

Global $g_updForm = 0
Global $g_updTitle = 0
Global $g_updStage = 0
Global $g_updBar = 0

Func UpdForm_Show($sTitle = "Pi 多语言包 · 检查更新")
	If IsHWnd($g_updForm) Then Return
	$g_updForm = GUICreate($sTitle, 380, 120, -1, -1, BitOR($WS_CAPTION, $WS_POPUP), $WS_EX_TOPMOST)
	GUISetBkColor(0xFFFFFF, $g_updForm)
	$g_updTitle = GUICtrlCreateLabel("正在检查更新…", 20, 18, 340, 24)
	GUICtrlSetFont($g_updTitle, 10, 600)
	$g_updStage = GUICtrlCreateLabel("正在连接更新服务器", 20, 46, 340, 20)
	GUICtrlSetColor($g_updStage, 0x666666)
	$g_updBar = GUICtrlCreateProgress(20, 76, 340, 16)
	GUICtrlSetData($g_updBar, 0)
	GUISetState(@SW_SHOW, $g_updForm)
EndFunc

Func UpdForm_Report($sStage, $iPercent = -1)
	If Not IsHWnd($g_updForm) Then Return
	Local $sText = $sStage
	If $iPercent >= 0 Then $sText &= "  " & $iPercent & "%"
	GUICtrlSetData($g_updStage, $sText)
	If $iPercent >= 0 Then GUICtrlSetData($g_updBar, $iPercent)
	GUIGetMsg() ; 透一次消息让窗口重绘，否则下载期间窗口是白板
EndFunc

Func UpdForm_Close()
	If Not IsHWnd($g_updForm) Then Return
	GUIDelete($g_updForm)
	$g_updForm = 0
EndFunc
