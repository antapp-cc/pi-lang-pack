#include "..\lib\Util.au3"
#include "..\lib\Json.au3"
#include "..\lib\UpdateForm.au3"

; 进度小窗的冒烟测试：能创建、能更新文字/进度、能关掉。
; 不测"好不好看"（那得人眼看），只测它不会崩、不会泄漏窗口。

Global $g_fail = 0

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

ConsoleWrite("== 更新进度窗自检 ==" & @CRLF)

UpdForm_Show()
T(WinExists("Pi 多语言包 · 检查更新") = 1, "窗口已创建")

UpdForm_Report("正在连接更新服务器", 0)
UpdForm_Report("正在下载程序", 42)
UpdForm_Report("正在下载程序", 100)
T(WinExists("Pi 多语言包 · 检查更新") = 1, "多次更新进度后窗口仍在")

UpdForm_Close()
T(WinExists("Pi 多语言包 · 检查更新") = 0, "关闭后窗口消失")

; 重复调用不应该出错（托盘可能连续两次手动检查）
UpdForm_Show()
UpdForm_Show()
UpdForm_Close()
UpdForm_Close()
T(WinExists("Pi 多语言包 · 检查更新") = 0, "重复 Show/Close 不出错")

ConsoleWrite(($g_fail = 0 ? "全部通过" : "失败 " & $g_fail & " 项") & @CRLF)
Exit($g_fail = 0 ? 0 : 1)
