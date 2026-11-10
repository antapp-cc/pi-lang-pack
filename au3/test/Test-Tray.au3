#include <GuiMenu.au3>
#include "..\lib\Util.au3"
#include "..\lib\Json.au3"
#include "..\lib\Tray.au3"

; 兄弟模块（Config/Locator/Patcher/LangPack/Updater）还没交付，这里给桩，
; 只为让 Au3Check 能解析 Tray.au3 的调用；本测试不会真的执行 Tray_Run。
Func Cfg_Load()
	Local $o = Json_NewObject()
	Json_Set($o, "locale", "zh-CN")
	Json_Set($o, "installPath", "")
	Return $o
EndFunc

Func Cfg_Save($cfg)
	Return True
EndFunc

Func Loc_IsValid($sDir)
	Return False
EndFunc

Func Loc_AsarPath($sDir)
	Return ""
EndFunc

Func Loc_Find($cfg)
	Return ""
EndFunc

Func Lang_Load($sLocale)
	Return 0
EndFunc

Func Patch_State($cfg)
	Return "unknown"
EndFunc

Func Patch_Install($cfg, $pack)
	Return 0
EndFunc

Func Patch_Restore($cfg)
	Return 0
EndFunc

Func Patch_Ensure($cfg, $pack)
	Return 0
EndFunc

Func Patch_IsAppRunning()
	Return False
EndFunc

Func Patch_ReadAppVersion($oAsar)
	Return ""
EndFunc

Func Asar_Open($sPath)
	Return 0
EndFunc

Func Upd_ShouldCheckNow($cfg)
	Return False
EndFunc

Func Upd_CheckAndApply($cfg, $fnProgress = 0)
	Return 0
EndFunc

Global $g_fail = 0
Global $g_aTopText[12] = ["已汉化（Pi Network 0.6.4）", "", "安装中文补丁", "还原英文原版", "语言", "", _
		"检查更新", "开机自动启动", "打开配置文件目录", "打开日志", "", "退出"]
Global $g_sTestValue = "PiLangTrayTest"

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

Func TEq($sGot, $sWant, $sWhat)
	T($sGot = $sWant, $sWhat & "（实际：" & $sGot & "）")
EndFunc

Func _SpecItem($aSpec, $sId)
	For $i = 0 To UBound($aSpec) - 1
		If $aSpec[$i].Item("id") = $sId Then Return $aSpec[$i]
	Next
	Return 0
EndFunc

; 用原生菜单 API 手工构建一份菜单，验证 spec 能一比一落成菜单项（不碰真实托盘）
Func _BuildPopupFromSpec($aSpec, ByRef $hSubMenu)
	Local $hMenu = _GUICtrlMenu_CreatePopup()
	Local $hSub = 0
	For $i = 0 To UBound($aSpec) - 1
		Local $e = $aSpec[$i]
		Switch $e.Item("kind")
			Case "submenu"
				$hSub = _GUICtrlMenu_CreatePopup()
				_GUICtrlMenu_AddMenuItem($hMenu, $e.Item("text"), $i + 1, $hSub)
				Local $iSubIdx = _GUICtrlMenu_GetItemCount($hMenu) - 1
				If Not $e.Item("enabled") Then _GUICtrlMenu_SetItemDisabled($hMenu, $iSubIdx)
				If $e.Item("checked") Then _GUICtrlMenu_SetItemChecked($hMenu, $iSubIdx)
			Case "subitem"
				_GUICtrlMenu_AddMenuItem($hSub, $e.Item("text"), $i + 1)
				If $e.Item("checked") Then _GUICtrlMenu_SetItemChecked($hSub, _GUICtrlMenu_GetItemCount($hSub) - 1)
			Case Else
				_GUICtrlMenu_AddMenuItem($hMenu, $e.Item("text"), $i + 1)
				Local $iIdx = _GUICtrlMenu_GetItemCount($hMenu) - 1
				If Not $e.Item("enabled") Then _GUICtrlMenu_SetItemDisabled($hMenu, $iIdx)
				If $e.Item("checked") Then _GUICtrlMenu_SetItemChecked($hMenu, $iIdx)
		EndSwitch
	Next
	$hSubMenu = $hSub
	Return $hMenu
EndFunc

ConsoleWrite("== 托盘层自检 ==" & @CRLF)

; ---- 1. 状态文案 ----
TEq(Tray_StatusText($TRAY_STATE_PATCHED, "0.6.4", "C:\pi"), "已汉化（Pi Network 0.6.4）", "已汉化带版本")
TEq(Tray_StatusText($TRAY_STATE_PATCHED, "", "C:\pi"), "已汉化", "已汉化无版本")
TEq(Tray_StatusText($TRAY_STATE_CLEAN, "0.6.4", "C:\pi"), "未汉化", "未汉化")
TEq(Tray_StatusText($TRAY_STATE_UNKNOWN, "", ""), "找不到 Pi Network 安装目录", "无安装目录")
TEq(Tray_StatusText($TRAY_STATE_UNKNOWN, "", "C:\pi"), "状态未知", "有目录但状态未知")
TEq(Tray_StatusText($TRAY_STATE_MISSING, "", "C:\pi"), "状态未知", "missing 走默认分支")
TEq(Tray_IconText($TRAY_STATE_PATCHED), "Pi 多语言包：已汉化", "图标提示：已汉化")
TEq(Tray_IconText($TRAY_STATE_CLEAN), "Pi 多语言包：未汉化", "图标提示：未汉化")
TEq(Tray_StatusBalloon($TRAY_STATE_PATCHED, "0.6.4"), "Pi Network 界面已汉化（0.6.4）", "双击气泡：已汉化")
TEq(Tray_StatusBalloon($TRAY_STATE_PATCHED, ""), "Pi Network 界面已汉化", "双击气泡：已汉化无版本")
TEq(Tray_StatusBalloon($TRAY_STATE_CLEAN, ""), "尚未汉化，右键托盘图标可安装中文补丁", "双击气泡：未汉化")

; ---- 2. 菜单结构 ----
Local $aPatch = Tray_MenuSpec($TRAY_STATE_PATCHED, "0.6.4", "C:\pi", "zh-CN", False)
T(UBound($aPatch) = 14, "菜单共 14 项（实际 " & UBound($aPatch) & "）")

Local $sIds = ""
For $i = 0 To UBound($aPatch) - 1
	$sIds &= ($i = 0 ? "" : ",") & $aPatch[$i].Item("id")
Next
TEq($sIds, "status,sep_status,install,restore,lang,lang_zh,lang_en,sep_actions,update,autostart,config_dir,log,sep_exit,exit", _
		"菜单项顺序与 C# 版一致")

TEq(_SpecItem($aPatch, "status").Item("text"), "已汉化（Pi Network 0.6.4）", "状态项文案")
T(_SpecItem($aPatch, "status").Item("enabled") = False, "状态项禁用")
TEq(_SpecItem($aPatch, "install").Item("text"), "安装中文补丁", "安装项文案")
TEq(_SpecItem($aPatch, "restore").Item("text"), "还原英文原版", "还原项文案")
TEq(_SpecItem($aPatch, "lang").Item("text"), "语言", "语言子菜单文案")
TEq(_SpecItem($aPatch, "lang").Item("kind"), "submenu", "语言项是子菜单")
TEq(_SpecItem($aPatch, "lang_zh").Item("text"), "简体中文", "简体中文文案")
TEq(_SpecItem($aPatch, "lang_en").Item("text"), "English", "English 文案")
TEq(_SpecItem($aPatch, "update").Item("text"), "检查更新", "检查更新文案")
TEq(_SpecItem($aPatch, "autostart").Item("text"), "开机自动启动", "开机自启文案")
TEq(_SpecItem($aPatch, "config_dir").Item("text"), "打开配置文件目录", "打开配置目录文案")
TEq(_SpecItem($aPatch, "log").Item("text"), "打开日志", "打开日志文案")
TEq(_SpecItem($aPatch, "exit").Item("text"), "退出", "退出文案")
T(_SpecItem($aPatch, "sep_status").Item("kind") = "sep" And _SpecItem($aPatch, "sep_exit").Item("kind") = "sep", "三条分隔线")

; 已汉化时：安装禁用、还原可用
T(_SpecItem($aPatch, "install").Item("enabled") = False, "已汉化：安装项禁用")
T(_SpecItem($aPatch, "restore").Item("enabled") = True, "已汉化：还原项可用")
; zh-CN 勾选简体中文
T(_SpecItem($aPatch, "lang_zh").Item("checked") = True And _SpecItem($aPatch, "lang_en").Item("checked") = False, _
		"zh-CN 勾选简体中文")

; ---- 3. 未汉化 + en-US + 自启开启 + 正在检查更新 ----
Local $aClean = Tray_MenuSpec($TRAY_STATE_CLEAN, "", "C:\pi", "en-US", True, True)
TEq(_SpecItem($aClean, "status").Item("text"), "未汉化", "未汉化状态项文案")
T(_SpecItem($aClean, "install").Item("enabled") = True, "未汉化：安装项可用")
T(_SpecItem($aClean, "restore").Item("enabled") = False, "未汉化：还原项禁用")
T(_SpecItem($aClean, "lang_zh").Item("checked") = False And _SpecItem($aClean, "lang_en").Item("checked") = True, _
		"en-US 勾选 English")
T(_SpecItem($aClean, "autostart").Item("checked") = True, "自启开启时打勾")
TEq(_SpecItem($aClean, "update").Item("text"), "检查更新（进行中…）", "检查中更新项文案")
T(_SpecItem($aClean, "update").Item("enabled") = False, "检查中更新项禁用")

; 找不到目录时安装项也不可用
Local $aNoDir = Tray_MenuSpec($TRAY_STATE_UNKNOWN, "", "", "zh-CN", False)
TEq(_SpecItem($aNoDir, "status").Item("text"), "找不到 Pi Network 安装目录", "无目录状态文案")
T(_SpecItem($aNoDir, "install").Item("enabled") = False, "无目录：安装项禁用")

; ---- 4. spec 落成原生菜单 ----
Local $hSub = 0
Local $hMenu = _BuildPopupFromSpec($aPatch, $hSub)
T(_GUICtrlMenu_GetItemCount($hMenu) = 12, "顶层菜单 12 项（实际 " & _GUICtrlMenu_GetItemCount($hMenu) & "）")
Local $iTextOk = 0
For $i = 0 To UBound($g_aTopText) - 1
	If _GUICtrlMenu_GetItemText($hMenu, $i) = $g_aTopText[$i] Then
		$iTextOk += 1
	Else
		ConsoleWrite("    第 " & $i & " 项文本不符：" & _GUICtrlMenu_GetItemText($hMenu, $i) & " != " & $g_aTopText[$i] & @CRLF)
	EndIf
Next
T($iTextOk = 12, "顶层 12 项文本全部一致（" & $iTextOk & "/12）")
T(_GUICtrlMenu_GetItemDisabled($hMenu, 0), "原生菜单：状态项灰显")
T(_GUICtrlMenu_GetItemDisabled($hMenu, 2), "原生菜单：已汉化时安装项灰显")
T(Not _GUICtrlMenu_GetItemDisabled($hMenu, 3), "原生菜单：已汉化时还原项可用（未灰显）")
T($hSub <> 0, "原生菜单：语言子菜单已挂上")
If $hSub <> 0 Then
	T(_GUICtrlMenu_GetItemCount($hSub) = 2, "语言子菜单 2 项")
	TEq(_GUICtrlMenu_GetItemText($hSub, 0), "简体中文", "子菜单第 1 项文案")
	TEq(_GUICtrlMenu_GetItemText($hSub, 1), "English", "子菜单第 2 项文案")
	T(_GUICtrlMenu_GetItemChecked($hSub, 0) And Not _GUICtrlMenu_GetItemChecked($hSub, 1), "子菜单勾选简体中文")
EndIf
_GUICtrlMenu_DestroyMenu($hMenu)

; ---- 5. 开机自启注册表（临时值，测完删掉） ----
Tray_SetAutoStart(False, $g_sTestValue)
T(Not Tray_IsAutoStart($g_sTestValue), "临时自启值初始不存在")
T(Tray_SetAutoStart(True, $g_sTestValue, '"C:\pilang-test\pi.exe"'), "写入临时自启值")
TEq(RegRead($TRAY_RUN_KEY, $g_sTestValue), '"C:\pilang-test\pi.exe"', "注册表内容原样写入")
T(Tray_IsAutoStart($g_sTestValue), "能读回自启状态")
T(Tray_SetAutoStart(False, $g_sTestValue), "删除临时自启值")
T(Not Tray_IsAutoStart($g_sTestValue), "删除后读不到自启状态")
Tray_SetAutoStart(False, $g_sTestValue)
Local $sCmd = Tray_AutoStartCommand()
T(StringLeft($sCmd, 1) = '"' And StringRight($sCmd, 1) = '"', "自启命令是带引号的完整路径（" & $sCmd & "）")

ConsoleWrite(($g_fail = 0 ? "全部通过" : "失败 " & $g_fail & " 项") & @CRLF)
Exit($g_fail = 0 ? 0 : 1)
