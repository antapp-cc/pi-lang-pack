#include-once

; 词表是「英文原文 → 译文」的整句映射，区分大小写。danger 里的键只允许整句精确匹配：
; 新版应用换了说法就保留英文，不冒险把删除/停止这类危险操作翻错。
;
; 加载策略与 C# 版一致：内置词表打底，%APPDATA%\PiLang\langs\<locale>.json 覆盖 entries、
; 合并 danger、追加 patterns。这样工具升级带来的新词条自动生效，用户自己补改的条目也不丢。

Func Lang_SeedIfMissing()
	U_EnsureDir(U_LangDir())
	Local $sTarget = U_LangDir() & "\zh-CN.json"
	If FileExists($sTarget) Then Return
	Local $sSrc = _Lang_BuiltInPath()
	If $sSrc = "" Then
		U_Log("释放语言包失败: 找不到内置词表")
		Return
	EndIf
	Local $sText = U_ReadText($sSrc)
	If @error Then
		U_Log("释放语言包失败: 读取 " & $sSrc)
		Return
	EndIf
	; 写失败也不致命：后面还能从内置资源读，只是用户没法再单独替换词表
	If Not U_WriteText($sTarget, $sText) Then U_Log("释放语言包失败: 写入 " & $sTarget)
EndFunc

; 编译后词表由主脚本 FileInstall 到 res\，开发期直接读项目里的 res\。
; 第三个候选是给 test\ 下的自检脚本用的：那里 @ScriptDir 是 test\，不是项目根。
Func _Lang_BuiltInPath()
	Local $aCand[3] = [ _
		U_ResourceDir() & "\zh-CN.json", _
		@ScriptDir & "\res\zh-CN.json", _
		@ScriptDir & "\..\res\zh-CN.json" _
	]
	Local $i
	For $i = 0 To UBound($aCand) - 1
		If FileExists($aCand[$i]) And FileGetSize($aCand[$i]) > 0 Then Return $aCand[$i]
	Next
	Return ""
EndFunc

Func Lang_Load($sLocale)
	Lang_SeedIfMissing()

	Local $oPack
	If StringLower($sLocale) = "zh-cn" Then
		Local $sPath = _Lang_BuiltInPath()
		Local $oRaw = Null
		If $sPath <> "" Then $oRaw = Json_Parse(U_ReadText($sPath))
		If IsObj($oRaw) Then
			$oPack = _Lang_ReadPack($oRaw, $sLocale)
		Else
			U_Log("内置词表读取失败，使用空词表: " & $sPath)
			$oPack = _Lang_NewPack($sLocale)
		EndIf
	Else
		$oPack = _Lang_NewPack($sLocale)
	EndIf

	Local $sExtPath = U_LangDir() & "\" & $sLocale & ".json"
	If Not FileExists($sExtPath) Then Return $oPack

	Local $oExt = Json_Parse(U_ReadText($sExtPath))
	If Not IsObj($oExt) Then
		; 外部词表坏掉时退回内置词表，别让整个汉化功能挂掉
		U_Log("读取外部语言包失败，用内置词表: " & $sExtPath)
		Return $oPack
	EndIf
	Return _Lang_Merge($oPack, _Lang_ReadPack($oExt, $sLocale))
EndFunc

Func _Lang_NewPack($sLocale)
	Local $o = Json_NewObject()
	; C# 里 Name 的默认值就是「简体中文」；非中文包按空包处理，不冒充中文包名
	Json_Set($o, "locale", $sLocale)
	Json_Set($o, "name", StringLower($sLocale) = "zh-cn" ? "简体中文" : "")
	Json_Set($o, "version", "")
	Json_Set($o, "entries", Json_NewObject())
	Json_Set($o, "danger", _Json_NewArray())
	Json_Set($o, "patterns", _Json_NewArray())
	Return $o
EndFunc

; 把词表 JSON 规整成契约里的包结构；字段名 pattern/replacement 在这里就转成 p/r，
; 免得注入脚本那一层还得兼容两套字段名
Func _Lang_ReadPack($oRaw, $sLocale)
	Local $oPack = _Lang_NewPack($sLocale)
	Local $sName = Json_GetStr($oRaw, "name", "")
	If $sName <> "" Then Json_Set($oPack, "name", $sName)
	Local $sVer = Json_GetStr($oRaw, "version", "")
	If $sVer <> "" Then Json_Set($oPack, "version", $sVer)

	; entries 直接沿用解析出来的 Dictionary：BinaryCompare，只差大小写的键（Awaiting config /
	; AWAITING CONFIG）必须都留下
	Local $oEntries = Json_Get($oRaw, "entries", Null)
	If IsObj($oEntries) Then Json_Set($oPack, "entries", $oEntries)

	Local $vDanger = Json_Get($oRaw, "danger", Null)
	If IsArray($vDanger) Then Json_Set($oPack, "danger", _Lang_ToStrings($vDanger))

	Json_Set($oPack, "patterns", _Lang_ReadPatterns($oRaw))
	Return $oPack
EndFunc

Func _Lang_ReadPatterns($oRaw)
	Local $aOut = _Json_NewArray()
	Local $vPats = Json_Get($oRaw, "patterns", Null)
	If Not IsArray($vPats) Then Return $aOut

	Local $i, $oPat, $oItem, $sP, $sR
	For $i = 0 To Json_ArrayLen($vPats) - 1
		$oPat = Json_ArrayGet($vPats, $i)
		If Not IsObj($oPat) Then ContinueLoop
		$sP = Json_GetStr($oPat, "pattern", "")
		If $sP = "" Then $sP = Json_GetStr($oPat, "p", "")
		$sR = Json_GetStr($oPat, "replacement", "")
		If $sR = "" Then $sR = Json_GetStr($oPat, "r", "")
		If $sP = "" Then ContinueLoop
		$oItem = Json_NewObject()
		Json_Set($oItem, "p", $sP)
		Json_Set($oItem, "r", $sR)
		Json_ArrayPush($aOut, $oItem)
	Next
	Return $aOut
EndFunc

Func _Lang_ToStrings($vList)
	Local $aOut = _Json_NewArray()
	Local $i, $s
	For $i = 0 To Json_ArrayLen($vList) - 1
		$s = String(Json_ArrayGet($vList, $i))
		If $s = "" Then ContinueLoop
		Json_ArrayPush($aOut, $s)
	Next
	Return $aOut
EndFunc

Func _Lang_Merge($oBase, $oExt)
	Local $oPack = _Lang_NewPack(Json_GetStr($oBase, "locale", ""))

	Local $sName = Json_GetStr($oExt, "name", "")
	Json_Set($oPack, "name", $sName <> "" ? $sName : Json_GetStr($oBase, "name", ""))
	Local $sVer = Json_GetStr($oExt, "version", "")
	Json_Set($oPack, "version", $sVer <> "" ? $sVer : Json_GetStr($oBase, "version", ""))

	; entries：内置打底，外部同键覆盖
	Local $oEntries = Json_Get($oBase, "entries", Null)
	If Not IsObj($oEntries) Then $oEntries = Json_NewObject()
	Local $oExtEntries = Json_Get($oExt, "entries", Null)
	If IsObj($oExtEntries) Then
		Local $aKeys = $oExtEntries.Keys()
		Local $i
		For $i = 0 To UBound($aKeys) - 1
			$oEntries.Item($aKeys[$i]) = $oExtEntries.Item($aKeys[$i])
		Next
	EndIf
	Json_Set($oPack, "entries", $oEntries)

	; danger：并集去重，保持内置条目在前的顺序
	Local $oSeen = Json_NewObject()
	Local $aDanger = _Json_NewArray()
	_Lang_UnionDanger($aDanger, $oSeen, Json_Get($oBase, "danger", Null))
	_Lang_UnionDanger($aDanger, $oSeen, Json_Get($oExt, "danger", Null))
	Json_Set($oPack, "danger", $aDanger)

	; patterns：内置在前、外部追加（内置规则先匹配），同 (p,r) 只留一份。
	; 种子文件本身就是内置词表的副本，不去重的话每次 Load 都会把 patterns 翻倍
	; （C# 版就是 38 → 76，词条少时看不出来，白编译一半正则）。
	Local $oPatSeen = Json_NewObject()
	Local $aPatterns = _Json_NewArray()
	_Lang_UnionPatterns($aPatterns, $oPatSeen, Json_Get($oBase, "patterns", Null))
	_Lang_UnionPatterns($aPatterns, $oPatSeen, Json_Get($oExt, "patterns", Null))
	Json_Set($oPack, "patterns", $aPatterns)

	Return $oPack
EndFunc

Func _Lang_UnionDanger(ByRef $aOut, $oSeen, $vList)
	If Not IsArray($vList) Then Return
	Local $i, $s
	For $i = 0 To Json_ArrayLen($vList) - 1
		$s = String(Json_ArrayGet($vList, $i))
		If $s = "" Then ContinueLoop
		If $oSeen.Exists($s) Then ContinueLoop
		$oSeen.Item($s) = 1
		Json_ArrayPush($aOut, $s)
	Next
EndFunc

Func _Lang_UnionPatterns(ByRef $aOut, $oSeen, $vList)
	If Not IsArray($vList) Then Return
	Local $i, $oItem, $sKey
	For $i = 0 To Json_ArrayLen($vList) - 1
		$oItem = Json_ArrayGet($vList, $i)
		If Not IsObj($oItem) Then ContinueLoop
		$sKey = Json_GetStr($oItem, "p", "") & Chr(1) & Json_GetStr($oItem, "r", "")
		If $oSeen.Exists($sKey) Then ContinueLoop
		$oSeen.Item($sKey) = 1
		Json_ArrayPush($aOut, $oItem)
	Next
EndFunc
