#include-once

; 找 Pi Network 安装目录：配置里记的 → 卸载注册表 DisplayIcon → 默认安装路径。

Global Const $LOC_PROCESS_NAME = "Pi Network.exe"

Func Loc_IsValid($sDir)
	If $sDir = "" Then Return False
	Return FileExists($sDir & "\resources\app.asar")
EndFunc

Func Loc_AsarPath($sDir)
	Return $sDir & "\resources\app.asar"
EndFunc

Func Loc_Find($oCfg)
	Local $sCfgDir = Json_GetStr($oCfg, "installPath", "")
	If Loc_IsValid($sCfgDir) Then Return $sCfgDir

	; 64 位进程读 HKLM\Software 不会重定向；32 位会进 WOW6432Node，两处都试
	Local $aRoots[3] = [ _
		"HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall", _
		"HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall", _
		"HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" _
	]
	Local $i
	For $i = 0 To UBound($aRoots) - 1
		Local $sFound = _Loc_FromUninstall($aRoots[$i])
		If $sFound <> "" Then Return $sFound
	Next

	Local $sFallback = @LocalAppDataDir & "\Programs\pi-network-desktop"
	If Loc_IsValid($sFallback) Then Return $sFallback
	Return ""
EndFunc

Func _Loc_FromUninstall($sRoot)
	Local $i
	For $i = 1 To 512
		Local $sName = RegEnumKey($sRoot, $i)
		If @error Then ExitLoop
		Local $sKey = $sRoot & "\" & $sName
		Local $sDisplay = RegRead($sKey, "DisplayName")
		If @error Then ContinueLoop
		If StringInStr($sDisplay, "Pi Network", 2) = 0 Then ContinueLoop
		Local $sIcon = RegRead($sKey, "DisplayIcon")
		If @error Or $sIcon = "" Then ContinueLoop
		; DisplayIcon 形如 "C:\...\Pi Network.exe,0"
		Local $aParts = StringSplit($sIcon, ",")
		Local $sExe = $aParts[1]
		$sExe = StringStripWS($sExe, 3)
		$sExe = StringTrimLeft($sExe, StringInStr($sExe, '"') = 1 ? 1 : 0)
		$sExe = StringTrimRight($sExe, StringRight($sExe, 1) = '"' ? 1 : 0)
		Local $iSlash = StringInStr($sExe, "\", 0, -1)
		If $iSlash <= 1 Then ContinueLoop
		Local $sDir = StringLeft($sExe, $iSlash - 1)
		If Loc_IsValid($sDir) Then Return $sDir
	Next
	Return ""
EndFunc
