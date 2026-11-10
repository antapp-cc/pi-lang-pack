#include-once
#include <Date.au3>
#include <FileConstants.au3>
#include <WinAPIConv.au3>

; 在线更新：拉最新清单 → SHA256 校验 → 更新词表（自动重打）或替换程序本体（重启）。
;
; 与 C# 版的差异，都是 AU3 下的取舍：
;   - 程序版本号不 DllCall 读自身 exe 资源（绕且编译期易出错），用常量；
;     发新版时改 $UPD_APP_VERSION 并同步清单里的 app.version。
;   - 下载用 InetGet 后台句柄 + 自己计时：既能收到进度回调，又能用 InetClose 硬中断超时。
;     WinHttp COM 同步 Send 拿不到进度，异步事件循环更绕。
;   - 自替换批处理显式写 GBK(936)：cmd 按代码页解析中文路径，而系统 ANSI 代码页在英文
;     Windows 上是 1252，直接 $FO_ANSI 会把中文写成 ?。

; 与 GitHub 清单里现有的 C# 版保持同一个版本号（1.0.11）：两个实现在更新系统里等价，
; 谁也不会把谁替换掉。以后发新版必须把这里的版本号 +1，否则老用户判定"不比本机新"不更新
; （更新只比版本号，不比内容哈希）。
Global Const $UPD_APP_VERSION = "1.0.11"
Global Const $UPD_CHECK_INTERVAL_HOURS = 6
Global Const $UPD_MANIFEST_TIMEOUT_MS = 10000
Global Const $UPD_DOWNLOAD_TIMEOUT_MS = 300000
Global Const $UPD_MAX_ATTEMPTS = 3

; 自检/演练时置 True：仍会写出 PiLang.new.exe 与 update-runner.cmd，但不启动自替换，
; 避免把正在跑的 exe 换掉。也可用环境变量 PILANG_DRY_RUN=1 在运行期打开（测试用）。
Global $UPD_DRY_RUN = False

Func _Upd_DryRun()
	If $UPD_DRY_RUN Then Return True
	Return EnvGet("PILANG_DRY_RUN") = "1"
EndFunc

Func Upd_CurrentAppVersion()
	Return $UPD_APP_VERSION
EndFunc

; 自动检查：启动后一次、之后每 6 小时一次（记录在 config 里）
Func Upd_ShouldCheckNow($oCfg)
	If Not Json_GetBool($oCfg, "autoUpdate", True) Then Return False
	If Json_GetStr($oCfg, "updateUrl", "") = "" Then Return False
	Local $sLast = Json_GetStr($oCfg, "lastUpdateCheck", "")
	If $sLast = "" Then Return True
	Local $sCalc = _Upd_ParseIsoUtc($sLast)
	If $sCalc = "" Then Return True
	Return _DateDiff('s', $sCalc, _Upd_NowUtcCalc()) > $UPD_CHECK_INTERVAL_HOURS * 3600
EndFunc

Func Upd_CheckAndApply($oCfg, $fnProgress = 0)
	_Upd_Progress($fnProgress, "正在检查更新…", 0)

	Local $aSources = _Upd_AllowedSources($oCfg)
	If UBound($aSources) = 0 Then Return _Upd_Result(False, "没有配置有效的更新地址（必须是 https）")

	; 按配置顺序串行尝试：主源 404 会立刻失败，不会拖慢；
	; 不能并行"谁先到用谁"，否则可能用到 CDN 缓存着的旧清单。
	Local $oManifest = 0, $sLastErr = ""
	Local $i
	For $i = 0 To UBound($aSources) - 1
		Local $sErr = ""
		$oManifest = _Upd_FetchManifest($aSources[$i], $sErr)
		If IsObj($oManifest) Then ExitLoop
		$sLastErr = $sErr
		U_Log("更新源失败，尝试下一个：" & $aSources[$i] & " -> " & $sErr)
	Next
	If Not IsObj($oManifest) Then
		Return _Upd_Result(False, "无法连接更新服务器（网络超时或受限）。" & $sLastErr, False, False)
	EndIf

	Local $aChanged[0], $bAppUpdated = False, $bLangUpdated = False

	Local $oLang = _Upd_Field($oManifest, "lang")
	If IsObj($oLang) And _Upd_Field($oLang, "url") <> "" Then
		Local $oR = _Upd_ApplyLang($oLang, $oCfg, $fnProgress)
		If Not Json_GetBool($oR, "ok", False) Then Return _Upd_Result(False, Json_GetStr($oR, "message"), False, False)
		If Json_GetBool($oR, "updated", False) Then
			$bLangUpdated = True
			_U_ArrayAdd($aChanged, "词表已更新")
			U_Log("在线更新：词表已更新到 " & _Upd_Field($oLang, "version"))
		EndIf
	EndIf

	Local $oApp = _Upd_Field($oManifest, "app")
	If IsObj($oApp) And _Upd_Field($oApp, "url") <> "" And _Upd_IsNewer(_Upd_Field($oApp, "version"), Upd_CurrentAppVersion()) Then
		Local $oR2 = _Upd_ApplyApp($oApp, $fnProgress)
		If Not Json_GetBool($oR2, "ok", False) Then Return _Upd_Result(False, Json_GetStr($oR2, "message"), False, False)
		If Json_GetBool($oR2, "updated", False) Then
			$bAppUpdated = True
			_U_ArrayAdd($aChanged, "程序已更新到 " & _Upd_Field($oApp, "version"))
			U_Log("在线更新：程序已下载 " & _Upd_Field($oApp, "version") & "，等待替换")
		EndIf
	EndIf

	Json_Set($oCfg, "lastUpdateCheck", _Upd_NowUtcIso())
	_Upd_CfgSave($oCfg)

	If UBound($aChanged) = 0 Then Return _Upd_Result(True, "已是最新版本", False, False)

	Local $sMessage = ""
	For $i = 0 To UBound($aChanged) - 1
		If $i > 0 Then $sMessage &= "，"
		$sMessage &= $aChanged[$i]
	Next
	Return _Upd_Result(True, $sMessage, $bAppUpdated, $bLangUpdated)
EndFunc

; ---- 词表更新 ----

; 返回 "same"（本地已与清单一致）| "downgrade"（清单比已应用的旧）| ""（该下载）
Func _Upd_LangSkip($oInfo, $oCfg, $sLocalPath)
	Local $sSha = StringLower(StringStripWS(_Upd_Field($oInfo, "sha256"), 3))
	; 本地已和清单一致就不用下载（省流量，也避免无意义地重打补丁）
	If FileExists($sLocalPath) And $sSha <> "" Then
		If U_Sha256File($sLocalPath) = $sSha Then Return "same"
	EndIf

	; 防降级：GitHub raw 的 CDN 可能先把旧清单刷出来，旧清单会把新词表盖回去。
	; 清单里带 updatedAt，只接受比"上次应用时间"更新的清单。
	Local $sR = _Upd_ParseIsoUtc(_Upd_Field($oInfo, "updatedAt"))
	Local $sL = _Upd_ParseIsoUtc(Json_GetStr($oCfg, "lastLangUpdatedAt", ""))
	If $sR <> "" And $sL <> "" Then
		If _DateDiff('s', $sL, $sR) <= 0 Then Return "downgrade"
	EndIf
	Return ""
EndFunc

Func _Upd_ApplyLang($oInfo, $oCfg, $fnProgress)
	Local $sLocal = U_LangDir() & "\zh-CN.json"
	Local $sSha = StringLower(StringStripWS(_Upd_Field($oInfo, "sha256"), 3))

	Local $sSkip = _Upd_LangSkip($oInfo, $oCfg, $sLocal)
	If $sSkip = "same" Then Return _Upd_InnerResult(True, "词表已是最新", False)
	If $sSkip = "downgrade" Then
		U_Log("清单里的词表比已应用的旧（CDN 缓存未刷新），跳过降级")
		Return _Upd_InnerResult(True, "词表已是最新版", False)
	EndIf

	Local $sRemoteAt = _Upd_Field($oInfo, "updatedAt")
	Local $oDl = _Upd_DownloadVerified(_Upd_Field($oInfo, "url"), $sSha, $fnProgress, "正在下载词表")
	If Not Json_GetBool($oDl, "ok", False) Then Return _Upd_InnerResult(False, Json_GetStr($oDl, "message"), False)

	U_EnsureDir(U_LangDir())
	If Not FileCopy(Json_GetStr($oDl, "file"), $sLocal, 1) Then
		FileDelete(Json_GetStr($oDl, "file"))
		Return _Upd_InnerResult(False, "写入词表失败（" & $sLocal & " 不可写）", False)
	EndIf
	FileDelete(Json_GetStr($oDl, "file"))

	Json_Set($oCfg, "lastLangUpdatedAt", $sRemoteAt)
	; 词表换了，已汉化的界面要按新词表重打一次
	Json_Set($oCfg, "pendingRepatch", True)
	_Upd_TryRepatch($oCfg)
	_Upd_CfgSave($oCfg)
	Return _Upd_InnerResult(True, "词表已更新", True)
EndFunc

; Pi Node 没在跑就立刻重打，省得等守护；模块没加载或失败就留给守护（pendingRepatch）
Func _Upd_TryRepatch($oCfg)
	; 这几个函数由主脚本的 LangPack/Patcher 提供。Call 一个不存在的函数只会返回 0
	; 并置 @error（57005），不会中断脚本，所以自检环境里缺模块也能跑。
	Local $sFnRunning = "Patch_IsAppRunning", $sFnLoad = "Lang_Load", $sFnEnsure = "Patch_Ensure"
	If Call($sFnRunning) Then Return False
	Local $oPack = Call($sFnLoad, Json_GetStr($oCfg, "locale", "zh-CN"))
	If Not IsObj($oPack) Then Return False
	Local $oR = Call($sFnEnsure, $oCfg, $oPack)
	If IsObj($oR) And Json_GetBool($oR, "ok", False) Then
		Json_Set($oCfg, "pendingRepatch", False)
		Return True
	EndIf
	U_Log("词表更新后重打失败: " & (IsObj($oR) ? Json_GetStr($oR, "message", "未知错误") : "Patch_Ensure 无返回"))
	Return False
EndFunc

; ---- 程序更新 ----

Func _Upd_ApplyApp($oInfo, $fnProgress)
	Local $oDl = _Upd_DownloadVerified(_Upd_Field($oInfo, "url"), _Upd_Field($oInfo, "sha256"), $fnProgress, "正在下载程序")
	If Not Json_GetBool($oDl, "ok", False) Then Return _Upd_InnerResult(False, Json_GetStr($oDl, "message"), False)

	Local $sNewExe = U_UpdateDir() & "\PiLang.new.exe"
	Local $sTarget = @ScriptFullPath
	Local $sBatch = U_UpdateDir() & "\update-runner.cmd"
	If Not _Upd_StageAppFiles(Json_GetStr($oDl, "file"), $sNewExe, $sTarget, $sTarget & ".old", $sBatch) Then
		FileDelete(Json_GetStr($oDl, "file"))
		Return _Upd_InnerResult(False, "准备更新文件失败（" & U_UpdateDir() & " 不可写）", False)
	EndIf
	FileDelete(Json_GetStr($oDl, "file"))

	If Not _Upd_LaunchBatch($sBatch) Then Return _Upd_InnerResult(False, "启动更新程序失败", False)
	Return _Upd_InnerResult(True, "程序已下载，等待替换重启", True)
EndFunc

; 单独拆出来：自检要能在临时目录里演练"文件名 + 批处理内容"，但不执行替换
Func _Upd_StageAppFiles($sDownload, $sNewExe, $sTarget, $sBackup, $sBatch)
	If Not U_EnsureDir(U_UpdateDir()) Then Return False
	If Not FileCopy($sDownload, $sNewExe, 1) Then Return False
	Return _Upd_WriteBatch($sBatch, $sNewExe, $sTarget, $sBackup)
EndFunc

; 用批处理做自替换：等当前进程退出（copy 失败就重试）→ 备份旧 exe → 换新 → 启动 → 自删。
; 批处理只能是 GBK：cmd 按系统代码页读它，中文路径用 UTF-8 会变乱码导致复制失败。
Func _Upd_WriteBatch($sBatchPath, $sNewExe, $sTarget, $sBackup)
	Local $aLines[12] = [ _
		"@echo off", _
		"chcp 936 >nul", _
		"timeout /t 3 /nobreak >nul", _
		"set tries=0", _
		":retry", _
		"copy /Y """ & $sTarget & """ """ & $sBackup & """ >nul 2>&1", _
		"copy /Y """ & $sNewExe & """ """ & $sTarget & """ >nul 2>&1", _
		"if not errorlevel 1 goto done", _
		"set /a tries+=1", _
		"if %tries% geq 60 exit /b 1", _
		"timeout /t 1 /nobreak >nul & goto retry", _
		":done" _
	]
	Local $sText = ""
	Local $i
	For $i = 0 To UBound($aLines) - 1
		$sText &= $aLines[$i] & @CRLF
	Next
	$sText &= 'start "" "' & $sTarget & '"' & @CRLF
	$sText &= 'del "' & $sNewExe & '" >nul 2>&1' & @CRLF
	$sText &= 'del "%~f0" >nul 2>&1' & @CRLF

	; WideCharToMultiByte(-1) 会把结尾 NUL 也带上，cmd 会把 NUL 当命令的一部分报错
	Local $bGbk = _WinAPI_WideCharToMultiByte($sText, 936, True, True)
	If @error Or BinaryLen($bGbk) = 0 Then Return False
	If Hex(BinaryMid($bGbk, BinaryLen($bGbk), 1)) = "00" Then $bGbk = BinaryMid($bGbk, 1, BinaryLen($bGbk) - 1)
	Return U_WriteBinary($sBatchPath, $bGbk)
EndFunc

Func _Upd_LaunchBatch($sBatchPath)
	If _Upd_DryRun() Then
		U_Log("演练模式：已生成更新批处理但不启动（" & $sBatchPath & "）")
		Return True
	EndIf
	Local $iPid = Run(@ComSpec & ' /c "' & $sBatchPath & '"', "", @SW_HIDE)
	If $iPid = 0 Then
		U_Log("启动更新批处理失败：" & $sBatchPath)
		Return False
	EndIf
	Return True
EndFunc

; ---- 下载 ----

; 返回 {"ok":bool,"message":str,"file":str,"status":int}
Func _Upd_Download($sUrl, $sDest, $iTimeoutMs, $fnProgress, $sStage)
	FileDelete($sDest)
	Local $h = InetGet($sUrl, $sDest, 1, 1)
	If $h = 0 Or @error Then Return _Upd_DlResult(False, "启动下载失败（错误 " & @error & "）", 0)

	Local $t0 = TimerInit(), $a = 0, $iLastPct = -1
	While 1
		$a = InetGetInfo($h)
		If Not IsArray($a) Then
			InetClose($h)
			FileDelete($sDest)
			Return _Upd_DlResult(False, "下载状态异常", 0)
		EndIf
		If $a[2] Then ExitLoop
		If TimerDiff($t0) > $iTimeoutMs Then
			InetClose($h)
			FileDelete($sDest)
			Return _Upd_DlResult(False, "下载超时（超过 " & Round($iTimeoutMs / 1000) & " 秒）", 0)
		EndIf
		; 只有服务器给了 Content-Length 才能算百分比；chunked 时退回"已下载字节"阶段
		If $a[1] > 0 Then
			Local $iPct = Int($a[0] * 100 / $a[1])
			If $iPct <> $iLastPct Then
				$iLastPct = $iPct
				_Upd_Progress($fnProgress, $sStage, $iPct)
			EndIf
		EndIf
		Sleep(50)
	WEnd

	Local $bOk = $a[3], $iCode = $a[4], $iExt = $a[5]
	InetClose($h)
	If Not $bOk Then
		FileDelete($sDest)
		Return _Upd_DlResult(False, _Upd_HttpErrorText($iCode, $iExt), $iCode)
	EndIf
	If Not FileExists($sDest) Then Return _Upd_DlResult(False, "下载失败：没有生成文件", 0)
	_Upd_Progress($fnProgress, $sStage, 100)
	Local $oOk = _Upd_DlResult(True, "", 0)
	$oOk.Item("file") = $sDest
	Return $oOk
EndFunc

; 下载并校验 SHA256。CDN 缓存不同步时（清单旧、文件新）会重试；
; URL 带版本参数后同一版本不会串缓存。
Func _Upd_DownloadVerified($sUrl, $sExpectedSha, $fnProgress, $sStage)
	Local $sExpected = StringLower(StringStripWS($sExpectedSha, 3))
	Local $sTmp = _Upd_TempPath("download")
	Local $sLastErr = "下载失败"
	Local $i
	For $i = 1 To $UPD_MAX_ATTEMPTS
		Local $oDl = _Upd_Download(_Upd_AppendQuery($sUrl, "v=" & _Upd_ShortHash($sExpected)), $sTmp, $UPD_DOWNLOAD_TIMEOUT_MS, $fnProgress, $sStage)
		If Not Json_GetBool($oDl, "ok", False) Then
			$sLastErr = Json_GetStr($oDl, "message")
			U_Log("下载失败（第 " & $i & " 次）：" & $sUrl & " -> " & $sLastErr)
			If $i < $UPD_MAX_ATTEMPTS Then Sleep(1500)
			ContinueLoop
		EndIf
		If $sExpected = "" Or U_Sha256File($sTmp) = $sExpected Then Return $oDl
		$sLastErr = "下载内容 SHA256 与清单不一致，已拒绝更新（缓存可能还没刷新生效，稍后再试）"
		If $i < $UPD_MAX_ATTEMPTS Then
			U_Log("SHA 校验不一致，重试下载：" & $sUrl)
			Sleep(3000)
		EndIf
	Next
	FileDelete($sTmp)
	Return _Upd_DlResult(False, $sLastErr, 0)
EndFunc

; ---- 清单 ----

Func _Upd_FetchManifest($sUrl, ByRef $sErr)
	$sErr = ""
	Local $sTmp = _Upd_TempPath("manifest")
	Local $oDl = _Upd_Download(_Upd_AppendQuery($sUrl, "t=" & _Upd_UnixNow()), $sTmp, $UPD_MANIFEST_TIMEOUT_MS, 0, "")
	If Not Json_GetBool($oDl, "ok", False) Then
		$sErr = Json_GetStr($oDl, "message")
		Return 0
	EndIf
	Local $sText = U_ReadText($sTmp)
	FileDelete($sTmp)
	If $sText = "" Then
		$sErr = "更新清单是空的"
		Return 0
	EndIf
	Local $o = Json_Parse($sText)
	If Not IsObj($o) Then
		$sErr = "更新清单不是合法 JSON（更新地址可能指向了网页而不是 latest.json）"
		Return 0
	EndIf
	; Json_Parse 对残缺输入可能吐出半个空对象，所以再核对一眼清单结构
	If Not IsObj(_Upd_Field($o, "app")) And Not IsObj(_Upd_Field($o, "lang")) Then
		$sErr = "更新清单格式不对（没有 app / lang 字段，可能指错了文件）"
		Return 0
	EndIf
	Return $o
EndFunc

; 清单字段名按 C# 的 PropertyNameCaseInsensitive 行为处理：外部文件大小写不保证
Func _Upd_Field($oObj, $sKey, $sDefault = "")
	If Not IsObj($oObj) Then Return $sDefault
	If $oObj.Exists($sKey) Then Return _Upd_FieldValue($oObj.Item($sKey), $sDefault)
	Local $aKeys = $oObj.Keys()
	Local $i
	For $i = 0 To UBound($aKeys) - 1
		If StringLower($aKeys[$i]) = StringLower($sKey) Then Return _Upd_FieldValue($oObj.Item($aKeys[$i]), $sDefault)
	Next
	Return $sDefault
EndFunc

Func _Upd_FieldValue($v, $sDefault)
	If Json_IsNull($v) Then Return $sDefault
	If IsObj($v) Then Return $v
	If IsArray($v) Then Return $sDefault
	If IsBool($v) Then Return ($v ? "true" : "false")
	Return String($v)
EndFunc

; ---- 更新源 ----

Func _Upd_AllowedSources($oCfg)
	Local $aAll = _Upd_BuildSources(Json_GetStr($oCfg, "updateUrl", ""))
	Local $aOut[0]
	Local $i
	For $i = 0 To UBound($aAll) - 1
		If _Upd_IsAllowedUrl($aAll[$i]) Then _U_ArrayAdd($aOut, $aAll[$i])
	Next
	Return $aOut
EndFunc

; config 里可以用 ; , 换行配多个源；GitHub raw 自动补 jsDelivr 镜像（国内 raw 被墙时还能用）
Func _Upd_BuildSources($sRaw)
	Local $aList[0]
	If $sRaw <> "" Then
		Local $aParts = StringRegExp($sRaw, "[^;,\r\n]+", 3)
		If IsArray($aParts) Then
			Local $i
			For $i = 0 To UBound($aParts) - 1
				Local $sUrl = StringStripWS($aParts[$i], 3)
				If $sUrl <> "" Then _U_ArrayAdd($aList, $sUrl)
			Next
		EndIf
	EndIf

	Local $aMirrors[0]
	Local $i
	For $i = 0 To UBound($aList) - 1
		Local $sMirror = _Upd_JsDelivrMirror($aList[$i])
		If $sMirror <> "" Then _U_ArrayAdd($aMirrors, $sMirror)
	Next
	For $i = 0 To UBound($aMirrors) - 1
		If Not _U_ArrayHas($aList, $aMirrors[$i]) Then _U_ArrayAdd($aList, $aMirrors[$i])
	Next
	Return $aList
EndFunc

Func _Upd_JsDelivrMirror($sUrl)
	Local $sHost = "raw.githubusercontent.com/"
	Local $iPos = StringInStr($sUrl, $sHost, 2)
	If $iPos = 0 Then Return ""
	Local $sRest = StringMid($sUrl, $iPos + StringLen($sHost))
	; 等价于 C# 的 rest.Split('/', 4)：前 3 段是 owner/repo/ref，剩下全部是文件路径
	Local $aParts[4]
	Local $i
	For $i = 0 To 2
		Local $iSlash = StringInStr($sRest, "/")
		If $iSlash = 0 Then Return ""
		$aParts[$i] = StringLeft($sRest, $iSlash - 1)
		$sRest = StringMid($sRest, $iSlash + 1)
	Next
	$aParts[3] = $sRest
	If $aParts[0] = "" Or $aParts[1] = "" Or $aParts[2] = "" Or $aParts[3] = "" Then Return ""
	Return "https://cdn.jsdelivr.net/gh/" & $aParts[0] & "/" & $aParts[1] & "@" & $aParts[2] & "/" & $aParts[3]
EndFunc

; 只信任 https；http 只放行本机回环（本地起服务测更新用）
Func _Upd_IsAllowedUrl($sUrl)
	If $sUrl = "" Then Return False
	If StringRegExp($sUrl, "(?i)^https://[^\s/?#]+(/|\?|#|$)") Then Return True
	If StringRegExp($sUrl, "(?i)^http://(localhost|127\.0\.0\.1|\[::1\])(:\d{1,5})?(/|\?|#|$)") Then Return True
	Return False
EndFunc

; ---- 杂项 ----

Func _Upd_Result($bOk, $sMessage, $bAppUpdated = False, $bLangUpdated = False)
	Local $o = Json_NewObject()
	$o.Item("ok") = $bOk
	$o.Item("message") = $sMessage
	$o.Item("appUpdated") = $bAppUpdated
	$o.Item("langUpdated") = $bLangUpdated
	Return $o
EndFunc

Func _Upd_InnerResult($bOk, $sMessage, $bUpdated)
	Local $o = Json_NewObject()
	$o.Item("ok") = $bOk
	$o.Item("message") = $sMessage
	$o.Item("updated") = $bUpdated
	Return $o
EndFunc

Func _Upd_DlResult($bOk, $sMessage, $iStatus)
	Local $o = Json_NewObject()
	$o.Item("ok") = $bOk
	$o.Item("message") = $sMessage
	$o.Item("file") = ""
	$o.Item("status") = $iStatus
	Return $o
EndFunc

; $fnProgress 是函数变量（AutoIt 3.3.14+ 的函数引用）；为了宽荣也收字符串函数名。
; 0 / 空表示不回调。
Func _Upd_Progress($fnProgress, $sStage, $iPercent)
	If IsFunc($fnProgress) Then
		$fnProgress($sStage, $iPercent)
		Return
	EndIf
	If IsString($fnProgress) And $fnProgress <> "" Then Call($fnProgress, $sStage, $iPercent)
EndFunc

Func _Upd_CfgSave($oCfg)
	; Config.au3 缺席（单测/自检环境）时 Call 返回 0 并置 @error，不中断更新流程
	Local $sFn = "Cfg_Save"
	Call($sFn, $oCfg)
EndFunc

Func _Upd_TempPath($sTag)
	Return _Upd_UpdateDirSafe() & "\" & $sTag & "." & @AutoItPID & ".tmp"
EndFunc

Func _Upd_UpdateDirSafe()
	Local $sDir = U_UpdateDir()
	If U_EnsureDir($sDir) Then Return $sDir
	Return @TempDir
EndFunc

Func _Upd_AppendQuery($sUrl, $sQuery)
	If StringInStr($sUrl, "?") Then Return $sUrl & "&" & $sQuery
	Return $sUrl & "?" & $sQuery
EndFunc

Func _Upd_ShortHash($sSha)
	Local $s = StringStripWS($sSha, 3)
	If $s = "" Then Return String(_Upd_UnixNow())
	Return StringLeft($s, 16)
EndFunc

Func _Upd_UnixNow()
	Local $iSec = _DateDiff('s', "1970/01/01 00:00:00", _Upd_NowUtcCalc())
	If $iSec <= 0 Then Return 1
	Return $iSec
EndFunc

; UTC 就绪格式："2026/11/10 13:30:40"，可直接喂 _DateDiff/_DateAdd
Func _Upd_NowUtcCalc()
	Local $t = _Date_Time_GetSystemTime()
	Return _Date_Time_SystemTimeToDateTimeStr($t, 1)
EndFunc

Func _Upd_NowUtcIso()
	Local $t = _Date_Time_GetSystemTime()
	Return _Date_Time_SystemTimeToDateTimeStr($t, 3, 1)
EndFunc

; 解析 ISO8601（C# 的 "O" 格式、带或不带 Z/偏移都接受），统一换算到 UTC；
; 解析不出来返回 ""（调用方当作"不知道时间"而不是 1970 年）。
Func _Upd_ParseIsoUtc($sText)
	If $sText = "" Then Return ""
	Local $a = StringRegExp($sText, "(?i)^\s*(\d{4})-(\d{1,2})-(\d{1,2})[T ](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?(?:\.\d+)?\s*(Z|[+-]\d{2}:?\d{2})?\s*$", 1)
	If @error Then Return ""
	Local $iY = Int($a[0]), $iMo = Int($a[1]), $iD = Int($a[2])
	Local $iH = Int($a[3]), $iMi = Int($a[4]), $iS = ($a[5] = "" ? 0 : Int($a[5]))
	If $iMo < 1 Or $iMo > 12 Or $iD < 1 Or $iD > 31 Or $iH > 23 Or $iMi > 59 Or $iS > 59 Then Return ""
	Local $sCalc = StringFormat("%04d/%02d/%02d %02d:%02d:%02d", $iY, $iMo, $iD, $iH, $iMi, $iS)
	Local $sZone = $a[6]
	If $sZone <> "" And $sZone <> "Z" And $sZone <> "z" Then
		Local $aHm = StringRegExp(StringTrimLeft($sZone, 1), "^(\d{2}):?(\d{2})$", 1)
		If Not @error Then
			Local $iSign = StringLeft($sZone, 1) = "-" ? -1 : 1
			Local $iOffSec = $iSign * (Int($aHm[0]) * 3600 + Int($aHm[1]) * 60)
			$sCalc = _DateAdd('s', -$iOffSec, $sCalc)
		EndIf
	EndIf
	Return $sCalc
EndFunc

; 照 C# Version.TryParse 的宽松度：2~4 段纯数字；非数字版本（如 1.0.0-beta）视为无效，不更新
Func _Upd_ParseVersion($sVer)
	If $sVer = "" Then Return 0
	Local $a = StringSplit($sVer, ".", 2)
	If UBound($a) < 2 Or UBound($a) > 4 Then Return 0
	Local $aOut[4] = [0, 0, 0, 0]
	Local $i
	For $i = 0 To UBound($a) - 1
		If Not StringRegExp($a[$i], "^\d{1,9}$") Then Return 0
		$aOut[$i] = Int($a[$i])
	Next
	Return $aOut
EndFunc

Func _Upd_IsNewer($sRemote, $sLocal)
	Local $aR = _Upd_ParseVersion($sRemote)
	If Not IsArray($aR) Then Return False
	Local $aL = _Upd_ParseVersion($sLocal)
	If Not IsArray($aL) Then Return False
	Local $i
	For $i = 0 To 3
		If $aR[$i] > $aL[$i] Then Return True
		If $aR[$i] < $aL[$i] Then Return False
	Next
	Return False
EndFunc

Func _Upd_HttpErrorText($iCode, $iExt)
	Switch $iExt
		Case 12002
			Return "网络超时（GitHub 在国内经常连不上），可以开代理后重试，或改用备用更新源。"
		Case 12007
			Return "网络连接失败：无法解析更新服务器域名（DNS 被干扰或没有网络）"
		Case 12029
			Return "网络连接失败：连接不上更新服务器（可能被墙，或服务器暂时不可用）"
		Case 12030, 12031
			Return "网络连接失败：连接被中断或重置（代理没开或网络不稳定）"
		Case 12057, 12038
			Return "网络连接失败：HTTPS 证书校验失败（可能有代理在拦截）"
	EndSwitch
	If $iCode > 0 Then Return "下载失败（错误码 " & $iCode & "）"
	Return "下载失败（网络不可用）"
EndFunc

; ---- 小工具（本模块内部用，避免为此 include 兄弟 lib）----

Func _U_ArrayAdd(ByRef $aArr, $v)
	ReDim $aArr[UBound($aArr) + 1]
	$aArr[UBound($aArr) - 1] = $v
EndFunc

Func _U_ArrayHas($aArr, $v)
	Local $i
	For $i = 0 To UBound($aArr) - 1
		; 只用于更新源去重，URL 大小写不敏感（C# 用的是 OrdinalIgnoreCase）
		If StringLower($aArr[$i]) = StringLower($v) Then Return True
	Next
	Return False
EndFunc
