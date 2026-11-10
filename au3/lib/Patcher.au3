#include-once
#include <FileConstants.au3>

; 安装 / 还原 / 状态判定。所有写 asar 的入口都在这里串起来。
;
; 状态机：cfg.desiredState
;   zh       应该汉化，守护发现被官方更新覆盖后自动重打
;   restored 用户主动还原英文，守护不许再打（否则"点还原后两秒被打回中文"）
;   paused   守护暂停但仍记住期望
; 判定"官方更新过"用 cfg.appliedAsarHash 与当前 asar 的 SHA256 对比。

Global Const $PATCH_STATE_PATCHED = "patched"
Global Const $PATCH_STATE_CLEAN = "notpatched"
Global Const $PATCH_STATE_MISSING = "missing"
Global Const $PATCH_STATE_UNKNOWN = "unknown"

Global Const $PATCH_MUTEX_NAME = "Local\pi-lang-asar-write"
Global Const $PATCH_WAIT_MS = 30000

Func _Patch_Result($bOk, $sMessage, $sVersion = "")
	Local $o = Json_NewObject()
	$o.Item("ok") = $bOk
	$o.Item("message") = $sMessage
	$o.Item("version") = $sVersion
	Return $o
EndFunc

Func Patch_IsAppRunning()
	Return U_ProcessRunning($LOC_PROCESS_NAME)
EndFunc

Func Patch_State($oCfg)
	Local $sDir = Loc_Find($oCfg)
	If Not Loc_IsValid($sDir) Then Return $PATCH_STATE_MISSING
	Local $sAsar = Loc_AsarPath($sDir)

	; 快路径：header 原文里没有 pi-lang.js 条目就不用解析整棵树（省 ~400ms，
	; 托盘菜单打开时要立刻出状态）
	Local $oFast = Asar_Open($sAsar, False)
	If Not IsObj($oFast) Then
		U_Log("读取 asar 状态失败")
		Return $PATCH_STATE_UNKNOWN
	EndIf
	If Not Asar_HasNameInHeader($oFast, "pi-lang.js") Then Return $PATCH_STATE_CLEAN

	Local $o = Asar_Open($sAsar)
	If Not IsObj($o) Then Return $PATCH_STATE_UNKNOWN
	If Asar_IsPatched($o, $INJ_SCRIPT_PATH) Then Return $PATCH_STATE_PATCHED
	Return $PATCH_STATE_CLEAN
EndFunc

Func Patch_ReadAppVersion($oAsar)
	Local $s = Asar_ReadText($oAsar, "package.json")
	If @error Then Return ""
	Local $o = Json_Parse($s)
	If Not IsObj($o) Then Return ""
	Return Json_GetStr($o, "version", "")
EndFunc

; 进程检查放在对外入口：写 asar 时 Pi 正在用会把界面文件写坏。
; 内部 *_Core 只做纯逻辑，自检/排障可以直接调用而不受当前进程影响。
Func Patch_Install($oCfg, $oPack)
	If Patch_IsAppRunning() Then Return _Patch_Result(False, "Pi Network 正在运行，请先完全退出（托盘图标也要退出）")
	Local $hMutex = _Patch_Lock()
	If $hMutex = 0 Then Return _Patch_Result(False, "另一个操作正在进行，请稍后再试")
	Local $oResult = _Patch_InstallCore($oCfg, $oPack)
	_Patch_Unlock($hMutex)
	Return $oResult
EndFunc

Func _Patch_InstallCore($oCfg, $oPack)
	Local $sDir = Loc_Find($oCfg)
	If Not Loc_IsValid($sDir) Then Return _Patch_Result(False, "找不到 Pi Network 安装目录")

	Local $sAsarPath = Loc_AsarPath($sDir)
	Local $oAsar = Asar_Open($sAsarPath)
	If Not IsObj($oAsar) Then Return _Patch_Result(False, "读取 app.asar 失败（文件可能损坏，错误码 " & @error & "）")

	Local $sVersion = Patch_ReadAppVersion($oAsar)
	If Not _Patch_Backup($sAsarPath, $sVersion) Then
		U_Log("备份 app.asar 失败，放弃安装")
		Return _Patch_Result(False, "备份 app.asar 失败，已放弃安装（不会改动原文件）")
	EndIf

	Inj_EnsureResources()
	Local $sScript = Inj_BuildScript($oPack)
	If $sScript = "" Then Return _Patch_Result(False, "生成注入脚本失败（模板缺失？）")

	Local $sHtml = Asar_ReadText($oAsar, $INJ_INDEX_PATH)
	If @error Then Return _Patch_Result(False, "读取 index.html 失败，补丁未写入（Pi Network 版本结构可能变了）")
	Local $sNewHtml = Inj_PatchHtml($sHtml)
	If @error Then Return _Patch_Result(False, "index.html 里找不到 script 标签，补丁未写入（版本结构可能变了）")

	Local $sMainJs = Asar_ReadText($oAsar, $SP_MAINJS)
	If @error Then Return _Patch_Result(False, "读取 main.js 失败，补丁未写入")
	Local $sRendererJs = Asar_ReadText($oAsar, $SP_RENDERERJS)
	If @error Then Return _Patch_Result(False, "读取 renderer.js 失败，补丁未写入")

	Asar_PutFile($oAsar, $INJ_SCRIPT_PATH, StringToBinary($sScript, 4))
	Asar_PutFile($oAsar, $INJ_INDEX_PATH, StringToBinary($sNewHtml, 4))
	Asar_PutFile($oAsar, $SP_MAINJS, StringToBinary(SP_ApplyMain($sMainJs), 4))
	Asar_PutFile($oAsar, $SP_RENDERERJS, StringToBinary(SP_ApplyRenderer($sRendererJs), 4))

	If Not Asar_Save($oAsar, $sAsarPath) Then
		U_Log("写入 app.asar 失败，错误码 " & @error)
		Return _Patch_Result(False, "写入 app.asar 失败（错误码 " & @error & "），原文件未被替换")
	EndIf

	Json_Set($oCfg, "installPath", $sDir)
	Json_Set($oCfg, "appliedAsarHash", U_Sha256File($sAsarPath))
	Json_Set($oCfg, "lastPatchVersion", $sVersion)
	Json_Set($oCfg, "desiredState", $CFG_STATE_ZH)
	Cfg_Save($oCfg)

	U_Log("已安装中文补丁，Pi Network " & $sVersion & "，asar 指纹 " & StringLeft(Json_GetStr($oCfg, "appliedAsarHash", ""), 12))
	Return _Patch_Result(True, "已安装中文补丁（Pi Network " & $sVersion & "）", $sVersion)
EndFunc

Func Patch_Restore($oCfg)
	If Patch_IsAppRunning() Then Return _Patch_Result(False, "Pi Network 正在运行，请先完全退出")
	Local $hMutex = _Patch_Lock()
	If $hMutex = 0 Then Return _Patch_Result(False, "另一个操作正在进行，请稍后再试")
	Local $oResult = _Patch_RestoreCore($oCfg)
	_Patch_Unlock($hMutex)
	Return $oResult
EndFunc

Func _Patch_RestoreCore($oCfg)
	Local $sDir = Loc_Find($oCfg)
	If Not Loc_IsValid($sDir) Then Return _Patch_Result(False, "找不到 Pi Network 安装目录")

	Local $sAsarPath = Loc_AsarPath($sDir)
	Local $sVersion = ""
	Local $oProbe = Asar_Open($sAsarPath)
	If IsObj($oProbe) Then $sVersion = Patch_ReadAppVersion($oProbe)

	Local $sBackup = U_BackupDir() & "\app.asar." & ($sVersion = "" ? "unknown" : $sVersion) & ".orig"
	If FileExists($sBackup) Then
		; 整包备份优先：静态替换过的 main.js/renderer.js 也能一并还原
		If Not FileCopy($sBackup, $sAsarPath, 1) Then
			U_Log("用备份还原 app.asar 失败")
			Return _Patch_Result(False, "还原 app.asar 失败（备份文件可能被占用）")
		EndIf
	Else
		; 备份丢了就尽量就地还原（菜单/弹窗文案可能残留中文）
		If Not IsObj($oProbe) Then Return _Patch_Result(False, "还原 app.asar 失败（读不到文件）")
		If Asar_IsPatched($oProbe, $INJ_SCRIPT_PATH) Then
			Asar_RemoveFile($oProbe, $INJ_SCRIPT_PATH)
			Local $sHtml = Asar_ReadText($oProbe, $INJ_INDEX_PATH)
			Asar_PutFile($oProbe, $INJ_INDEX_PATH, StringToBinary(Inj_UnpatchHtml($sHtml), 4))
			Asar_PutFile($oProbe, $SP_MAINJS, StringToBinary(SP_RevertMain(Asar_ReadText($oProbe, $SP_MAINJS)), 4))
			Asar_PutFile($oProbe, $SP_RENDERERJS, StringToBinary(SP_RevertRenderer(Asar_ReadText($oProbe, $SP_RENDERERJS)), 4))
			If Not Asar_Save($oProbe, $sAsarPath) Then
				U_Log("就地还原 app.asar 失败，错误码 " & @error)
				Return _Patch_Result(False, "还原 app.asar 失败（错误码 " & @error & "）")
			EndIf
		EndIf
	EndIf

	Json_Set($oCfg, "desiredState", $CFG_STATE_RESTORED)
	Json_Set($oCfg, "appliedAsarHash", "")
	Cfg_Save($oCfg)
	U_Log("已还原英文原版")
	Return _Patch_Result(True, "已还原英文原版")
EndFunc

; 守护用的幂等入口：按 desiredState 决定该不该打
Func Patch_Ensure($oCfg, $oPack)
	Local $sDir = Loc_Find($oCfg)
	If Not Loc_IsValid($sDir) Then Return _Patch_Result(False, "找不到 Pi Network 安装目录")

	Local $sDesired = Json_GetStr($oCfg, "desiredState", $CFG_STATE_ZH)
	If $sDesired = $CFG_STATE_RESTORED Then Return _Patch_Result(True, "已还原英文，守护不自动汉化")
	If $sDesired = $CFG_STATE_PAUSED Or Not Json_GetBool($oCfg, "guardEnabled", True) Then
		Return _Patch_Result(True, "守护已暂停")
	EndIf

	Local $sState = Patch_State($oCfg)
	Local $bNeedInstall = False
	If $sState = $PATCH_STATE_PATCHED Then
		Local $sHash = U_Sha256File(Loc_AsarPath($sDir))
		Local $sApplied = Json_GetStr($oCfg, "appliedAsarHash", "")
		If $sApplied <> "" And $sHash <> $sApplied Then
			; 文件被外部换过（官方更新），重打
			$bNeedInstall = True
		Else
			Return _Patch_Result(True, "已汉化")
		EndIf
	ElseIf $sState = $PATCH_STATE_UNKNOWN Then
		Return _Patch_Result(False, "app.asar 状态异常，跳过自动汉化")
	Else
		$bNeedInstall = True
	EndIf

	; Pi 正开着就不动文件，等它退出：这不是错误，守护会一直重试
	If $bNeedInstall And Patch_IsAppRunning() Then Return _Patch_Result(True, "Pi Network 正在运行，等它退出后再自动汉化")
	Return _Patch_InstallCore($oCfg, $oPack)
EndFunc

; 备份最近 3 个版本，避免每次官方更新都堆 25MB
Func _Patch_Backup($sAsarPath, $sVersion)
	U_EnsureDir(U_BackupDir())
	Local $sTarget = U_BackupDir() & "\app.asar." & ($sVersion = "" ? "unknown" : $sVersion) & ".orig"
	If FileExists($sTarget) Then Return True

	Local $aFiles[1] = [""]
	Local $n = 0
	Local $hFind = FileFindFirstFile(U_BackupDir() & "\app.asar.*.orig")
	If $hFind <> -1 Then
		While True
			Local $sName = FileFindNextFile($hFind)
			If @error Then ExitLoop
			ReDim $aFiles[$n + 1]
			$aFiles[$n] = U_BackupDir() & "\" & $sName
			$n += 1
		WEnd
		FileClose($hFind)
	EndIf

	; 按修改时间从新到旧排序，只留 2 个旧的（再加这次备份共 3 个）
	Local $i, $j
	For $i = 0 To $n - 2
		For $j = 0 To $n - 2 - $i
			If FileGetTime($aFiles[$j], 0, 1) < FileGetTime($aFiles[$j + 1], 0, 1) Then
				Local $t = $aFiles[$j]
				$aFiles[$j] = $aFiles[$j + 1]
				$aFiles[$j + 1] = $t
			EndIf
		Next
	Next
	For $i = 2 To $n - 1
		FileDelete($aFiles[$i])
	Next

	Return FileCopy($sAsarPath, $sTarget)
EndFunc

; 跨进程互斥：托盘守护和命令行可能同时改 app.asar。Windows Mutex 同线程可重入，
; Ensure 内部再调 Install 不会死锁。
Func _Patch_Lock()
	Local $aCreate = DllCall("kernel32.dll", "handle", "CreateMutexW", "ptr", 0, "bool", False, "wstr", $PATCH_MUTEX_NAME)
	If @error Then Return 0
	Local $h = $aCreate[0]
	Local $aWait = DllCall("kernel32.dll", "dword", "WaitForSingleObject", "handle", $h, "dword", $PATCH_WAIT_MS)
	If @error Or $aWait[0] <> 0 Then ; WAIT_OBJECT_0 = 0
		DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
		Return 0
	EndIf
	Return $h
EndFunc

Func _Patch_Unlock($hMutex)
	DllCall("kernel32.dll", "bool", "ReleaseMutex", "handle", $hMutex)
	DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $hMutex)
EndFunc
