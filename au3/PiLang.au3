#include-once

; 主入口：无参数常驻托盘，有参数走命令行。
; include 顺序不能乱：lib 之间不互相 include，全靠这里按依赖顺序引入。

#include <Misc.au3>

#include "lib\Util.au3"
#include "lib\Json.au3"
#include "lib\Asar.au3"
#include "lib\Config.au3"
#include "lib\Locator.au3"
#include "lib\LangPack.au3"
#include "lib\StaticPatches.au3"
#include "lib\Injector.au3"
#include "lib\Patcher.au3"
#include "lib\Tray.au3"
#include "lib\Updater.au3"
#include "lib\UpdateForm.au3"
#include "lib\SelfTest.au3"

Global Const $APP_TITLE = "Pi 多语言包"
Global Const $APP_MUTEX = "Local\pi-lang-pack"

; 资源随 exe 走：编译后 @ScriptDir 里没有 res\，词表和注入模板必须在这里释放出来，
; 否则 LangPack/Injector 会找不到内置资源（开发期直跑 .au3 时这步是多余的但无害）
Func _InstallResources()
	U_EnsureDir(U_ResourceDir())
	FileInstall("res\zh-CN.json", U_ResourceDir() & "\zh-CN.json", 1)
	FileInstall("res\pi-lang.js.template", U_ResourceDir() & "\pi-lang.js.template", 1)
	FileInstall("res\antnest.ico", U_ResourceDir() & "\antnest.ico", 1)
EndFunc

Func _Main()
	_InstallResources()
	If $CmdLine[0] > 0 Then Return _RunCli()

	; 托盘单实例：已在跑就静默退出
	If _Singleton($APP_MUTEX, 1) = 0 Then Return 0

	Local $oCfg = Cfg_Load()
	Lang_SeedIfMissing()

	If Not Loc_IsValid(Json_GetStr($oCfg, "installPath", "")) Then
		Local $sFound = Loc_Find($oCfg)
		If $sFound <> "" Then
			Json_Set($oCfg, "installPath", $sFound)
			Cfg_Save($oCfg)
		EndIf
	EndIf

	Tray_Run($oCfg)
	Return 0
EndFunc

; 编译成 GUI 子系统的 exe 时没有自己的控制台，先挂到调用方的控制台，
; 这样 cmd 里跑 --status 才看得见输出
Func _AttachConsole()
	DllCall("kernel32.dll", "bool", "AttachConsole", "dword", 0xFFFFFFFF)
EndFunc

Func _RunCli()
	_AttachConsole()
	Local $oCfg = Cfg_Load()
	Lang_SeedIfMissing()

	; --dir 临时指定安装目录（验证副本 / 排障用），不写回配置
	Local $sDirArg = _CliOption("--dir")
	If $sDirArg <> "" And Loc_IsValid($sDirArg) Then Json_Set($oCfg, "installPath", $sDirArg)

	Local $sCmd = StringLower(StringRegExpReplace($CmdLine[1], "^-+", ""))
	Local $oPack = Lang_Load(Json_GetStr($oCfg, "locale", $CFG_LOCALE_ZH))
	Local $oResult

	Switch $sCmd
		Case "install"
			$oResult = Patch_Install($oCfg, $oPack)
			ConsoleWrite(Json_GetStr($oResult, "message") & @CRLF)
			Return Json_GetBool($oResult, "ok", False) ? 0 : 1
		Case "restore"
			$oResult = Patch_Restore($oCfg)
			ConsoleWrite(Json_GetStr($oResult, "message") & @CRLF)
			Return Json_GetBool($oResult, "ok", False) ? 0 : 1
		Case "ensure"
			$oResult = Patch_Ensure($oCfg, $oPack)
			If Not Json_GetBool($oResult, "ok", False) Then ConsoleWrite(Json_GetStr($oResult, "message") & @CRLF)
			Return Json_GetBool($oResult, "ok", False) ? 0 : 1
		Case "status"
			Return _CliStatus($oCfg, $oPack)
		Case "lang"
			If $CmdLine[0] < 2 Then
				ConsoleWrite("用法: --lang zh-CN | en-US" & @CRLF)
				Return 2
			EndIf
			Json_Set($oCfg, "locale", $CmdLine[2])
			Cfg_Save($oCfg)
			If Patch_State($oCfg) = $PATCH_STATE_PATCHED Then
				$oResult = Patch_Install($oCfg, Lang_Load($CmdLine[2]))
				ConsoleWrite(Json_GetStr($oResult, "message") & "（重启 Pi Network 生效）" & @CRLF)
				Return Json_GetBool($oResult, "ok", False) ? 0 : 1
			EndIf
			ConsoleWrite("语言已设为 " & $CmdLine[2] & @CRLF)
			Return 0
		Case "update"
			$oResult = Upd_CheckAndApply($oCfg)
			ConsoleWrite(Json_GetStr($oResult, "message") & @CRLF)
			If Json_GetBool($oResult, "appUpdated", False) Then ConsoleWrite("程序更新将在本进程退出后自动替换并重启。" & @CRLF)
			Return Json_GetBool($oResult, "ok", False) ? 0 : 1
		Case "selftest"
			Return ST_Run($oCfg, $oPack)
		Case Else
			ConsoleWrite("未知参数: " & $CmdLine[1] & @CRLF)
			ConsoleWrite("可用: --install --restore --ensure --status --lang <locale> --update --selftest" & @CRLF)
			Return 2
	EndSwitch
EndFunc

Func _CliStatus($oCfg, $oPack)
	Local $sDir = Loc_Find($oCfg)
	Local $sState = Patch_State($oCfg)
	Local $sStateText = $PATCH_STATE_PATCHED
	If $sState = $PATCH_STATE_CLEAN Then
		$sStateText = "未汉化"
	ElseIf $sState <> $PATCH_STATE_PATCHED Then
		$sStateText = $sState
	Else
		$sStateText = "已汉化"
	EndIf
	ConsoleWrite("安装目录 : " & ($sDir = "" ? "(未找到)" : $sDir) & @CRLF)
	ConsoleWrite("汉化状态 : " & $sStateText & @CRLF)
	ConsoleWrite("期望状态 : " & Json_GetStr($oCfg, "desiredState") & @CRLF)
	ConsoleWrite("守护     : " & (Json_GetBool($oCfg, "guardEnabled", True) ? "开启" : "关闭") & @CRLF)
	ConsoleWrite("语言     : " & Json_GetStr($oCfg, "locale") & @CRLF)
	Local $oEntries = Json_Get($oPack, "entries")
	ConsoleWrite("词表     : " & ($oPack.Exists("entries") ? $oEntries.Count : 0) & " 条（" & Json_GetStr($oPack, "version") & "）" & @CRLF)
	Return 0
EndFunc

Func _CliOption($sName)
	Local $i
	For $i = 1 To $CmdLine[0] - 1
		If StringLower($CmdLine[$i]) = StringLower($sName) Then Return $CmdLine[$i + 1]
	Next
	Return ""
EndFunc

Exit(_Main())
