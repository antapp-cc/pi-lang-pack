#include "..\lib\Util.au3"
#include "..\lib\Json.au3"

; 词表规模下的性能探针：641 条 entries（含长段落、引号转义）在 AU3 里的
; 解析 / 序列化 / 生成注入脚本内联 JSON 各要多久。这几个数决定安装时会不会卡。

Global $g_fail = 0

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

Global $g_json = "C:\Users\Administrator\Desktop\Pi多语言包-AU3\res\zh-CN.json"
If Not FileExists($g_json) Then
	ConsoleWrite("[跳过] 没有词表" & @CRLF)
	Exit(2)
EndIf

Local $sRaw = U_ReadText($g_json)
ConsoleWrite("词表原始大小 " & StringLen($sRaw) & " 字符" & @CRLF)

Local $t = TimerInit()
Local $oPack = Json_Parse($sRaw)
ConsoleWrite("解析 " & Round(TimerDiff($t)) & " ms" & @CRLF)
T(IsObj($oPack), "词表解析成功")

Local $oEntries = Json_Get($oPack, "entries")
Local $oDanger = Json_Get($oPack, "danger")
Local $oPatterns = Json_Get($oPack, "patterns")
T($oEntries.Count = 641, "entries = 641（实际 " & $oEntries.Count & "）")
T(Json_ArrayLen($oDanger) = 16, "danger = 16（实际 " & Json_ArrayLen($oDanger) & "）")
T(Json_ArrayLen($oPatterns) = 38, "patterns = 38（实际 " & Json_ArrayLen($oPatterns) & "）")

; 大小写只差一档的键必须都留着
T($oEntries.Exists("Awaiting config") And $oEntries.Exists("AWAITING CONFIG"), "仅大小写不同的键都保留")
T($oEntries.Exists("Remove all blockchain data"), "危险操作键存在")

; 带双引号的键能正确解出
Local $sQuoted = 'Docker runs on your system as a background task called a "daemon". Start Docker Desktop and wait until it reports that it is running, so your computer can run a Pi node.'
T($oEntries.Exists($sQuoted), "含双引号的键正确解析")

; patterns 字段名
Local $oP0 = Json_ArrayGet($oPatterns, 0)
T(Json_GetStr($oP0, "pattern") <> "", "patterns[0].pattern = " & Json_GetStr($oP0, "pattern"))
T(Json_GetStr($oP0, "replacement") <> "", "patterns[0].replacement = " & Json_GetStr($oP0, "replacement"))

; 序列化回 JSON（就是注入脚本内联的那份数据）
Local $t = TimerInit()
Local $sOut = Json_Stringify($oPack)
ConsoleWrite("序列化 " & Round(TimerDiff($t)) & " ms，输出 " & StringLen($sOut) & " 字符" & @CRLF)
T(StringLen($sOut) > 50000, "序列化体积合理（" & StringLen($sOut) & " 字符）")
T(StringInStr($sOut, "daemon") > 0, "引号内容没有被破坏")

Local $t = TimerInit()
Local $oBack = Json_Parse($sOut)
ConsoleWrite("重新解析 " & Round(TimerDiff($t)) & " ms" & @CRLF)
T(Json_Get($oBack, "entries").Count = 641, "往返后 entries 仍 641 条")
T(Json_Get(Json_Get($oBack, "entries"), $sQuoted) <> Json_Null(), "往返后含引号的键仍可查")

; 转义与特殊字符
Local $oEdge = Json_Parse('{"a":"引号\"和\\反斜杠","b":"换行\n结束","c":"制表\t"}')
T(Json_GetStr($oEdge, "a") = "引号""和\反斜杠", "转义往返正确: [" & Json_GetStr($oEdge, "a") & "]")
T(StringInStr(Json_GetStr($oEdge, "b"), @LF) > 0, "换行转义正确")

ConsoleWrite(($g_fail = 0 ? "全部通过" : "失败 " & $g_fail & " 项") & @CRLF)
Exit($g_fail = 0 ? 0 : 1)

