#include-once
#include <FileConstants.au3>

; asar 结构：8 字节前缀 + headerPickle + 数据区
;   [0..3]  pickle 长度固定 4        [4..7]  headerPickle 长度
;   [8..11] header payload 长度       [12..15] JSON 长度
;   [16..]  JSON（紧凑，4 字节对齐后接数据区）
; 数据区每个文件按 header 里的 offset/size 定位，offset 相对数据区起点。
;
; 重打包策略：保持原文件在数据区里的先后顺序，只改被替换文件的内容与全表 offset；
; 新增文件追加到数据区末尾。这样未改动文件的 integrity 可以原样复用，不必重算全部哈希。

Global Const $ASAR_MARKER = "/* pi-lang-patch */"
Global Const $ASAR_BLOCK = 4194304

; $bParseTree = False 时只读 header 原文，不解析 JSON 树（补丁态快速判定用，省掉 ~400ms）
Func Asar_Open($sPath, $bParseTree = True)
	Local $h = FileOpen($sPath, $FO_READ + $FO_BINARY)
	If $h = -1 Then Return SetError(1, 0, 0)
	Local $b16 = FileRead($h, 16)
	If BinaryLen($b16) < 16 Then
		FileClose($h)
		Return SetError(2, 0, 0)
	EndIf
	Local $iHeaderLen = _Asar_Int32($b16, 4)
	Local $iJsonLen = _Asar_Int32($b16, 12)
	Local $iFileSize = FileGetSize($sPath)
	If $iHeaderLen <= 8 Or 8 + $iHeaderLen > $iFileSize Then
		FileClose($h)
		Return SetError(3, 0, 0)
	EndIf
	If $iJsonLen <= 0 Or 16 + $iJsonLen > 8 + $iHeaderLen Then
		FileClose($h)
		Return SetError(4, 0, 0)
	EndIf
	FileSetPos($h, 16, 0)
	Local $bJson = FileRead($h, $iJsonLen)
	FileClose($h)
	If BinaryLen($bJson) <> $iJsonLen Then Return SetError(5, 0, 0)

	Local $sJson = BinaryToString($bJson, 4)
	Local $o = Json_NewObject()
	$o.Item("path") = $sPath
	$o.Item("dataStart") = 8 + $iHeaderLen
	$o.Item("total") = $iFileSize
	$o.Item("headerJson") = $sJson
	$o.Item("newContent") = Json_NewObject()
	$o.Item("deleted") = Json_NewObject()
	If Not $bParseTree Then
		$o.Item("root") = 0
		Return $o
	EndIf

	Local $oRoot = Json_Parse($sJson)
	If Not IsObj($oRoot) Then Return SetError(6, 0, 0)
	Local $oFiles = Json_Get($oRoot, "files")
	If Not IsObj($oFiles) Then Return SetError(7, 0, 0)
	$o.Item("root") = $oRoot
	Return $o
EndFunc

; header 原文里是否有同名条目（不比解析整棵树省内存也不占用递归栈）
Func Asar_HasNameInHeader($o, $sFileName)
	Return StringInStr($o.Item("headerJson"), '"' & $sFileName & '":{"size"') > 0
EndFunc

Func Asar_GetRoot($o)
	Return $o.Item("root")
EndFunc

Func Asar_FilesObject($o)
	Return Json_Get($o.Item("root"), "files")
EndFunc

; 按 asar 内部路径（"dist/renderer/index.html"）取条目节点
Func Asar_GetNode($o, $sInnerPath)
	Local $aParts = StringSplit($sInnerPath, "/", 2)
	Local $oFiles = Asar_FilesObject($o)
	Local $i
	For $i = 0 To UBound($aParts) - 1
		If Not IsObj($oFiles) Then Return 0
		If Not $oFiles.Exists($aParts[$i]) Then Return 0
		Local $oNode = $oFiles.Item($aParts[$i])
		Local $bLast = ($i = UBound($aParts) - 1)
		If $bLast Then Return $oNode
		If Not IsObj($oNode) Then Return 0
		$oFiles = Json_Get($oNode, "files")
	Next
	Return 0
EndFunc

Func Asar_Has($o, $sInnerPath)
	Return IsObj(Asar_GetNode($o, $sInnerPath))
EndFunc

Func Asar_ReadBytes($o, $sInnerPath)
	Local $oNode = Asar_GetNode($o, $sInnerPath)
	If Not IsObj($oNode) Then Return SetError(1, 0, Binary(""))
	If $o.Item("newContent").Exists($sInnerPath) Then Return $o.Item("newContent").Item($sInnerPath)
	Local $iSize = Json_GetInt($oNode, "size", -1)
	Local $iOffset = Number(Json_GetStr($oNode, "offset", "-1"))
	If $iSize < 0 Or $iOffset < 0 Then Return SetError(2, 0, Binary(""))
	Local $h = FileOpen($o.Item("path"), $FO_READ + $FO_BINARY)
	If $h = -1 Then Return SetError(3, 0, Binary(""))
	FileSetPos($h, $o.Item("dataStart") + $iOffset, 0)
	Local $b = FileRead($h, $iSize)
	FileClose($h)
	If BinaryLen($b) <> $iSize Then Return SetError(4, 0, Binary(""))
	Return $b
EndFunc

Func Asar_ReadText($o, $sInnerPath)
	Local $b = Asar_ReadBytes($o, $sInnerPath)
	If @error Then Return SetError(@error, 0, "")
	Return BinaryToString($b, 4)
EndFunc

; 新增或替换：内容先进待写表，真正落盘在 Asar_Save
Func Asar_PutFile($o, $sInnerPath, $bData)
	$o.Item("newContent").Item($sInnerPath) = $bData
	Local $oDel = $o.Item("deleted")
	If $oDel.Exists($sInnerPath) Then $oDel.Remove($sInnerPath)

	If IsObj(Asar_GetNode($o, $sInnerPath)) Then Return True

	; 新条目要挂进树里，父目录不存在就补上
	Local $aParts = StringSplit($sInnerPath, "/", 2)
	Local $oFiles = Asar_FilesObject($o)
	Local $i
	For $i = 0 To UBound($aParts) - 2
		If Not $oFiles.Exists($aParts[$i]) Then
			Local $oDir = Json_NewObject()
			$oDir.Item("files") = Json_NewObject()
			$oFiles.Item($aParts[$i]) = $oDir
		EndIf
		Local $oNode = $oFiles.Item($aParts[$i])
		If Not IsObj($oNode) Then Return SetError(1, 0, False)
		$oFiles = Json_Get($oNode, "files")
		If Not IsObj($oFiles) Then
			$oFiles = Json_NewObject()
			$oNode.Item("files") = $oFiles
		EndIf
	Next
	Local $oLeaf = Json_NewObject()
	$oLeaf.Item("size") = 0
	$oLeaf.Item("integrity") = Json_NewObject()
	$oLeaf.Item("offset") = "0"
	$oFiles.Item($aParts[UBound($aParts) - 1]) = $oLeaf
	Return True
EndFunc

Func Asar_RemoveFile($o, $sInnerPath)
	Local $oNew = $o.Item("newContent")
	If $oNew.Exists($sInnerPath) Then $oNew.Remove($sInnerPath)
	$o.Item("deleted").Item($sInnerPath) = True

	Local $aParts = StringSplit($sInnerPath, "/", 2)
	Local $oFiles = Asar_FilesObject($o)
	Local $i
	For $i = 0 To UBound($aParts) - 2
		If Not $oFiles.Exists($aParts[$i]) Then Return False
		$oFiles = Json_Get($oFiles.Item($aParts[$i]), "files")
		If Not IsObj($oFiles) Then Return False
	Next
	If $oFiles.Exists($aParts[UBound($aParts) - 1]) Then
		$oFiles.Remove($aParts[UBound($aParts) - 1])
		Return True
	EndIf
	Return False
EndFunc

; 补丁标记检查：注入脚本存在且正文含 MARKER
Func Asar_IsPatched($o, $sScriptPath)
	If Not Asar_Has($o, $sScriptPath) Then Return False
	Local $s = Asar_ReadText($o, $sScriptPath)
	If @error Then Return False
	Return StringInStr($s, $ASAR_MARKER) > 0
EndFunc

; 全部叶子文件数/目录数（诊断/自检用）
Func Asar_CountFiles($o)
	Local $a = [0, 0] ; [0]=文件 [1]=目录
	_Asar_Count(Asar_FilesObject($o), $a)
	Return $a
EndFunc

Func _Asar_Count($oFiles, ByRef $aStat)
	Local $aKeys = $oFiles.Keys()
	Local $i
	For $i = 0 To UBound($aKeys) - 1
		Local $oNode = $oFiles.Item($aKeys[$i])
		If Not IsObj($oNode) Then ContinueLoop
		Local $oSub = Json_Get($oNode, "files")
		If IsObj($oSub) Then
			$aStat[1] += 1
			_Asar_Count($oSub, $aStat)
		Else
			$aStat[0] += 1
		EndIf
	Next
EndFunc

; 重打包写出。返回 True/False，失败原因在 SetError
Func Asar_Save($o, $sOutPath)
	Local $sSource = $o.Item("path")
	Local $iDataStart = $o.Item("dataStart")
	Local $oNew = $o.Item("newContent")
	Local $oDel = $o.Item("deleted")

	; 克隆树并同时按原顺序收集叶子（Scripting.Dictionary 保持插入顺序，Key 即内部路径）
	Local $oLeaves = Json_NewObject()
	Local $oNewRoot = Json_NewObject()
	Local $oNewFiles = Json_NewObject()
	$oNewRoot.Item("files") = $oNewFiles
	Local $bOk = _Asar_Clone(Asar_FilesObject($o), $oNewFiles, "", $oNew, $oDel, $oLeaves)
	If Not $bOk Then Return SetError(1, 0, False)

	; 按顺序重算 offset，替换内容则重算 integrity
	Local $aLeafPaths = $oLeaves.Keys()
	Local $iOffset = 0
	Local $i
	For $i = 0 To UBound($aLeafPaths) - 1
		Local $sPath = $aLeafPaths[$i]
		Local $oLeafInfo = $oLeaves.Item($sPath)
		Local $oNode = $oLeafInfo.Item("node")
		If $oNew.Exists($sPath) Then
			Local $bNew = $oNew.Item($sPath)
			$oNode.Item("size") = BinaryLen($bNew)
			$oNode.Item("integrity") = _Asar_Integrity($bNew)
		EndIf
		$oNode.Item("offset") = String($iOffset)
		$iOffset += Int($oNode.Item("size"))
	Next

	Local $sJson = Json_Stringify($oNewRoot)
	Local $bJson = StringToBinary($sJson, 4)
	Local $iJsonLen = BinaryLen($bJson)
	Local $iPad = Mod(4 - Mod($iJsonLen, 4), 4)
	Local $iPayloadLen = 4 + $iJsonLen + $iPad
	Local $iHeaderPartLen = 4 + $iPayloadLen

	Local $sTmp = $sOutPath & "." & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC & ".tmp"
	Local $hSrc = FileOpen($sSource, $FO_READ + $FO_BINARY)
	If $hSrc = -1 Then Return SetError(2, 0, False)
	Local $hDst = FileOpen($sTmp, $FO_OVERWRITE + $FO_CREATEPATH + $FO_BINARY)
	If $hDst = -1 Then
		FileClose($hSrc)
		Return SetError(3, 0, False)
	EndIf

	Local $bOk2 = _Asar_WriteHeader($hDst, $iHeaderPartLen, $iPayloadLen, $bJson, $iPad)
	If $bOk2 Then
		For $i = 0 To UBound($aLeafPaths) - 1
			Local $sLeafPath = $aLeafPaths[$i]
			Local $oLeafInfo = $oLeaves.Item($sLeafPath)
			Local $iSize = Int($oLeafInfo.Item("node").Item("size"))
			If $oNew.Exists($sLeafPath) Then
				FileWrite($hDst, $oNew.Item($sLeafPath))
			Else
				Local $iSrcOff = $oLeafInfo.Item("srcOffset")
				FileSetPos($hSrc, $iDataStart + $iSrcOff, 0)
				Local $bChunk = FileRead($hSrc, $iSize)
				If BinaryLen($bChunk) <> $iSize Then
					$bOk2 = False
					ExitLoop
				EndIf
				FileWrite($hDst, $bChunk)
			EndIf
		Next
	EndIf
	FileClose($hDst)
	FileClose($hSrc)

	If Not $bOk2 Then
		FileDelete($sTmp)
		Return SetError(4, 0, False)
	EndIf

	If Not _Asar_ReplaceFile($sTmp, $sOutPath) Then
		FileDelete($sTmp)
		Return SetError(5, 0, False)
	EndIf
	Return True
EndFunc

Func _Asar_WriteHeader($h, $iHeaderPartLen, $iPayloadLen, $bJson, $iPad)
	FileWrite($h, _Asar_Int32Bin(4))
	FileWrite($h, _Asar_Int32Bin($iHeaderPartLen))
	FileWrite($h, _Asar_Int32Bin($iPayloadLen))
	FileWrite($h, _Asar_Int32Bin(BinaryLen($bJson)))
	FileWrite($h, $bJson)
	If $iPad > 0 Then FileWrite($h, _Asar_Zeros($iPad))
	Return True
EndFunc

; 深克隆（叶子浅拷贝，integrity 对象共享引用——只整体替换，不内部改）
Func _Asar_Clone($oFiles, $oOutFiles, $sPrefix, $oNew, $oDel, $oLeaves)
	Local $aKeys = $oFiles.Keys()
	Local $i, $j
	For $i = 0 To UBound($aKeys) - 1
		Local $sName = $aKeys[$i]
		Local $oNode = $oFiles.Item($sName)
		If Not IsObj($oNode) Then ContinueLoop
		Local $sPath = $sPrefix & $sName
		If $oDel.Exists($sPath) Then ContinueLoop

		Local $oSub = Json_Get($oNode, "files")
		If IsObj($oSub) Then
			Local $oNewDir = Json_NewObject()
			Local $oNewSub = Json_NewObject()
			$oNewDir.Item("files") = $oNewSub
			$oOutFiles.Item($sName) = $oNewDir
			If Not _Asar_Clone($oSub, $oNewSub, $sPath & "/", $oNew, $oDel, $oLeaves) Then Return False
		Else
			Local $oLeaf = Json_NewObject()
			Local $aLeafKeys = $oNode.Keys()
			For $j = 0 To UBound($aLeafKeys) - 1
				$oLeaf.Item($aLeafKeys[$j]) = $oNode.Item($aLeafKeys[$j])
			Next
			$oOutFiles.Item($sName) = $oLeaf
			Local $oInfo = Json_NewObject()
			$oInfo.Item("node") = $oLeaf
			$oInfo.Item("srcOffset") = Number(Json_GetStr($oNode, "offset", "0"))
			$oInfo.Item("srcSize") = Json_GetInt($oNode, "size", 0)
			$oLeaves.Item($sPath) = $oInfo
		EndIf
	Next
	Return True
EndFunc

Func _Asar_Integrity($bData)
	Local $o = Json_NewObject()
	$o.Item("algorithm") = "SHA256"
	$o.Item("hash") = U_Sha256Hex($bData)
	$o.Item("blockSize") = $ASAR_BLOCK

	Local $aBlocks = _Json_NewArray()
	Local $iLen = BinaryLen($bData)
	Local $i
	For $i = 0 To $iLen - 1 Step $ASAR_BLOCK
		Local $n = $ASAR_BLOCK
		If $i + $n > $iLen Then $n = $iLen - $i
		Json_ArrayPush($aBlocks, U_Sha256Hex(BinaryMid($bData, $i + 1, $n)))
	Next
	If Json_ArrayLen($aBlocks) = 0 Then Json_ArrayPush($aBlocks, U_Sha256Hex(Binary("")))
	$o.Item("blocks") = $aBlocks
	Return $o
EndFunc

Func _Asar_Int32($b, $iOff)
	; $iOff 是 0-based 字节偏移
	Local $r = 0
	For $i = 0 To 3
		$r += Number(BinaryMid($b, $iOff + $i + 1, 1)) * (256 ^ $i)
	Next
	Return Int($r)
EndFunc

Func _Asar_Int32Bin($iValue)
	Local $h = Hex(BitAND($iValue, 0xFFFFFFFF), 8)
	Return Binary("0x" & StringMid($h, 7, 2) & StringMid($h, 5, 2) & StringMid($h, 3, 2) & StringMid($h, 1, 2))
EndFunc

Func _Asar_Zeros($iCount)
	Local $s = ""
	Local $i
	For $i = 1 To $iCount
		$s &= "00"
	Next
	Return Binary("0x" & $s)
EndFunc

; 同卷原子替换：MoveFileEx(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)
Func _Asar_ReplaceFile($sTmp, $sTarget)
	Local $aRet = DllCall("kernel32.dll", "bool", "MoveFileExW", "wstr", $sTmp, "wstr", $sTarget, "dword", 0x00000001 + 0x00000008)
	If @error Then Return False
	Return $aRet[0] <> 0
EndFunc
