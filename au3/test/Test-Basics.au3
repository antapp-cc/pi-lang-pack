#include "..\lib\Util.au3"
#include "..\lib\Json.au3"

Global $g_fail = 0
Global $g_asar = "C:\Users\Administrator\AppData\Local\Programs\pi-network-desktop\resources\app.asar"

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

ConsoleWrite("== 基础层自检 ==" & @CRLF)

T(U_Sha256Hex("abc") = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA256('abc')")
T(U_Sha256Hex("") = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA256('')")
Local $sZh = U_Sha256Hex("中文测试")
T(StringLen($sZh) = 64, "SHA256 中文输出 64 位 hex（" & $sZh & "）")

; JSON 往返
Local $v = Json_Parse('{"a":1,"b":[1,2,{"c":"中"}],"d":true,"e":null,"f":-3.5}')
T(IsObj($v), "解析对象")
T(Json_GetInt($v, "a") = 1, "对象取整数 a=1")
Local $aB = Json_Get($v, "b")
T(Json_ArrayLen($aB) = 3, "数组长度 3")
Local $oSub = Json_ArrayGet($aB, 2)
T(Json_GetStr($oSub, "c") = "中", "嵌套字符串 中")
T(Json_Get($v, "d") = True, "布尔 true")
T(Json_IsNull(Json_Get($v, "e")), "null")
T(Json_Get($v, "f") = -3.5, "负数小数")

Local $s1 = Json_Stringify($v)
Local $v2 = Json_Parse($s1)
T(Json_GetInt($v2, "a") = 1 And Json_GetStr(Json_ArrayGet(Json_Get($v2, "b"), 2), "c") = "中", "序列化后重新解析一致")

; UTF-8 文件往返
Local $p = @TempDir & "\pilang-utf8-test.json"
U_WriteText($p, '{"名称":"多语言包","emoji":"✓"}')
Local $sBack = U_ReadText($p)
T(StringInStr($sBack, '"多语言包"') > 0, "UTF-8 写读往返（中文）")
FileDelete($p)

; 真 asar 头部
If FileExists($g_asar) Then
	Local $h = FileOpen($g_asar, $FO_READ + $FO_BINARY)
	Local $b8 = FileRead($h, 16)
	Local $iHeaderLen = _U_Int32At($b8, 4)
	Local $iJsonLen = _U_Int32At($b8, 12)
	Local $iDataStart = 8 + $iHeaderLen
	FileSetPos($h, 16, 0)
	Local $bJson = FileRead($h, $iJsonLen)
	FileClose($h)

	Local $t0 = TimerInit()
	Local $oRoot = Json_Parse(BinaryToString($bJson, 4))
	Local $msParse = TimerDiff($t0)

	T(IsObj($oRoot), "asar header 解析成功（" & Round($msParse) & " ms, JSON " & $iJsonLen & " 字节）")

	Local $oFiles = Json_Get($oRoot, "files")
	T(IsObj($oFiles), "header.files 是对象")

	; 递归统计叶子和校验 offset 边界
	Local $aStat[3] = [0, 0, 0] ; 文件数, 目录数, 总大小
	_Walk($oFiles, "", $aStat, $iDataStart)
	ConsoleWrite("    文件数=" & $aStat[0] & " 目录数=" & $aStat[1] & " 数据区总大小=" & $aStat[2] & @CRLF)
	T($aStat[0] > 1000, "文件数合理")
	T($aStat[2] <= 24161946 - $iDataStart, "所有条目 offset+size 未越界（数据区 " & (24161946 - $iDataStart) & " 字节）")

	Local $oRenderer = Json_Get(Json_Get(Json_Get($oFiles, "dist"), "files"), "renderer")
	T(IsObj($oRenderer), "找到 dist/renderer")
	Local $oIdx = Json_Get(Json_Get($oRenderer, "files"), "index.html")
	T(IsObj($oIdx), "找到 dist/renderer/index.html")
	ConsoleWrite("    index.html size=" & Json_GetStr($oIdx, "size") & " offset=" & Json_GetStr($oIdx, "offset") & @CRLF)
Else
	ConsoleWrite("[跳过] 没找到 asar：" & $g_asar & @CRLF)
EndIf

ConsoleWrite($g_fail = 0 ? "全部通过" : "失败 " & $g_fail & " 项")
ConsoleWrite(@CRLF)
Exit($g_fail = 0 ? 0 : 1)

Func _Walk($oFiles, $sPrefix, ByRef $aStat, $iDataStart)
	Local $aKeys = $oFiles.Keys()
	For $i = 0 To UBound($aKeys) - 1
		Local $sName = $aKeys[$i]
		Local $oNode = $oFiles.Item($sName)
		Local $sPath = $sPrefix & $sName
		Local $oSub = Json_Get($oNode, "files")
		If IsObj($oSub) Then
			$aStat[1] += 1
			_Walk($oSub, $sPath & "/", $aStat, $iDataStart)
		Else
			Local $iSize = Json_GetInt($oNode, "size", -1)
			Local $iOffset = Number(Json_GetStr($oNode, "offset", "-1"))
			If $iSize < 0 Or $iOffset < 0 Then
				ConsoleWrite("    [警告] 条目缺 size/offset: " & $sPath & @CRLF)
				ContinueLoop
			EndIf
			$aStat[0] += 1
			If $iOffset + $iSize > $aStat[2] Then $aStat[2] = $iOffset + $iSize
		EndIf
	Next
EndFunc

Func _U_Int32At($b, $iOff)
	Local $r = 0, $i
	For $i = 0 To 3
		$r += Number(BinaryMid($b, $iOff + $i + 1, 1)) * (2 ^ (8 * $i))
	Next
	Return $r
EndFunc
