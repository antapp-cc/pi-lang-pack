#include "..\lib\Util.au3"
#include "..\lib\Json.au3"
#include "..\lib\Asar.au3" ; 只用来读原始备份，做真实文件上的替换验证
#include "..\lib\LangPack.au3"
#include "..\lib\StaticPatches.au3"
#include "..\lib\Injector.au3"

; 自检不碰真实 %APPDATA%\PiLang（那里是用户数据），全部落在 test\work\selftest 里
Global $g_work = @ScriptDir & "\work\selftest"
Global $g_fail = 0
Global $g_origAsar = "C:\Users\Administrator\AppData\Roaming\PiLang\backup\app.asar.0.6.4.orig"

EnvSet("PILANG_CONFIG_DIR", $g_work)
DirRemove($g_work, 1)
U_EnsureDir($g_work)

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

Func _CountKeys($oObj)
	If Not IsObj($oObj) Then Return -1
	Return $oObj.Count
EndFunc

Local $tAll = TimerInit()
ConsoleWrite("== LangPack / StaticPatches / Injector 自检 ==" & @CRLF)

; ---------------- 语言包 ----------------
ConsoleWrite("-- 语言包释放与加载 --" & @CRLF)
Local $sSeed = U_LangDir() & "\zh-CN.json"

Lang_SeedIfMissing()
Local $iSeedSize = FileGetSize($sSeed)
T(FileExists($sSeed) And $iSeedSize > 60000, "首次释放词表到 langs\zh-CN.json（" & $iSeedSize & " 字节）")

; 已存在的词表是用户可能改过的，种子不许覆盖
U_WriteText($sSeed, '{"locale":"zh-CN","entries":{}}')
Lang_SeedIfMissing()
T(FileGetSize($sSeed) < $iSeedSize And StringInStr(U_ReadText($sSeed), '"entries":{}') > 0, "已存在的词表不被覆盖")
FileDelete($sSeed)

Local $oPack = Lang_Load("zh-CN")
Local $oEntries = Json_Get($oPack, "entries")
Local $aDanger = Json_Get($oPack, "danger")
Local $aPatterns = Json_Get($oPack, "patterns")
T(FileExists($sSeed) And FileGetSize($sSeed) = $iSeedSize, "词表缺失时 Lang_Load 会补回种子")
T(Json_GetStr($oPack, "locale") = "zh-CN" And Json_GetStr($oPack, "name") = "简体中文" And Json_GetStr($oPack, "version") = "0.6.4", _
	"包元信息 locale/name/version = " & Json_GetStr($oPack, "locale") & "/" & Json_GetStr($oPack, "name") & "/" & Json_GetStr($oPack, "version"))

Local $iEntries = _CountKeys($oEntries)
T($iEntries = 641, "entries 条数 641（实际 " & $iEntries & "）")
T(Json_ArrayLen($aDanger) = 16, "danger 16 条（实际 " & Json_ArrayLen($aDanger) & "）")
T(Json_ArrayLen($aPatterns) = 38, "patterns 38 条（实际 " & Json_ArrayLen($aPatterns) & "）")

Local $oP0 = Json_ArrayGet($aPatterns, 0)
Local $oPLast = Json_ArrayGet($aPatterns, Json_ArrayLen($aPatterns) - 1)
T(IsObj($oP0) And Json_Has($oP0, "p") And Json_Has($oP0, "r") And Not Json_Has($oP0, "pattern"), "patterns 字段名已转成 p/r")
T(Json_GetStr($oP0, "p") = "^(\d+) (?:second|seconds) ago$" And Json_GetStr($oP0, "r") = "$1 秒前", _
	"patterns[0] = " & Json_GetStr($oP0, "p") & " → " & Json_GetStr($oP0, "r"))
T(IsObj($oPLast) And Json_GetStr($oPLast, "p") = "^Currently supporting (\d+) other nodes$", "patterns 末条完整（" & Json_GetStr($oPLast, "p") & "）")

; 词表里有只差大小写的键，转小写就会丢
T(Json_GetStr($oEntries, "Awaiting config") = "等待配置" And Json_GetStr($oEntries, "AWAITING CONFIG") = "等待配置", "仅差大小写的键都在且都有译文")
T(Json_GetStr($oEntries, "Do you want to stop?") = "要停止吗？", "整句词条 Do you want to stop? → 要停止吗？")
T(Json_GetStr($oEntries, "Remove all blockchain data") = "删除所有区块链数据", "danger 词条也有译文")

Local $iMissing = 0, $i
For $i = 0 To Json_ArrayLen($aDanger) - 1
	If Not Json_Has($oEntries, String(Json_ArrayGet($aDanger, $i))) Then $iMissing += 1
Next
T($iMissing = 0, "danger 词条都在 entries 里（缺 " & $iMissing & " 条）")

Local $aEntryKeys = $oEntries.Keys()
Local $iEmpty = 0
For $i = 0 To UBound($aEntryKeys) - 1
	If String($oEntries.Item($aEntryKeys[$i])) = "" Then $iEmpty += 1
Next
T($iEmpty = 0, "没有空译文（空 " & $iEmpty & " 条）")

; 外部词表：覆盖已有条目、加新条目、并集 danger、追加 patterns
ConsoleWrite("-- 外部词表合并 --" & @CRLF)
U_WriteText($sSeed, '{"locale":"zh-CN","name":"自定义简体中文","version":"9.9.9",' & _
	'"entries":{"Do you want to stop?":"覆盖后的译文","自造新键":"自造译文"},' & _
	'"danger":["Brand New Danger"],' & _
	'"patterns":[{"pattern":"^brand-new$","replacement":"全新"}]}')

Local $oM = Lang_Load("zh-CN")
Local $oMEntries = Json_Get($oM, "entries")
Local $aMDanger = Json_Get($oM, "danger")
Local $aMPatterns = Json_Get($oM, "patterns")
T(_CountKeys($oMEntries) = 642, "合并后 entries 642 条（覆盖 1 条 + 新增 1 条，实际 " & _CountKeys($oMEntries) & "）")
T(Json_GetStr($oMEntries, "Do you want to stop?") = "覆盖后的译文", "外部词条覆盖同键")
T(Json_GetStr($oMEntries, "自造新键") = "自造译文", "外部新增词条生效")
T(Json_GetStr($oMEntries, "Remove all blockchain data") = "删除所有区块链数据", "内置词条仍在（打底没被吃掉）")
T(Json_ArrayLen($aMDanger) = 17, "合并后 danger 17 条（并集去重，实际 " & Json_ArrayLen($aMDanger) & "）")
T(Json_ArrayLen($aMPatterns) = 39, "合并后 patterns 39 条（追加，实际 " & Json_ArrayLen($aMPatterns) & "）")
Local $oMLast = Json_ArrayGet($aMPatterns, Json_ArrayLen($aMPatterns) - 1)
T(Json_GetStr($oMLast, "p") = "^brand-new$" And Json_GetStr($oMLast, "r") = "全新", "外部 pattern 追加在末尾")
T(Json_GetStr($oM, "name") = "自定义简体中文" And Json_GetStr($oM, "version") = "9.9.9", "外部 name/version 覆盖内置")

; 词表坏掉时退回内置词表而不是崩
U_WriteText($sSeed, "{ 这不是 JSON")
Local $oBad = Lang_Load("zh-CN")
T(IsObj($oBad) And _CountKeys(Json_Get($oBad, "entries")) = 641, "外部词表损坏时退回内置词表")
FileDelete($sSeed)

Local $oEn = Lang_Load("en-US")
T(Json_GetStr($oEn, "locale") = "en-US" And _CountKeys(Json_Get($oEn, "entries")) = 0 And Json_ArrayLen(Json_Get($oEn, "danger")) = 0 And Json_ArrayLen(Json_Get($oEn, "patterns")) = 0, _
	"en-US 是空包（entries/danger/patterns 都为空）")

; 编译后内置词表由 FileInstall 释放到运行期资源目录，优先读那里
FileCopy(@ScriptDir & "\..\res\zh-CN.json", U_ResourceDir() & "\zh-CN.json", 1)
Local $oRes = Lang_Load("zh-CN")
T(_CountKeys(Json_Get($oRes, "entries")) = 641 And Json_ArrayLen(Json_Get($oRes, "patterns")) = 38, "从运行期资源目录读内置词表（编译后走的路径）")

; ---------------- 注入脚本 ----------------
ConsoleWrite("-- 注入脚本生成 --" & @CRLF)
Local $sTpl = U_ResourceDir() & "\" & $INJ_TEMPLATE_NAME
DirRemove(U_ResourceDir(), 1)
T(Inj_EnsureResources(), "释放注入脚本模板到运行期资源目录")
T(FileExists($sTpl) And FileGetSize($sTpl) > 1000, "模板已就位（" & FileGetSize($sTpl) & " 字节）")
Local $iTplSize = FileGetSize($sTpl)
T(Inj_EnsureResources() And FileGetSize($sTpl) = $iTplSize, "重复释放幂等")

Local $t0 = TimerInit()
Local $sScript = Inj_BuildScript($oPack)
Local $iBuildMs = Round(TimerDiff($t0))
T(StringInStr($sScript, "/* pi-lang-patch */", 0, 1) > 0, "脚本含补丁标记 /* pi-lang-patch */")
T(StringInStr($sScript, '"locale":"zh-CN"', 0, 1) > 0, "脚本内联了语言包（compact JSON）")
T(StringLen($sScript) > 10000, "脚本长度合理（" & StringLen($sScript) & " 字节，" & $iBuildMs & " ms）")
T(Inj_BuildScript($oPack) = $sScript, "同样输入生成同样脚本（可复现）")

; 内联 JSON 取出来重新解析一遍：中文已转成 \u 转义，这一步同时验证转义往返
Local $iDataPos = StringInStr($sScript, "var DATA = ")
Local $sInline = ""
If $iDataPos > 0 Then
	$iDataPos += StringLen("var DATA = ")
	Local $iLineEnd = StringInStr($sScript, @LF, 0, 1, $iDataPos)
	If $iLineEnd > $iDataPos Then $sInline = StringStripWS(StringMid($sScript, $iDataPos, $iLineEnd - $iDataPos), 2)
EndIf
If StringRight($sInline, 1) = ";" Then $sInline = StringTrimRight($sInline, 1)

Local $oData = Json_Parse($sInline)
T(IsObj($oData), "内联 JSON 可解析（" & StringLen($sInline) & " 字节）")
Local $oDataEntries = Json_Get($oData, "entries")
Local $aDataDanger = Json_Get($oData, "danger")
Local $aDataPatterns = Json_Get($oData, "patterns")
T(_CountKeys($oDataEntries) = 641, "内联 entries 641 条（实际 " & _CountKeys($oDataEntries) & "）")
T(Json_ArrayLen($aDataDanger) = 16, "内联 danger 16 条（实际 " & Json_ArrayLen($aDataDanger) & "）")
T(Json_ArrayLen($aDataPatterns) = 38, "内联 patterns 38 条（实际 " & Json_ArrayLen($aDataPatterns) & "）")
T(Json_GetStr($oData, "version") = "0.6.4", "内联 version 0.6.4")
T(Json_GetStr($oDataEntries, "Do you want to stop?") = "要停止吗？", "中文经 \u 转义往返后没坏")

; 键里本身带双引号/弯引号的词条最容易在序列化时出事
Local $sQuoteKey = 'Windows Firewall may show a dialog about Docker, in which case you need to click "Allow access".'
T(Json_GetStr($oDataEntries, $sQuoteKey) = Json_GetStr($oEntries, $sQuoteKey) And Json_GetStr($oDataEntries, $sQuoteKey) <> "", _
	"含双引号的键经内联/解析后一致")

Local $oPData = Json_ArrayGet($aDataPatterns, 0)
T(IsObj($oPData) And Json_GetStr($oPData, "p") = Json_GetStr($oP0, "p") And Json_GetStr($oPData, "r") = Json_GetStr($oP0, "r"), "内联 pattern 的 p/r 与词表一致")

; 落一份出来，方便外部用 node --check 验证语法
U_WriteText($g_work & "\pi-lang.js", $sScript)
T(FileExists($g_work & "\pi-lang.js"), "脚本已落盘供语法检查（test\work\selftest\pi-lang.js）")

; ---------------- index.html ----------------
ConsoleWrite("-- index.html 注入 --" & @CRLF)
Local $sHtml = "<!DOCTYPE html><html><head><meta charset=utf-8><title>Pi Desktop</title><script defer=defer src=./renderer.js></script></head><body></body></html>"
Local $sPatched = Inj_PatchHtml($sHtml)
T(StringInStr($sPatched, $INJ_SCRIPT_TAG, 0, 1) > 0, "index.html 注入了脚本标签")
T(StringInStr($sPatched, "./pi-lang.js", 0, 1) < StringInStr($sPatched, "./renderer.js", 0, 1), "注入脚本在 renderer.js 之前")
T(Inj_PatchHtml($sPatched) = $sPatched, "重复注入幂等")
T(Inj_UnpatchHtml($sPatched) = $sHtml, "移除注入后回到原文")
Local $sNoScript = "<!DOCTYPE html><html></html>"
Inj_PatchHtml($sNoScript)
T(@error = 1, "找不到 <script 时返回错误码 1（而不是抛异常/返回空）")

; ---------------- 静态替换 ----------------
ConsoleWrite("-- 静态替换表 --" & @CRLF)
Local $iBad = 0
For $i = 0 To UBound($SP_MAIN_MAP) - 1
	If SP_ApplyMain($SP_MAIN_MAP[$i][0]) <> $SP_MAIN_MAP[$i][1] Then
		$iBad += 1
		ConsoleWrite("      第 " & ($i + 1) & " 条不符: " & $SP_MAIN_MAP[$i][0] & @CRLF)
	EndIf
Next
T(UBound($SP_MAIN_MAP) = 30 And $iBad = 0, "主菜单 30 条逐条命中（不符 " & $iBad & " 条）")

$iBad = 0
For $i = 0 To UBound($SP_RENDERER_MAP) - 1
	If SP_ApplyRenderer($SP_RENDERER_MAP[$i][0]) <> $SP_RENDERER_MAP[$i][1] Then
		$iBad += 1
		ConsoleWrite("      第 " & ($i + 1) & " 条不符: " & StringLeft($SP_RENDERER_MAP[$i][0], 40) & @CRLF)
	EndIf
Next
T(UBound($SP_RENDERER_MAP) = 8 And $iBad = 0, "confirm 文案 8 条逐条命中（不符 " & $iBad & " 条）")

Local $sMainFrom = "", $sMainTo = "", $sMainFromOk = ""
For $i = 0 To UBound($SP_MAIN_MAP) - 1
	$sMainFrom &= $SP_MAIN_MAP[$i][0] & @LF
	$sMainTo &= $SP_MAIN_MAP[$i][1] & @LF
Next
T(SP_ApplyMain($sMainFrom) = $sMainTo, "整体替换结果与逐条结果一致")
T(SP_HasAny($sMainFrom, "main") = False, "原文不含中文译文（SP_HasAny 判未打补丁）")
T(SP_HasAny($sMainTo, "main"), "译文可被 SP_HasAny 识别（判已打补丁）")
T(SP_HasAny($sMainTo, "renderer") = False, "菜单译文不串到 renderer 表")
SP_HasAny($sMainFrom, "nonsense")
T(@error = 1, "SP_HasAny 未知目标返回错误码 1")

; Exit/Quit 都译成「退出」，兜底还原没法分辨是哪条；跳过译文重复的条目再验可逆
Local $oToCount = Json_NewObject()
Local $sTo
For $i = 0 To UBound($SP_MAIN_MAP) - 1
	$sTo = $SP_MAIN_MAP[$i][1]
	If $oToCount.Exists($sTo) Then
		$oToCount.Item($sTo) = 2
	Else
		$oToCount.Item($sTo) = 1
	EndIf
Next
Local $iAmbig = 0
For $i = 0 To UBound($SP_MAIN_MAP) - 1
	If $oToCount.Item($SP_MAIN_MAP[$i][1]) = 1 Then
		$sMainFromOk &= $SP_MAIN_MAP[$i][0] & @LF
	Else
		$iAmbig += 1
	EndIf
Next
T(SP_RevertMain(SP_ApplyMain($sMainFromOk)) = $sMainFromOk, "菜单替换可逆（跳过译文重复的 " & $iAmbig & " 条）")

Local $sRendFrom = "", $sRendTo = ""
For $i = 0 To UBound($SP_RENDERER_MAP) - 1
	$sRendFrom &= $SP_RENDERER_MAP[$i][0] & @LF
	$sRendTo &= $SP_RENDERER_MAP[$i][1] & @LF
Next
T(SP_ApplyRenderer($sRendFrom) = $sRendTo, "confirm 文案整体替换逐条一致")
T(SP_RevertRenderer($sRendTo) = $sRendFrom, "confirm 文案替换可逆")
T(SP_HasAny($sRendTo, "renderer") And Not SP_HasAny($sRendFrom, "renderer"), "renderer 表 SP_HasAny 判定正确")

; ---------------- 真实原版 asar 上再验一遍 ----------------
ConsoleWrite("-- 真实 asar 备份上的替换 --" & @CRLF)
If Not FileExists($g_origAsar) Then
	ConsoleWrite("[跳过] 没有原始 asar 备份，真实文件上的替换未验证: " & $g_origAsar & @CRLF)
Else
	Local $tAsar = TimerInit()
	Local $oAsar = Asar_Open($g_origAsar)
	T(IsObj($oAsar), "打开原始 asar 备份（" & Round(TimerDiff($tAsar)) & " ms）")
	If IsObj($oAsar) Then
		Local $sMain = Asar_ReadText($oAsar, $SP_MAINJS)
		Local $sRend = Asar_ReadText($oAsar, $SP_RENDERERJS)
		Local $sRealHtml = Asar_ReadText($oAsar, $INJ_INDEX_PATH)
		T(StringLen($sMain) > 100000 And StringLen($sRend) > 100000, "读出 main.js / renderer.js（" & StringLen($sMain) & " / " & StringLen($sRend) & " 字节）")

		Local $iHit = 0, $iLeft = 0
		Local $sMainZh = SP_ApplyMain($sMain)
		For $i = 0 To UBound($SP_MAIN_MAP) - 1
			If StringInStr($sMainZh, $SP_MAIN_MAP[$i][1], 0, 1) > 0 Then $iHit += 1
			If StringInStr($sMainZh, $SP_MAIN_MAP[$i][0], 0, 1) > 0 Then $iLeft += 1
		Next
		T($iHit = 30, "真实 main.js 命中 30/30 条菜单（" & $iHit & "）")
		T($iLeft = 0, "真实 main.js 无残留英文 label（" & $iLeft & "）")

		$iHit = 0
		$iLeft = 0
		Local $sRendZh = SP_ApplyRenderer($sRend)
		For $i = 0 To UBound($SP_RENDERER_MAP) - 1
			If StringInStr($sRendZh, $SP_RENDERER_MAP[$i][1], 0, 1) > 0 Then $iHit += 1
			If StringInStr($sRendZh, $SP_RENDERER_MAP[$i][0], 0, 1) > 0 Then $iLeft += 1
		Next
		T($iHit = 8, "真实 renderer.js 命中 8/8 条 confirm 文案（" & $iHit & "）")
		T($iLeft = 0, "真实 renderer.js 无残留英文 confirm 文案（" & $iLeft & "）")

		Local $sRealPatched = Inj_PatchHtml($sRealHtml)
		T(StringInStr($sRealHtml, "./pi-lang.js", 0, 1) = 0 And StringInStr($sRealPatched, "./pi-lang.js", 0, 1) > 0, "真实 index.html 注入成功")
		T(Inj_PatchHtml($sRealPatched) = $sRealPatched, "真实 index.html 重复注入幂等")
		T(Inj_UnpatchHtml($sRealPatched) = $sRealHtml, "真实 index.html 还原后与原文一致")
	EndIf
EndIf

ConsoleWrite("-- 耗时 " & Round(TimerDiff($tAll)) & " ms --" & @CRLF)
ConsoleWrite($g_fail = 0 ? "全部通过" : "失败 " & $g_fail & " 项")
ConsoleWrite(@CRLF)
Exit($g_fail = 0 ? 0 : 1)
