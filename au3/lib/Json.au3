#include-once

; 最小 JSON：对象用 Scripting.Dictionary（二进制比较，保留键大小写与插入顺序），
; 数组用 AutoIt 一维数组（0-based），标量用字符串/数字/True/False/Null。
; 只需要能读 asar header（138KB）、config.json、词表；不追求通用 JSON 的全部边界。

Global $g_jChars[1]
Global $g_jPos = 0
Global $g_jLen = 0

Func Json_Parse($sText)
	If $sText = "" Then Return SetError(1, 0, Null)
	$g_jChars = StringSplit($sText, "", 2)
	$g_jLen = UBound($g_jChars)
	$g_jPos = 0
	Json_SkipWs()
	Local $v = Json_ParseValue()
	If @error Then Return SetError(2, 0, Null)
	Return $v
EndFunc

Func Json_NewObject()
	Local $o = ObjCreate("Scripting.Dictionary")
	$o.CompareMode = 0 ; BinaryCompare：asar 里大小写不同的文件名不能混
	Return $o
EndFunc

Func Json_IsObject($v)
	Return IsObj($v)
EndFunc

Func Json_IsArray($v)
	Return IsArray($v)
EndFunc

; Scripting.Dictionary 存不了 Null（会被吞成 Empty），JSON null 用带标记的空对象表示
Global $g_jNullTag = 0

Func Json_Null()
	If Not IsObj($g_jNullTag) Then
		$g_jNullTag = Json_NewObject()
		$g_jNullTag.Item("__json_null__") = True
	EndIf
	Return $g_jNullTag
EndFunc

Func Json_IsNull($v)
	If IsKeyword($v) = 1 Then Return True
	If Not IsObj($v) Then Return False
	Return $v.Exists("__json_null__")
EndFunc

Func Json_Get($oObj, $sKey, $vDefault = Null)
	If Not IsObj($oObj) Then Return $vDefault
	If $oObj.Exists($sKey) Then Return $oObj.Item($sKey)
	Return $vDefault
EndFunc

Func Json_Has($oObj, $sKey)
	If Not IsObj($oObj) Then Return False
	Return $oObj.Exists($sKey)
EndFunc

Func Json_Set($oObj, $sKey, $vValue)
	If Not IsObj($oObj) Then Return False
	$oObj.Item($sKey) = $vValue
	Return True
EndFunc

Func Json_GetStr($oObj, $sKey, $sDefault = "")
	Local $v = Json_Get($oObj, $sKey, Null)
	If Json_IsNull($v) Then Return $sDefault
	Return String($v)
EndFunc

Func Json_GetInt($oObj, $sKey, $iDefault = 0)
	Local $v = Json_Get($oObj, $sKey, Null)
	If Json_IsNull($v) Then Return $iDefault
	If IsNumber($v) Then Return Int($v)
	Local $n = Number($v)
	If @error Then Return $iDefault
	Return Int($n)
EndFunc

Func Json_GetBool($oObj, $sKey, $bDefault = False)
	Local $v = Json_Get($oObj, $sKey, Null)
	If Json_IsNull($v) Then Return $bDefault
	If IsBool($v) Then Return $v
	Local $s = StringLower(String($v))
	Return $s = "true" Or $s = "1"
EndFunc

Func Json_SkipWs()
	Local $c
	While $g_jPos < $g_jLen
		$c = $g_jChars[$g_jPos]
		If $c = " " Or $c = @TAB Or $c = @CR Or $c = @LF Then
			$g_jPos += 1
		Else
			ExitLoop
		EndIf
	WEnd
EndFunc

Func Json_ParseValue()
	If $g_jPos >= $g_jLen Then Return SetError(1, 0, Null)
	Local $c = $g_jChars[$g_jPos]
	Switch $c
		Case "{"
			Return Json_ParseObject()
		Case "["
			Return Json_ParseArray()
		Case '"'
			Return Json_ParseString()
		Case "t"
			If Json_MatchLit("true") Then Return True
			Return SetError(2, 0, Null)
		Case "f"
			If Json_MatchLit("false") Then Return False
			Return SetError(2, 0, Null)
		Case "n"
			If Json_MatchLit("null") Then Return Json_Null()
			Return SetError(2, 0, Json_Null())
		Case Else
			Return Json_ParseNumber()
	EndSwitch
EndFunc

Func Json_MatchLit($sLit)
	Local $n = StringLen($sLit)
	If $g_jPos + $n > $g_jLen Then Return False
	Local $s = ""
	For $i = 0 To $n - 1
		$s &= $g_jChars[$g_jPos + $i]
	Next
	If $s <> $sLit Then Return False
	$g_jPos += $n
	Return True
EndFunc

Func Json_ParseObject()
	Local $o = Json_NewObject()
	$g_jPos += 1 ; {
	Json_SkipWs()
	If $g_jPos < $g_jLen And $g_jChars[$g_jPos] = "}" Then
		$g_jPos += 1
		Return $o
	EndIf
	While $g_jPos < $g_jLen
		Json_SkipWs()
		If $g_jChars[$g_jPos] <> '"' Then Return SetError(3, $g_jPos, $o)
		Local $sKey = Json_ParseString()
		Json_SkipWs()
		If $g_jPos >= $g_jLen Or $g_jChars[$g_jPos] <> ":" Then Return SetError(4, $g_jPos, $o)
		$g_jPos += 1
		Json_SkipWs()
		Local $v = Json_ParseValue()
		Json_Set($o, $sKey, $v)
		Json_SkipWs()
		If $g_jPos >= $g_jLen Then ExitLoop
		If $g_jChars[$g_jPos] = "," Then
			$g_jPos += 1
			ContinueLoop
		EndIf
		If $g_jChars[$g_jPos] = "}" Then
			$g_jPos += 1
			Return $o
		EndIf
		Return SetError(5, $g_jPos, $o)
	WEnd
	Return SetError(6, $g_jPos, $o)
EndFunc

Func Json_ParseArray()
	Local $a = _Json_NewArray()
	$g_jPos += 1 ; [
	Json_SkipWs()
	If $g_jPos < $g_jLen And $g_jChars[$g_jPos] = "]" Then
		$g_jPos += 1
		Return $a
	EndIf
	Local $iCount = 0
	While $g_jPos < $g_jLen
		Json_SkipWs()
		Local $v = Json_ParseValue()
		If @error Then Return SetError(7, $g_jPos, $a)
		Json_ArrayPush($a, $v)
		$iCount += 1
		Json_SkipWs()
		If $g_jPos >= $g_jLen Then ExitLoop
		If $g_jChars[$g_jPos] = "," Then
			$g_jPos += 1
			ContinueLoop
		EndIf
		If $g_jChars[$g_jPos] = "]" Then
			$g_jPos += 1
			Return $a
		EndIf
		Return SetError(8, $g_jPos, $a)
	WEnd
	Return SetError(9, $g_jPos, $a)
EndFunc

; AutoIt 数组不能用 Redim 之外的动态增长，这里包一层：元素放 0-based，长度记在 $a[0]
Func _Json_NewArray()
	Local $a[1] = [0]
	Return $a
EndFunc

Func Json_ArrayPush(ByRef $aArr, $v)
	Local $n = $aArr[0]
	If UBound($aArr) <= $n + 1 Then ReDim $aArr[UBound($aArr) + 16]
	$aArr[$n + 1] = $v
	$aArr[0] = $n + 1
EndFunc

Func Json_ArrayLen($aArr)
	If Not IsArray($aArr) Then Return 0
	Return $aArr[0]
EndFunc

Func Json_ArrayGet($aArr, $iIndex)
	If Not IsArray($aArr) Then Return Null
	If $iIndex < 0 Or $iIndex >= $aArr[0] Then Return Null
	Return $aArr[$iIndex + 1]
EndFunc

Func Json_ParseString()
	$g_jPos += 1 ; "
	Local $sOut = ""
	Local $c, $sEsc
	While $g_jPos < $g_jLen
		$c = $g_jChars[$g_jPos]
		If $c = '"' Then
			$g_jPos += 1
			Return $sOut
		EndIf
		If $c = "\" Then
			$g_jPos += 1
			If $g_jPos >= $g_jLen Then ExitLoop
			$sEsc = $g_jChars[$g_jPos]
			Switch $sEsc
				Case '"'
					$sOut &= '"'
					$g_jPos += 1
				Case "\"
					$sOut &= "\"
					$g_jPos += 1
				Case "/"
					$sOut &= "/"
					$g_jPos += 1
				Case "b"
					$sOut &= Chr(8)
					$g_jPos += 1
				Case "f"
					$sOut &= Chr(12)
					$g_jPos += 1
				Case "n"
					$sOut &= @LF
					$g_jPos += 1
				Case "r"
					$sOut &= @CR
					$g_jPos += 1
				Case "t"
					$sOut &= @TAB
					$g_jPos += 1
				Case "u"
					$sOut &= Json_ParseUnicodeEscape()
				Case Else
					$sOut &= $sEsc
					$g_jPos += 1
			EndSwitch
		Else
			$sOut &= $c
			$g_jPos += 1
		EndIf
	WEnd
	Return SetError(10, $g_jPos, $sOut)
EndFunc

Func Json_ParseUnicodeEscape()
	; 已停在 'u' 上；读 4 位十六进制
	$g_jPos += 1
	Local $sHex = ""
	For $i = 0 To 3
		If $g_jPos >= $g_jLen Then ExitLoop
		$sHex &= $g_jChars[$g_jPos]
		$g_jPos += 1
	Next
	If StringLen($sHex) < 4 Then Return ""
	Return ChrW(Int("0x" & $sHex))
EndFunc

Func Json_ParseNumber()
	Local $sNum = ""
	Local $c
	While $g_jPos < $g_jLen
		$c = $g_jChars[$g_jPos]
		If ($c >= "0" And $c <= "9") Or $c = "-" Or $c = "+" Or $c = "." Or $c = "e" Or $c = "E" Then
			$sNum &= $c
			$g_jPos += 1
		Else
			ExitLoop
		EndIf
	WEnd
	If $sNum = "" Then Return SetError(11, $g_jPos, Null)
	Local $n = Number($sNum)
	If @error Then Return SetError(12, $g_jPos, Null)
	Return $n
EndFunc

; ---- 序列化 ----

Func Json_Stringify($v, $bIndent = False)
	Return _Json_Str($v, $bIndent, 0)
EndFunc

Func _Json_Str($v, $bIndent, $iLevel)
	If Json_IsNull($v) Then Return "null"
	If IsBool($v) Then Return ($v ? "true" : "false")
	If IsNumber($v) Then Return Json_NumToStr($v)
	If IsString($v) Then Return Json_Quote($v)
	If IsObj($v) Then Return _Json_StrObject($v, $bIndent, $iLevel)
	If IsArray($v) Then Return _Json_StrArray($v, $bIndent, $iLevel)
	Return "null"
EndFunc

Func Json_NumToStr($n)
	If IsInt($n) Then Return String($n)
	Local $i = Int($n)
	If $i = $n And Abs($n) < 2147483647 Then Return String($i)
	Local $s = String($n)
	If StringInStr($s, ".") = 0 And StringInStr($s, "e") = 0 And StringInStr($s, "E") = 0 Then Return $s
	Return $s
EndFunc

Func _Json_StrObject($o, $bIndent, $iLevel)
	Local $aKeys = $o.Keys()
	Local $aItems = $o.Items()
	Local $n = UBound($aKeys)
	If $n = 0 Then Return "{}"
	Local $sPad = "", $sItemPad = "", $sEndPad = "", $sSep = ",", $sColon = ":"
	If $bIndent Then
		$sPad = _Json_Pad($iLevel + 1)
		$sItemPad = _Json_Pad($iLevel + 1)
		$sEndPad = _Json_Pad($iLevel)
		$sSep = "," & @CRLF
		$sColon = ": "
	EndIf
	Local $sOut = "{" & ($bIndent ? @CRLF : "")
	For $i = 0 To $n - 1
		$sOut &= ($bIndent ? $sItemPad : "") & Json_Quote($aKeys[$i]) & $sColon
		$sOut &= _Json_Str($aItems[$i], $bIndent, $iLevel + 1)
		If $i < $n - 1 Then $sOut &= $sSep
	Next
	If $bIndent Then $sOut &= @CRLF & $sEndPad
	Return $sOut & "}"
EndFunc

Func _Json_StrArray($a, $bIndent, $iLevel)
	Local $n = Json_ArrayLen($a)
	If $n = 0 Then Return "[]"
	Local $sSep = ",", $sPad = ""
	If $bIndent Then
		$sSep = "," & @CRLF
		$sPad = _Json_Pad($iLevel + 1)
	EndIf
	Local $sOut = "[" & ($bIndent ? @CRLF : "")
	For $i = 0 To $n - 1
		$sOut &= ($bIndent ? $sPad : "") & _Json_Str(Json_ArrayGet($a, $i), $bIndent, $iLevel + 1)
		If $i < $n - 1 Then $sOut &= $sSep
	Next
	If $bIndent Then $sOut &= @CRLF & _Json_Pad($iLevel)
	Return $sOut & "]"
EndFunc

Func _Json_Pad($iLevel)
	Local $s = ""
	For $i = 1 To $iLevel
		$s &= "  "
	Next
	Return $s
EndFunc

; 只转义 JSON 语法的必要字符，非 ASCII（中文）原样输出：写成 UTF-8 后体积小 3 倍，
; 和 C# 版 UnsafeRelaxedJsonEscaping 的行为一致
Func Json_Quote($s)
	Local $n = StringLen($s), $sOut = '"', $c, $iCode
	For $i = 1 To $n
		$c = StringMid($s, $i, 1)
		Switch $c
			Case '"'
				$sOut &= '\"'
			Case "\"
				$sOut &= "\\"
			Case @CR
				$sOut &= '\r'
			Case @LF
				$sOut &= '\n'
			Case @TAB
				$sOut &= '\t'
			Case Else
				$iCode = AscW($c)
				If $iCode < 32 Then
					$sOut &= "\u" & StringRight("0000" & Hex($iCode, 4), 4)
				Else
					$sOut &= $c
				EndIf
		EndSwitch
	Next
	Return $sOut & '"'
EndFunc
