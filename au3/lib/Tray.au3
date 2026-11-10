#include-once
#include <TrayConstants.au3>
#include <MsgBoxConstants.au3>

; 托盘程序：与 C# 版 Tray\PiLangApp.cs 一一对应。
; 本模块只 include 标准库；Cfg_/Loc_/Patch_/Lang_/Asar_ 等函数由主脚本按契约提供。

Global Const $TRAY_STATE_PATCHED = "patched"
Global Const $TRAY_STATE_CLEAN = "notpatched"
Global Const $TRAY_STATE_MISSING = "missing"
Global Const $TRAY_STATE_UNKNOWN = "unknown"

Global Const $TRAY_RUN_KEY = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
Global Const $TRAY_RUN_VALUE = "PiLang"

Global $g_trayCfg = 0
Global $g_trayState = $TRAY_STATE_UNKNOWN
Global $g_trayVersion = ""
Global $g_trayDir = ""
Global $g_trayExiting = False
Global $g_trayChecking = False
Global $g_trayFp = ""
Global $g_trayFirst = True
Global $g_trayLastMsg = ""
Global $g_trayMenuSig = ""
Global $g_trayMenuItems = 0
Global $g_trayIdStatus = -1
Global $g_trayIdInstall = -1
Global $g_trayIdRestore = -1
Global $g_trayIdLangZh = -1
Global $g_trayIdLangEn = -1
Global $g_trayIdUpdate = -1
Global $g_trayIdAutoStart = -1
Global $g_trayIdConfigDir = -1
Global $g_trayIdLog = -1
Global $g_trayIdExit = -1

; ---- 纯函数区：不碰托盘/注册表，方便自检 ----

; 状态文案与 C# RefreshMenu 的 switch 一致
Func Tray_StatusText($sState, $sVersion, $sDir)
	Switch $sState
		Case $TRAY_STATE_PATCHED
			Return "已汉化" & ($sVersion = "" ? "" : "（Pi Network " & $sVersion & "）")
		Case $TRAY_STATE_CLEAN
			Return "未汉化"
		Case Else
			Return $sDir = "" ? "找不到 Pi Network 安装目录" : "状态未知"
	EndSwitch
EndFunc

Func Tray_IconText($sState)
	Return "Pi 多语言包：" & ($sState = $TRAY_STATE_PATCHED ? "已汉化" : "未汉化")
EndFunc

Func Tray_StatusBalloon($sState, $sVersion)
	If $sState = $TRAY_STATE_PATCHED Then
		Return "Pi Network 界面已汉化" & ($sVersion = "" ? "" : "（" & $sVersion & "）")
	EndIf
	Return "尚未汉化，右键托盘图标可安装中文补丁"
EndFunc

; 菜单的唯一事实来源：托盘构建和自检都从这里取文本/可用/勾选状态。
; kind: item=普通项, sep=分隔线, submenu=子菜单, subitem=子菜单项（parent 指向子菜单 id）
Func Tray_MenuSpec($sState, $sVersion, $sDir, $sLocale, $bAutoStart, $bChecking = False)
	Local $aSpec[14]
	Local $i = 0
	$aSpec[$i] = _Tray_Entry("status", Tray_StatusText($sState, $sVersion, $sDir), False, False, "item")
	$i += 1
	$aSpec[$i] = _Tray_Entry("sep_status", "", True, False, "sep")
	$i += 1
	$aSpec[$i] = _Tray_Entry("install", "安装中文补丁", $sDir <> "" And $sState <> $TRAY_STATE_PATCHED, False, "item")
	$i += 1
	$aSpec[$i] = _Tray_Entry("restore", "还原英文原版", $sState = $TRAY_STATE_PATCHED, False, "item")
	$i += 1
	$aSpec[$i] = _Tray_Entry("lang", "语言", True, False, "submenu")
	$i += 1
	$aSpec[$i] = _Tray_Entry("lang_zh", "简体中文", True, $sLocale = "zh-CN", "subitem", "lang")
	$i += 1
	$aSpec[$i] = _Tray_Entry("lang_en", "English", True, $sLocale = "en-US", "subitem", "lang")
	$i += 1
	$aSpec[$i] = _Tray_Entry("sep_actions", "", True, False, "sep")
	$i += 1
	$aSpec[$i] = _Tray_Entry("update", $bChecking ? "检查更新（进行中…）" : "检查更新", Not $bChecking, False, "item")
	$i += 1
	$aSpec[$i] = _Tray_Entry("autostart", "开机自动启动", True, $bAutoStart, "item")
	$i += 1
	$aSpec[$i] = _Tray_Entry("config_dir", "打开配置文件目录", True, False, "item")
	$i += 1
	$aSpec[$i] = _Tray_Entry("log", "打开日志", True, False, "item")
	$i += 1
	$aSpec[$i] = _Tray_Entry("sep_exit", "", True, False, "sep")
	$i += 1
	$aSpec[$i] = _Tray_Entry("exit", "退出", True, False, "item")
	Return $aSpec
EndFunc

Func _Tray_Entry($sId, $sText, $bEnabled, $bChecked, $sKind, $sParent = "")
	Local $o = ObjCreate("Scripting.Dictionary")
	$o.Item("id") = $sId
	$o.Item("text") = $sText
	$o.Item("enabled") = $bEnabled
	$o.Item("checked") = $bChecked
	$o.Item("kind") = $sKind
	$o.Item("parent") = $sParent
	Return $o
EndFunc

; ---- 开机自启：照 C# 的 HKCU Run 键 ----

Func Tray_AutoStartCommand()
	; 编译后注册 exe 本身；开发期注册"解释器 + 脚本"，否则开机跑的是 AutoIt3.exe
	If @Compiled Then Return '"' & @ScriptFullPath & '"'
	Return '"' & @AutoItExe & '" "' & @ScriptFullPath & '"'
EndFunc

Func Tray_IsAutoStart($sValueName = $TRAY_RUN_VALUE)
	RegRead($TRAY_RUN_KEY, $sValueName)
	Return @error = 0
EndFunc

Func Tray_SetAutoStart($bEnable, $sValueName = $TRAY_RUN_VALUE, $sCommand = "")
	If $bEnable Then
		If $sCommand = "" Then $sCommand = Tray_AutoStartCommand()
		If RegWrite($TRAY_RUN_KEY, $sValueName, "REG_SZ", $sCommand) = 0 Then
			U_Log("设置开机自启失败")
			Return False
		EndIf
	Else
		; 值本来就不存在时 RegDelete 也返回 0，不算失败
		RegDelete($TRAY_RUN_KEY, $sValueName)
	EndIf
	Return True
EndFunc

; ---- 托盘本体 ----

Func Tray_IconPath()
	Local $sDev = @ScriptDir & "\res\antnest.ico"
	If FileExists($sDev) Then Return $sDev
	Return U_ResourceDir() & "\antnest.ico"
EndFunc

Func Tray_Run($cfg)
	Opt("TrayMenuMode", 3)   ; 去掉默认的退出/暂停项，勾选状态由本程序控制
	Opt("TrayOnEventMode", 0) ; 用 TrayGetMsg 消息循环分派，不用阻塞轮询

	$g_trayCfg = IsObj($cfg) ? $cfg : Cfg_Load()
	$g_trayState = $TRAY_STATE_UNKNOWN
	$g_trayVersion = ""
	$g_trayDir = ""
	$g_trayExiting = False
	$g_trayChecking = False
	$g_trayFp = ""
	$g_trayFirst = True
	$g_trayLastMsg = ""
	$g_trayMenuSig = ""

	If @Compiled Then
		; 资源跟着 exe 走：Aut2Exe 命令行不能嵌文件，只能运行期释放
		If U_EnsureDir(U_ResourceDir()) Then FileInstall("res\antnest.ico", U_ResourceDir() & "\antnest.ico")
	EndIf
	TraySetIcon(Tray_IconPath())
	TraySetToolTip("Pi 多语言包")

	_Tray_PrimeState()
	_BuildMenu()
	Tray_RefreshMenu()

	Local $hGuard = TimerInit()
	Local $hStartupUpd = TimerInit()
	Local $hPeriodicUpd = TimerInit()
	Local $bStartupUpdDone = False

	While Not $g_trayExiting
		Local $iMsg = TrayGetMsg()
		Switch $iMsg
			Case 0
				; 无事件
			Case $g_trayIdInstall
				_Tray_DoInstall()
			Case $g_trayIdRestore
				_Tray_DoRestore()
			Case $g_trayIdLangZh
				_Tray_SwitchLang("zh-CN")
			Case $g_trayIdLangEn
				_Tray_SwitchLang("en-US")
			Case $g_trayIdUpdate
				_Tray_CheckUpdates(True)
			Case $g_trayIdAutoStart
				_Tray_ToggleAutoStart()
			Case $g_trayIdConfigDir
				U_ShellOpenDir(U_ConfigDir())
			Case $g_trayIdLog
				If FileExists(U_LogPath()) Then U_ShellOpen(U_LogPath())
			Case $g_trayIdExit
				_Tray_Exit()
			Case $TRAY_EVENT_PRIMARYDOUBLE
				_Tray_ShowStatusBalloon()
		EndSwitch
		If $g_trayExiting Then ExitLoop

		If TimerDiff($hGuard) >= 2000 Then
			$hGuard = TimerInit()
			_Tray_GuardTick()
		EndIf

		If Not $bStartupUpdDone And TimerDiff($hStartupUpd) >= 15000 Then
			$bStartupUpdDone = True
			If _Tray_ShouldCheckNow($g_trayCfg) Then _Tray_CheckUpdates(False)
		EndIf

		If TimerDiff($hPeriodicUpd) >= 30 * 60 * 1000 Then
			$hPeriodicUpd = TimerInit()
			; 周期检查前重读配置，别拿半小时前的开关做决定
			$g_trayCfg = Cfg_Load()
			If _Tray_ShouldCheckNow($g_trayCfg) Then _Tray_CheckUpdates(False)
		EndIf
	WEnd

	TraySetState($TRAY_ICONSTATE_HIDE)
EndFunc

Func _Tray_PrimeState()
	Local $sDir = Json_GetStr($g_trayCfg, "installPath", "")
	If $sDir = "" Or Not Loc_IsValid($sDir) Then
		Local $sFound = Loc_Find($g_trayCfg)
		If $sFound <> "" Then
			Json_Set($g_trayCfg, "installPath", $sFound)
			$sDir = $sFound
		EndIf
	EndIf
	$g_trayDir = $sDir
	; 自启的真实状态在注册表里，同步回配置，避免 config.json 显示过期的值
	Json_Set($g_trayCfg, "autoStart", Tray_IsAutoStart())
	Cfg_Save($g_trayCfg)

	$g_trayState = Patch_State($g_trayCfg)
	If Loc_IsValid($sDir) Then
		Local $oAsar = Asar_Open(Loc_AsarPath($sDir))
		If IsObj($oAsar) Then $g_trayVersion = Patch_ReadAppVersion($oAsar)
	EndIf
EndFunc

Func _BuildMenu()
	$g_trayMenuItems = _Tray_CreateMenu(Tray_MenuSpec($g_trayState, $g_trayVersion, $g_trayDir, _
			Json_GetStr($g_trayCfg, "locale", "zh-CN"), Tray_IsAutoStart(), $g_trayChecking))
	$g_trayIdStatus = $g_trayMenuItems.Item("status")
	$g_trayIdInstall = $g_trayMenuItems.Item("install")
	$g_trayIdRestore = $g_trayMenuItems.Item("restore")
	$g_trayIdLangZh = $g_trayMenuItems.Item("lang_zh")
	$g_trayIdLangEn = $g_trayMenuItems.Item("lang_en")
	$g_trayIdUpdate = $g_trayMenuItems.Item("update")
	$g_trayIdAutoStart = $g_trayMenuItems.Item("autostart")
	$g_trayIdConfigDir = $g_trayMenuItems.Item("config_dir")
	$g_trayIdLog = $g_trayMenuItems.Item("log")
	$g_trayIdExit = $g_trayMenuItems.Item("exit")
EndFunc

Func _Tray_CreateMenu($aSpec)
	Local $oItems = ObjCreate("Scripting.Dictionary")
	For $i = 0 To UBound($aSpec) - 1
		Local $e = $aSpec[$i]
		Local $hItem = -1
		Switch $e.Item("kind")
			Case "sep"
				$hItem = TrayCreateItem("")
			Case "submenu"
				$hItem = TrayCreateMenu($e.Item("text"))
			Case "subitem"
				$hItem = TrayCreateItem($e.Item("text"), $oItems.Item($e.Item("parent")))
			Case Else
				$hItem = TrayCreateItem($e.Item("text"))
		EndSwitch
		$oItems.Item($e.Item("id")) = $hItem
	Next
	Return $oItems
EndFunc

; AU3 托盘菜单没有"菜单打开"事件，所以状态由 2 秒守护定时器顺带刷新；
; 用签名跳过没变化的写入，避免菜单开着时反复重设造成闪烁。
Func Tray_RefreshMenu()
	If Not IsObj($g_trayCfg) Or Not IsObj($g_trayMenuItems) Then Return
	Local $aSpec = Tray_MenuSpec($g_trayState, $g_trayVersion, $g_trayDir, _
			Json_GetStr($g_trayCfg, "locale", "zh-CN"), Tray_IsAutoStart(), $g_trayChecking)
	Local $sSig = _Tray_SpecSignature($aSpec)
	If $sSig = $g_trayMenuSig Then Return
	$g_trayMenuSig = $sSig
	_Tray_ApplySpec($aSpec)
	TraySetToolTip(Tray_IconText($g_trayState))
EndFunc

Func _Tray_SpecSignature($aSpec)
	Local $s = ""
	For $i = 0 To UBound($aSpec) - 1
		$s &= $aSpec[$i].Item("id") & "|" & $aSpec[$i].Item("text") & "|" & _
				$aSpec[$i].Item("enabled") & "|" & $aSpec[$i].Item("checked") & @LF
	Next
	Return $s
EndFunc

Func _Tray_ApplySpec($aSpec)
	For $i = 0 To UBound($aSpec) - 1
		Local $e = $aSpec[$i]
		If $e.Item("kind") = "sep" Then ContinueLoop
		Local $hItem = $g_trayMenuItems.Item($e.Item("id"))
		TrayItemSetText($hItem, $e.Item("text"))
		; 可用性和勾选合成一次调用，分开设可能互相覆盖
		Local $iState = $e.Item("enabled") ? $TRAY_ENABLE : $TRAY_DISABLE
		$iState += $e.Item("checked") ? $TRAY_CHECKED : $TRAY_UNCHECKED
		TrayItemSetState($hItem, $iState)
	Next
EndFunc

Func _Tray_GuardTick()
	; CLI（--restore / --lang）可能在另一个进程里改过配置，这里必须重新读磁盘，
	; 否则会把用户刚做的还原又自动打回去。
	$g_trayCfg = Cfg_Load()

	; 词表在线更新后，等 Pi Node 退出再把新词表打进界面
	If Json_GetBool($g_trayCfg, "pendingRepatch", False) And Not Patch_IsAppRunning() Then
		Local $oRepatch = Patch_Install($g_trayCfg, Lang_Load(Json_GetStr($g_trayCfg, "locale", "zh-CN")))
		If _Tray_IsOk($oRepatch) Then
			Json_Set($g_trayCfg, "pendingRepatch", False)
			Cfg_Save($g_trayCfg)
			U_Log("词表更新后已重新打补丁")
		EndIf
	EndIf

	$g_trayDir = Loc_Find($g_trayCfg)
	If Not Loc_IsValid($g_trayDir) Then
		Tray_RefreshMenu()
		Return
	EndIf

	; 只盯 app.asar 的大小和修改时间：变了才做完整检查，平时 2 秒一次 stat
	Local $sAsar = Loc_AsarPath($g_trayDir)
	Local $sFp = U_FileSize($sAsar) & "|" & U_FileTicks($sAsar)
	If Not $g_trayFirst And $sFp = $g_trayFp Then
		Tray_RefreshMenu()
		Return
	EndIf
	$g_trayFp = $sFp
	$g_trayFirst = False

	Local $oResult = Patch_Ensure($g_trayCfg, Lang_Load(Json_GetStr($g_trayCfg, "locale", "zh-CN")))
	Local $bOk = _Tray_IsOk($oResult)
	Local $sMessage = Json_GetStr($oResult, "message", "")
	If Not $bOk Then $sMessage = "自动汉化失败：" & $sMessage
	If $sMessage <> $g_trayLastMsg Then
		$g_trayLastMsg = $sMessage
		$g_trayState = Patch_State($g_trayCfg)
		If $bOk And StringLeft($sMessage, 3) = "已安装" Then
			U_Log("守护自动重打：" & $sMessage)
			TrayTip("Pi 多语言包", "检测到 Pi Network 更新，已自动重新汉化。重启 Pi Network 后生效。", 6, $TIP_ICONASTERISK)
		EndIf
	EndIf
	Tray_RefreshMenu()
EndFunc

Func _Tray_DoInstall()
	$g_trayCfg = Cfg_Load()
	Local $oResult = Patch_Install($g_trayCfg, Lang_Load(Json_GetStr($g_trayCfg, "locale", "zh-CN")))
	Local $bOk = _Tray_IsOk($oResult)
	If $bOk Then
		$g_trayState = $TRAY_STATE_PATCHED
		Local $sVersion = Json_GetStr($oResult, "version", "")
		If $sVersion <> "" Then $g_trayVersion = $sVersion
	EndIf
	Tray_RefreshMenu()
	MsgBox($MB_OK + $MB_SYSTEMMODAL + ($bOk ? $MB_ICONINFORMATION : $MB_ICONWARNING), "Pi 多语言包", _
			Json_GetStr($oResult, "message", ""))
EndFunc

Func _Tray_DoRestore()
	$g_trayCfg = Cfg_Load()
	Local $oResult = Patch_Restore($g_trayCfg)
	Local $bOk = _Tray_IsOk($oResult)
	If $bOk Then $g_trayState = $TRAY_STATE_CLEAN
	Tray_RefreshMenu()
	MsgBox($MB_OK + $MB_SYSTEMMODAL + ($bOk ? $MB_ICONINFORMATION : $MB_ICONWARNING), "Pi 多语言包", _
			Json_GetStr($oResult, "message", ""))
EndFunc

Func _Tray_SwitchLang($sLocale)
	$g_trayCfg = Cfg_Load()
	If Json_GetStr($g_trayCfg, "locale", "zh-CN") = $sLocale Then Return
	Json_Set($g_trayCfg, "locale", $sLocale)
	Cfg_Save($g_trayCfg)

	If $g_trayState = $TRAY_STATE_PATCHED Then
		Local $oResult = Patch_Install($g_trayCfg, Lang_Load($sLocale))
		Local $bOk = _Tray_IsOk($oResult)
		MsgBox($MB_OK + $MB_SYSTEMMODAL + ($bOk ? $MB_ICONINFORMATION : $MB_ICONWARNING), "Pi 多语言包", _
				$bOk ? "语言已切换，重启 Pi Network 生效。" : Json_GetStr($oResult, "message", ""))
	EndIf
	Tray_RefreshMenu()
EndFunc

Func _Tray_ToggleAutoStart()
	$g_trayCfg = Cfg_Load()
	Local $bEnable = Not Tray_IsAutoStart()
	Tray_SetAutoStart($bEnable)
	Json_Set($g_trayCfg, "autoStart", $bEnable)
	Cfg_Save($g_trayCfg)
	Tray_RefreshMenu()
EndFunc

Func _Tray_CheckUpdates($bManual)
	If $g_trayChecking Then Return
	If Not IsFunc("Upd_CheckAndApply") Then
		If $bManual Then MsgBox($MB_OK + $MB_SYSTEMMODAL + $MB_ICONWARNING, "Pi 多语言包", "更新模块不可用。")
		Return
	EndIf

	$g_trayChecking = True
	Tray_RefreshMenu()
	$g_trayCfg = Cfg_Load()
	; 手动检查时弹进度小窗（UpdateForm.au3）；自动检查不打扰用户。
	; 模块间不互相 include，用 Call 调：函数不存在时 Call 返回 0 不崩。
	If $bManual Then Call("UpdForm_Show")
	Local $oResult = Upd_CheckAndApply($g_trayCfg, "_Tray_UpdProgress")
	If $bManual Then Call("UpdForm_Close")
	$g_trayChecking = False
	TraySetToolTip(Tray_IconText($g_trayState))
	Tray_RefreshMenu()

	If Not IsObj($oResult) Then Return
	If $bManual Then
		MsgBox($MB_OK + $MB_SYSTEMMODAL + (_Tray_IsOk($oResult) ? $MB_ICONINFORMATION : $MB_ICONWARNING), _
				"Pi 多语言包", Json_GetStr($oResult, "message", ""))
	ElseIf Not _Tray_IsOk($oResult) Then
		U_Log("自动检查更新：" & Json_GetStr($oResult, "message", ""))
	EndIf

	If Json_GetBool($oResult, "langUpdated", False) Then
		$g_trayCfg = Cfg_Load()
		$g_trayState = Patch_State($g_trayCfg)
		Tray_RefreshMenu()
		TrayTip("Pi 多语言包", "词表已更新并重新汉化，重启 Pi Network 后生效。", 6, $TIP_ICONASTERISK)
	EndIf

	If Json_GetBool($oResult, "appUpdated", False) Then
		TrayTip("Pi 多语言包", "程序已更新，正在重启…", 6, $TIP_ICONASTERISK)
		Sleep(1200)
		_Tray_Exit()
	EndIf
EndFunc

Func _Tray_UpdProgress($sStage, $iPercent)
	Local $s = "Pi 多语言包：" & $sStage
	If $iPercent > 0 Then $s &= " " & $iPercent & "%"
	TraySetToolTip($s)
	Call("UpdForm_Report", $sStage, $iPercent)
EndFunc

Func _Tray_ShouldCheckNow($cfg)
	If Not IsFunc("Upd_ShouldCheckNow") Then Return False
	Return Upd_ShouldCheckNow($cfg)
EndFunc

Func _Tray_IsOk($oResult)
	If Not IsObj($oResult) Then Return False
	Return Json_GetBool($oResult, "ok", False)
EndFunc

Func _Tray_ShowStatusBalloon()
	TrayTip("Pi 多语言包", Tray_StatusBalloon($g_trayState, $g_trayVersion), 4, $TIP_ICONASTERISK)
EndFunc

Func _Tray_Exit()
	If $g_trayExiting Then Return
	$g_trayExiting = True
	TraySetState($TRAY_ICONSTATE_HIDE)
EndFunc
