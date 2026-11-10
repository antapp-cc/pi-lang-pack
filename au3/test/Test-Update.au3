#include "..\lib\Util.au3"
#include "..\lib\Json.au3"
#include "..\lib\Updater.au3"
#include <WinAPIConv.au3>

; 在线更新自检。纯逻辑部分不依赖网络；网络部分用一个本地 HTTP 服务（127.0.0.1），
; 服务没起就打印 [跳过] 而不是失败——GitHub 在国内未必连得上，自检不能因此红。
;
; 起服务（另开一个 PowerShell）：
;   python -m http.server 18765 --bind 127.0.0.1 --directory %TEMP%\pilang-web
; 脚本自己会把 fixture 写进那个目录。

Global $T_CFG = @TempDir & "\pilang-test-update-" & @AutoItPID
Global $T_WEB = @TempDir & "\pilang-web"
Global $T_PORT = 18765
Global $T_BASE = "http://127.0.0.1:" & $T_PORT

Global $g_fail = 0
Global $g_skip = 0
Global $g_progCalls = 0
Global $g_progLastStage = ""
Global $g_progLastPct = -1
Global $g_progMaxPct = -1

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

Func Skip($sWhat)
	ConsoleWrite("[跳过] " & $sWhat & @CRLF)
	$g_skip += 1
EndFunc

Func TestProgress($sStage, $iPercent)
	$g_progCalls += 1
	$g_progLastStage = $sStage
	$g_progLastPct = $iPercent
	If $iPercent > $g_progMaxPct Then $g_progMaxPct = $iPercent
EndFunc

Func _T_IsoFromCalc($sCalc)
	Return StringRegExpReplace($sCalc, "^(\d{4})/(\d{2})/(\d{2}) (\d{2}):(\d{2}):(\d{2})$", "$1-$2-$3T$4:$5:$6Z")
EndFunc

Func _T_IsoAgo($iSecondsAgo)
	Return _T_IsoFromCalc(_DateAdd('s', -$iSecondsAgo, _Upd_NowUtcCalc()))
EndFunc

Func _T_NewCfg($sUpdateUrl)
	Local $o = Json_NewObject()
	Json_Set($o, "locale", "zh-CN")
	Json_Set($o, "installPath", "")
	Json_Set($o, "autoUpdate", True)
	Json_Set($o, "updateUrl", $sUpdateUrl)
	Json_Set($o, "lastUpdateCheck", "")
	Json_Set($o, "lastLangUpdatedAt", "")
	Json_Set($o, "pendingRepatch", False)
	Json_Set($o, "appliedAsarHash", "")
	Return $o
EndFunc

Func _T_Manifest($sAppVer, $sAppUrl, $sAppSha, $sLangVer, $sLangUrl, $sLangSha, $sLangAt)
	Local $o = Json_NewObject()
	Local $oApp = Json_NewObject()
	Json_Set($oApp, "version", $sAppVer)
	Json_Set($oApp, "url", $sAppUrl)
	Json_Set($oApp, "sha256", $sAppSha)
	Json_Set($oApp, "updatedAt", "2026-11-10T10:00:00Z")
	Local $oLang = Json_NewObject()
	Json_Set($oLang, "version", $sLangVer)
	Json_Set($oLang, "url", $sLangUrl)
	Json_Set($oLang, "sha256", $sLangSha)
	Json_Set($oLang, "updatedAt", $sLangAt)
	Json_Set($o, "app", $oApp)
	Json_Set($o, "lang", $oLang)
	Return Json_Stringify($o)
EndFunc

Func _T_ServiceUp()
	Local $sTmp = @TempDir & "\pilang-test-probe-" & @AutoItPID & ".json"
	FileDelete($sTmp)
	Local $h = InetGet($T_BASE & "/latest.json?probe=" & @AutoItPID, $sTmp, 1, 1)
	If $h = 0 Or @error Then Return False
	Local $iWaited = 0, $a = 0
	While 1
		$a = InetGetInfo($h)
		If IsArray($a) And $a[2] Then ExitLoop
		Sleep(50)
		$iWaited += 50
		If $iWaited > 3000 Then
			InetClose($h)
			FileDelete($sTmp)
			Return False
		EndIf
	WEnd
	Local $bOk = (IsArray($a) And $a[3])
	InetClose($h)
	FileDelete($sTmp)
	Return $bOk
EndFunc

Func _T_LogCount($sPattern)
	Local $sLog = U_ReadText(U_LogPath())
	If $sLog = "" Then Return 0
	Local $aM = StringRegExp($sLog, $sPattern, 3)
	If Not IsArray($aM) Then Return 0
	Return UBound($aM)
EndFunc

; 把 ASCII 字符串转成十六进制，用于在 GBK 字节流里找命令关键字（不依赖系统代码页）
Func _T_HexAscii($s)
	Local $sOut = "", $i
	For $i = 1 To StringLen($s)
		$sOut &= Hex(Asc(StringMid($s, $i, 1)), 2)
	Next
	Return $sOut
EndFunc

; ---------------------------------------------------------------- 准备

EnvSet("PILANG_CONFIG_DIR", $T_CFG)
DirRemove($T_CFG, 1)
U_EnsureDir($T_CFG)
U_EnsureDir($T_WEB)

ConsoleWrite("== 在线更新自检（test\Test-Update.au3）==" & @CRLF)
ConsoleWrite("    配置目录: " & $T_CFG & @CRLF)
ConsoleWrite("    测试用 HTTP 服务根: " & $T_WEB & @CRLF)

; 假 exe：内容随便，只要求 SHA 可算、能被下载
Local $sFakeExe = ""
Local $i
For $i = 1 To 1200
	$sFakeExe &= "PiLang fixture line " & $i & " 0123456789abcdef" & @LF
Next
Local $sExePath = $T_WEB & "\PiLang.new.exe"
U_WriteText($sExePath, $sFakeExe)
Local $sExeSha = U_Sha256File($sExePath)

Local $sLangV1 = '{"locale":"zh-CN","name":"简体中文","version":"0.6.5","entries":{"File":"文件","Exit":"退出"},"danger":[],"patterns":[]}'
Local $sLangV2 = '{"locale":"zh-CN","name":"简体中文","version":"0.6.6","entries":{"File":"文件","Exit":"退出","Help":"帮助"},"danger":[],"patterns":[]}'
U_WriteText($T_WEB & "\zh-CN-v1.json", $sLangV1)
U_WriteText($T_WEB & "\zh-CN-v2.json", $sLangV2)
Local $sLangV1Sha = U_Sha256File($T_WEB & "\zh-CN-v1.json")
Local $sLangV2Sha = U_Sha256File($T_WEB & "\zh-CN-v2.json")

U_WriteText($T_WEB & "\latest.json", _T_Manifest("1.0.1", $T_BASE & "/PiLang.new.exe", $sExeSha, "0.6.5", $T_BASE & "/zh-CN-v1.json", $sLangV1Sha, "2026-11-10T12:00:00Z"))
U_WriteText($T_WEB & "\langonly.json", _T_Manifest("1.0.0", $T_BASE & "/PiLang.new.exe", $sExeSha, "0.6.5", $T_BASE & "/zh-CN-v1.json", $sLangV1Sha, "2026-11-10T12:00:00Z"))
U_WriteText($T_WEB & "\badsha.json", _T_Manifest("1.0.0", $T_BASE & "/PiLang.new.exe", $sExeSha, "0.6.5", $T_BASE & "/zh-CN-v2.json", "0000000000000000000000000000000000000000000000000000000000000000", "2026-11-10T12:00:00Z"))
U_WriteText($T_WEB & "\downgrade.json", _T_Manifest("1.0.0", $T_BASE & "/PiLang.new.exe", $sExeSha, "0.6.6", $T_BASE & "/zh-CN-v2.json", $sLangV2Sha, "2026-11-10T09:00:00Z"))
U_WriteText($T_WEB & "\broken.json", "{ this is not json ")

; ---------------------------------------------------------------- 1. 版本号 / 检查频率

ConsoleWrite("-- 版本与检查频率 --" & @CRLF)
T(Upd_CurrentAppVersion() = "1.0.0", "Upd_CurrentAppVersion 返回常量 1.0.0")

Local $oCfg = _T_NewCfg("https://example.com/latest.json")
Json_Set($oCfg, "autoUpdate", False)
T(Not Upd_ShouldCheckNow($oCfg), "autoUpdate=False 不检查")
Json_Set($oCfg, "autoUpdate", True)
Json_Set($oCfg, "updateUrl", "")
T(Not Upd_ShouldCheckNow($oCfg), "updateUrl 为空不检查")
Json_Set($oCfg, "updateUrl", "https://example.com/latest.json")
T(Upd_ShouldCheckNow($oCfg), "没有 lastUpdateCheck 就检查")
Json_Set($oCfg, "lastUpdateCheck", _T_IsoAgo(3600))
T(Not Upd_ShouldCheckNow($oCfg), "1 小时前检查过 → 不检查")
Json_Set($oCfg, "lastUpdateCheck", _T_IsoAgo(5 * 3600 + 3550))
T(Not Upd_ShouldCheckNow($oCfg), "5 小时 59 分前 → 不检查")
Json_Set($oCfg, "lastUpdateCheck", _T_IsoAgo(6 * 3600 + 90))
T(Upd_ShouldCheckNow($oCfg), "6 小时 1 分前 → 检查")
Json_Set($oCfg, "lastUpdateCheck", "not-a-time")
T(Upd_ShouldCheckNow($oCfg), "时间格式坏 → 检查（不能因此永远不检查）")
Json_Set($oCfg, "lastUpdateCheck", _T_IsoAgo(365 * 24 * 3600))
T(Upd_ShouldCheckNow($oCfg), "一年前检查过 → 要检查")

; ---------------------------------------------------------------- 2. URL 过滤

ConsoleWrite("-- 更新地址白名单 --" & @CRLF)
T(_Upd_IsAllowedUrl("https://raw.githubusercontent.com/o/r/main/server/latest.json"), "https 放行")
T(Not _Upd_IsAllowedUrl("http://raw.githubusercontent.com/o/r/main/latest.json"), "远程 http 拒绝")
T(Not _Upd_IsAllowedUrl("http://example.com/latest.json"), "普通 http 拒绝")
T(_Upd_IsAllowedUrl("http://localhost:18765/latest.json"), "http://localhost 放行（本地测试）")
T(_Upd_IsAllowedUrl("http://127.0.0.1:18765/latest.json"), "http://127.0.0.1 放行")
T(_Upd_IsAllowedUrl("http://127.0.0.1"), "http://127.0.0.1 无路径放行")
T(Not _Upd_IsAllowedUrl("http://127.0.0.1.evil.com/latest.json"), "127.0.0.1 前缀的伪装域名拒绝")
T(Not _Upd_IsAllowedUrl("ftp://example.com/x"), "ftp 拒绝")
T(Not _Upd_IsAllowedUrl(""), "空地址拒绝")
T(Not _Upd_IsAllowedUrl("not a url"), "非法地址拒绝")
T(Not _Upd_IsAllowedUrl("https://"), "https 但没有主机名拒绝")

; ---------------------------------------------------------------- 3. jsDelivr 镜像

ConsoleWrite("-- 更新源与 jsDelivr 镜像 --" & @CRLF)
Local $aSrc = _Upd_BuildSources("https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json")
T(UBound($aSrc) = 2, "GitHub raw 自动追加 1 个镜像（共 " & UBound($aSrc) & " 个源）")
T($aSrc[0] = "https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json", "主源顺序不变")
T($aSrc[1] = "https://cdn.jsdelivr.net/gh/antapp-cc/pi-lang-pack@main/server/latest.json", "镜像地址正确：" & $aSrc[1])

$aSrc = _Upd_BuildSources("https://a.com/1.json; https://b.com/2.json,https://c.com/3.json" & @CRLF & "  https://d.com/4.json  ")
T(UBound($aSrc) = 4, "; , 换行 分隔且去空白（共 " & UBound($aSrc) & " 个源）")
T($aSrc[0] = "https://a.com/1.json" And $aSrc[3] = "https://d.com/4.json", "拆分后首尾正确")

$aSrc = _Upd_BuildSources("https://example.com/latest.json")
T(UBound($aSrc) = 1, "非 GitHub 地址不生成镜像")

$aSrc = _Upd_BuildSources("https://cdn.jsdelivr.net/gh/a/b@main/x.json")
T(UBound($aSrc) = 1, "jsDelivr 地址不重复镜像")

$aSrc = _Upd_BuildSources("https://raw.GitHubusercontent.com/o/r/ref/path/sub/x.json")
T(UBound($aSrc) = 2 And $aSrc[1] = "https://cdn.jsdelivr.net/gh/o/r@ref/path/sub/x.json", "主机名大小写不敏感，路径可含多级目录")

$aSrc = _Upd_BuildSources("https://raw.githubusercontent.com/o/r/x.json")
T(UBound($aSrc) = 1, "raw 地址路径段不足 4 段 → 不生成镜像")

$aSrc = _Upd_BuildSources("https://raw.githubusercontent.com/o/r/main/x.json;https://raw.githubusercontent.com/o/r/main/x.json")
T(UBound($aSrc) = 3, "重复配置的源不重复追加镜像（共 " & UBound($aSrc) & " 个）")

$aSrc = _Upd_BuildSources("")
T(UBound($aSrc) = 0, "空配置 → 0 个源")

; ---------------------------------------------------------------- 4. 版本比较

ConsoleWrite("-- 版本比较 --" & @CRLF)
T(_Upd_IsNewer("1.0.1", "1.0.0"), "1.0.1 > 1.0.0")
T(Not _Upd_IsNewer("1.0.0", "1.0.1"), "1.0.0 不比 1.0.1 新")
T(_Upd_IsNewer("0.6.5", "0.6.4"), "0.6.5 > 0.6.4")
T(_Upd_IsNewer("1.10.0", "1.9.9"), "1.10.0 > 1.9.9（按数字段比较，不按字符串）")
T(_Upd_IsNewer("1.0.0.1", "1.0.0"), "1.0.0.1 > 1.0.0")
T(Not _Upd_IsNewer("1.0.0", "1.0.0.1"), "1.0.0 不比 1.0.0.1 新")
T(Not _Upd_IsNewer("1.0.0", "1.0.0"), "相等不算新版本")
T(Not _Upd_IsNewer("abc", "1.0.0"), "非法远端版本不更新")
T(Not _Upd_IsNewer("1.0.0-beta", "1.0.0"), "带后缀的版本不更新")
T(Not _Upd_IsNewer("1", "1.0.0"), "只有一段的版本不更新")
T(_Upd_IsNewer("2.0", "1.9.9"), "两段版本也能比较")
T(Not _Upd_IsNewer("", "1.0.0"), "空版本不更新")

; ---------------------------------------------------------------- 5. 清单解析

ConsoleWrite("-- 清单解析与字段宽容度 --" & @CRLF)
Local $sJson = _T_Manifest("1.0.1", "https://x/pi.exe", "ABCDEF", "0.6.5", "https://x/zh.json", "123456", "2026-11-10T12:00:00Z")
Local $oMan = Json_Parse($sJson)
T(IsObj($oMan), "清单能解析成对象")
Local $oApp = _Upd_Field($oMan, "app")
Local $oLang = _Upd_Field($oMan, "lang")
T(IsObj($oApp) And IsObj($oLang), "app / lang 都是对象")
T(_Upd_Field($oApp, "version") = "1.0.1", "app.version 解析正确")
T(_Upd_Field($oApp, "sha256") = "ABCDEF", "app.sha256 解析正确")
T(_Upd_Field($oApp, "updatedAt") = "2026-11-10T10:00:00Z", "app.updatedAt 解析正确")
T(_Upd_Field($oLang, "url") = "https://x/zh.json", "lang.url 解析正确")
T(_Upd_Field($oApp, "missing") = "", "缺字段返回默认空串")

Local $oCaps = Json_Parse('{"APP":{"Version":"2.0.0","SHA256":"abc"},"LANG":null}')
T(_Upd_Field(_Upd_Field($oCaps, "app"), "version") = "2.0.0", "字段名大小写不敏感（APP → app, Version → version）")
T(_Upd_Field(_Upd_Field($oCaps, "app"), "sha256") = "abc", "字段名大小写不敏感（SHA256 → sha256）")
T(Not IsObj(_Upd_Field($oCaps, "lang")), "lang:null 不当作对象")

; Json_Parse 对残缺输入可能吐出半个空对象，所以自检只看"解不出合法清单"
Local $oBad = Json_Parse("{ this is not json ")
T(Not IsObj(_Upd_Field($oBad, "app")) And Not IsObj(_Upd_Field($oBad, "lang")), "坏 JSON 解不出合法清单（app/lang 都不是对象）")

; ---------------------------------------------------------------- 6. SHA 校验与防降级（纯逻辑）

ConsoleWrite("-- 词表跳过逻辑（同 SHA / 防降级）--" & @CRLF)
Local $sLocalLang = U_LangDir() & "\zh-CN.json"
U_EnsureDir(U_LangDir())
U_WriteText($sLocalLang, $sLangV1)

Local $oCfg2 = _T_NewCfg("https://example.com/latest.json")
Local $oInfo = Json_NewObject()
Json_Set($oInfo, "version", "0.6.5")
Json_Set($oInfo, "url", "https://x/zh.json")
Json_Set($oInfo, "sha256", $sLangV1Sha)
Json_Set($oInfo, "updatedAt", "2026-11-10T12:00:00Z")
T(_Upd_LangSkip($oInfo, $oCfg2, $sLocalLang) = "same", "本地词表 SHA 与清单一致 → 跳过（same）")

Json_Set($oInfo, "sha256", $sLangV2Sha)
T(_Upd_LangSkip($oInfo, $oCfg2, $sLocalLang) = "", "SHA 不同且没有已应用时间 → 需要下载")

Json_Set($oCfg2, "lastLangUpdatedAt", "2026-11-10T12:00:00Z")
Json_Set($oInfo, "updatedAt", "2026-11-10T09:00:00Z")
T(_Upd_LangSkip($oInfo, $oCfg2, $sLocalLang) = "downgrade", "清单 updatedAt 比已应用的旧 → 拒绝降级")

Json_Set($oInfo, "updatedAt", "2026-11-10T12:00:00Z")
T(_Upd_LangSkip($oInfo, $oCfg2, $sLocalLang) = "downgrade", "updatedAt 相等（CDN 缓存未刷新）→ 拒绝降级")

Json_Set($oInfo, "updatedAt", "2026-11-10T13:00:00Z")
T(_Upd_LangSkip($oInfo, $oCfg2, $sLocalLang) = "", "清单 updatedAt 更新 → 下载")

Json_Set($oCfg2, "lastLangUpdatedAt", "")
Json_Set($oInfo, "updatedAt", "2026-11-10T09:00:00Z")
T(_Upd_LangSkip($oInfo, $oCfg2, $sLocalLang) = "", "没有已应用时间时不判降级")

Json_Set($oInfo, "updatedAt", "")
T(_Upd_LangSkip($oInfo, $oCfg2, $sLocalLang) = "", "清单没有 updatedAt 时不判降级")

; 时间解析
T(_Upd_ParseIsoUtc("2026-11-10T12:00:00Z") = "2026/11/10 12:00:00", "解析 Z 结尾的 UTC 时间")
T(_Upd_ParseIsoUtc("2026-11-10T20:00:00+08:00") = "2026/11/10 12:00:00", "解析 +08:00 偏移")
T(_Upd_ParseIsoUtc("2026-11-10T12:00:00.1234567Z") = "2026/11/10 12:00:00", "解析带小数秒的时间")
T(_Upd_ParseIsoUtc("garbage") = "", "非法时间返回空串")
T(_Upd_ParseIsoUtc("2026-13-01T00:00:00Z") = "", "非法月份返回空串")

; ---------------------------------------------------------------- 7. 网络部分（本地 HTTP 服务）

Local $bService = _T_ServiceUp()
If Not $bService Then
	Skip("网络集成测试（本地 HTTP 服务未启动；先运行 python -m http.server " & $T_PORT & " --bind 127.0.0.1 --directory " & $T_WEB & "）")
Else
	ConsoleWrite("-- 网络集成（本地 HTTP 服务 " & $T_BASE & "）--" & @CRLF)
	$UPD_DRY_RUN = True

	; 7.1 完整更新：词表 + 程序
	DirRemove($T_CFG, 1)
	U_EnsureDir($T_CFG)
	Local $oCfgA = _T_NewCfg($T_BASE & "/latest.json")
	$g_progCalls = 0
	$g_progMaxPct = -1
	; 函数引用（AutoIt 3.3.14+ 的函数变量）传进度回调
	Local $oR = Upd_CheckAndApply($oCfgA, TestProgress)
	T(Json_GetBool($oR, "ok", False), "完整更新 ok=True（" & Json_GetStr($oR, "message") & "）")
	T(Json_GetBool($oR, "langUpdated", False), "langUpdated=True")
	T(Json_GetBool($oR, "appUpdated", False), "appUpdated=True")
	T(StringInStr(Json_GetStr($oR, "message"), "词表已更新") > 0, "消息含「词表已更新」")
	T(StringInStr(Json_GetStr($oR, "message"), "程序已更新到 1.0.1") > 0, "消息含「程序已更新到 1.0.1」")
	T(FileExists(U_LangDir() & "\zh-CN.json"), "词表已写入 langs\zh-CN.json")
	T(U_Sha256File(U_LangDir() & "\zh-CN.json") = $sLangV1Sha, "写入的词表 SHA 与清单一致")
	T(Json_GetStr($oCfgA, "lastLangUpdatedAt") = "2026-11-10T12:00:00Z", "cfg.lastLangUpdatedAt 已记录清单时间")
	T(Json_GetBool($oCfgA, "pendingRepatch", False), "cfg.pendingRepatch=True（等守护重打）")
	T(Json_GetStr($oCfgA, "lastUpdateCheck") <> "", "cfg.lastUpdateCheck 已写入")
	T(FileExists(U_UpdateDir() & "\PiLang.new.exe"), "程序更新已下载 PiLang.new.exe")
	T(U_Sha256File(U_UpdateDir() & "\PiLang.new.exe") = $sExeSha, "PiLang.new.exe 内容与清单 SHA 一致")
	T(FileExists(U_UpdateDir() & "\update-runner.cmd"), "已生成 update-runner.cmd")
	T($g_progCalls > 0, "进度回调被调用（" & $g_progCalls & " 次，最后阶段「" & $g_progLastStage & "」）")
	T($g_progMaxPct = 100, "进度回调最终到达 100%（最大 " & $g_progMaxPct & "）")
	T(_T_LogCount("在线更新：词表已更新到 0.6.5") = 1, "日志记录了词表更新")

	; 7.2 已是最新：同一个词表，不重复下载
	Local $oCfgB = _T_NewCfg($T_BASE & "/langonly.json")
	Json_Set($oCfgB, "lastLangUpdatedAt", "2026-11-10T12:00:00Z")
	Local $oR2 = Upd_CheckAndApply($oCfgB)
	T(Json_GetBool($oR2, "ok", False), "第二次检查 ok=True")
	T(Not Json_GetBool($oR2, "langUpdated", False), "词表 SHA 相同 → 不重复更新")
	T(Not Json_GetBool($oR2, "appUpdated", False), "程序版本相同 → 不更新")
	T(Json_GetStr($oR2, "message") = "已是最新版本", "消息为「已是最新版本」")

	; 7.3 SHA 不一致：拒绝更新并重试 3 次
	DirRemove($T_CFG, 1)
	U_EnsureDir($T_CFG)
	U_EnsureDir(U_LangDir())
	U_WriteText(U_LangDir() & "\zh-CN.json", $sLangV1)
	Local $oCfgC = _T_NewCfg($T_BASE & "/badsha.json")
	Local $oR3 = Upd_CheckAndApply($oCfgC)
	T(Not Json_GetBool($oR3, "ok", False), "SHA 不一致 → ok=False")
	T(StringInStr(Json_GetStr($oR3, "message"), "SHA256 与清单不一致") > 0, "消息说明 SHA 不一致（" & Json_GetStr($oR3, "message") & "）")
	T(U_Sha256File(U_LangDir() & "\zh-CN.json") = $sLangV1Sha, "SHA 不一致时本地词表未被覆盖")
	T(_T_LogCount("SHA 校验不一致，重试下载") = 2, "SHA 不一致时重试了 2 次（共 3 次下载）")

	; 7.4 防降级：清单比已应用的旧
	Local $oCfgD = _T_NewCfg($T_BASE & "/downgrade.json")
	Json_Set($oCfgD, "lastLangUpdatedAt", "2026-11-10T12:00:00Z")
	Local $oR4 = Upd_CheckAndApply($oCfgD)
	T(Json_GetBool($oR4, "ok", False), "降级清单 → ok=True（不是错误，只是跳过）")
	T(Not Json_GetBool($oR4, "langUpdated", False), "降级清单 → 词表不更新")
	T(U_Sha256File(U_LangDir() & "\zh-CN.json") = $sLangV1Sha, "降级清单 → 本地词表内容不变")
	T(Json_GetStr($oCfgD, "lastLangUpdatedAt") = "2026-11-10T12:00:00Z", "降级清单 → 已应用时间不被改回旧值")

	; 7.5 坏清单
	Local $oCfgE = _T_NewCfg($T_BASE & "/broken.json")
	Local $oR5 = Upd_CheckAndApply($oCfgE)
	T(Not Json_GetBool($oR5, "ok", False), "坏清单 → ok=False")
	T(StringInStr(Json_GetStr($oR5, "message"), "更新清单") > 0, "坏清单消息指出清单有问题（" & Json_GetStr($oR5, "message") & "）")
EndIf

; ---------------------------------------------------------------- 8. 配置级错误

ConsoleWrite("-- 配置错误与连接失败 --" & @CRLF)
Local $oCfgF = _T_NewCfg("http://example.com/latest.json")
Local $oR6 = Upd_CheckAndApply($oCfgF)
T(Not Json_GetBool($oR6, "ok", False), "非 https 源 → ok=False")
T(StringInStr(Json_GetStr($oR6, "message"), "必须是 https") > 0, "消息说明必须 https（" & Json_GetStr($oR6, "message") & "）")

Local $oCfgG = _T_NewCfg("")
Local $oR7 = Upd_CheckAndApply($oCfgG)
T(Not Json_GetBool($oR7, "ok", False), "空更新地址 → ok=False")

Local $oCfgH = _T_NewCfg("http://127.0.0.1:1/latest.json")
Local $oR8 = Upd_CheckAndApply($oCfgH)
T(Not Json_GetBool($oR8, "ok", False), "连不上服务器 → ok=False（不卡死）")
T(StringInStr(Json_GetStr($oR8, "message"), "无法连接更新服务器") > 0, "连不上服务器消息可读（" & Json_GetStr($oR8, "message") & "）")

; ---------------------------------------------------------------- 9. 自替换演练（不执行）

ConsoleWrite("-- 自替换批处理演练（只落文件，不执行）--" & @CRLF)
Local $sDrillDir = $T_CFG & "\update-drill"
U_EnsureDir($sDrillDir)
Local $sDrillNew = $sDrillDir & "\PiLang.new.exe"
Local $sDrillBatch = $sDrillDir & "\update-runner.cmd"
Local $sDrillTarget = "C:\Users\测试用户\Pi多语言包\PiLang.exe"
T(_Upd_StageAppFiles($sExePath, $sDrillNew, $sDrillTarget, $sDrillTarget & ".old", $sDrillBatch), "演练：写出新 exe 与 update-runner.cmd")
T(FileExists($sDrillNew), "演练：PiLang.new.exe 已生成")
T(FileExists($sDrillBatch), "演练：update-runner.cmd 已生成")
T(U_Sha256File($sDrillNew) = $sExeSha, "演练：新 exe 内容与下载文件一致")

Local $bBatch = U_ReadBinary($sDrillBatch)
T(BinaryLen($bBatch) > 0, "演练：批处理非空（" & BinaryLen($bBatch) & " 字节）")
T(Hex(BinaryMid($bBatch, 1, 3)) <> "EFBBBF", "演练：批处理无 UTF-8 BOM（cmd 不认）")
T(Hex(BinaryMid($bBatch, BinaryLen($bBatch), 1)) <> "00", "演练：批处理结尾没有 NUL 字节（cmd 会报错）")

; 直接查字节：中文必须按 GBK(936) 写出，UTF-8 或英文系统的 1252 都会让 cmd 复制失败
Local $sHexBatch = Hex($bBatch)
T(StringInStr($sHexBatch, "B6E0D3EFD1D4B0FC") > 0, "演练：中文目录「多语言包」按 GBK 写出")
T(StringInStr($sHexBatch, "B2E2CAD4D3C3BBA7") > 0, "演练：中文用户名「测试用户」按 GBK 写出")
T(StringInStr($sHexBatch, _T_HexAscii("chcp 936")) > 0, "演练：批处理切换 936 代码页")
T(StringInStr($sHexBatch, _T_HexAscii("copy /Y")) > 0, "演练：批处理用 copy /Y 替换")
T(StringInStr($sHexBatch, _T_HexAscii("goto done")) > 0, "演练：批处理有重试与完成分支")
T(StringInStr($sHexBatch, _T_HexAscii('start "" "')) > 0, "演练：批处理会重启新程序")

; ---------------------------------------------------------------- 汇总

ConsoleWrite("-- 汇总 --" & @CRLF)
DirRemove($T_CFG, 1)
If $g_fail = 0 Then
	ConsoleWrite("全部通过" & ($g_skip > 0 ? "（跳过 " & $g_skip & " 项）" : "") & @CRLF)
	Exit(0)
EndIf
ConsoleWrite("失败 " & $g_fail & " 项" & ($g_skip > 0 ? "，跳过 " & $g_skip & " 项" : "") & @CRLF)
Exit(1)
