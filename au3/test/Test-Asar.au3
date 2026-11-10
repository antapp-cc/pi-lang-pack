#include "..\lib\Util.au3"
#include "..\lib\Json.au3"
#include "..\lib\Asar.au3"

Global $g_fail = 0
Global $g_src = "C:\Users\Administrator\AppData\Roaming\PiLang\backup\app.asar.0.6.4.orig"
Global $g_work = @ScriptDir & "\work"

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

Func _DataSha($o)
	Local $h = FileOpen($o.Item("path"), $FO_READ + $FO_BINARY)
	If $h = -1 Then Return ""
	FileSetPos($h, $o.Item("dataStart"), 0)
	Local $b = FileRead($h, $o.Item("total") - $o.Item("dataStart"))
	FileClose($h)
	Return U_Sha256Hex($b)
EndFunc

Func _PropsToList($o)
	Local $oMap = Json_NewObject()
	_CollectProps(Asar_FilesObject($o), "", $oMap)
	Return $oMap
EndFunc

Func _CollectProps($oFiles, $sPrefix, $oMap)
	Local $aKeys = $oFiles.Keys()
	For $i = 0 To UBound($aKeys) - 1
		Local $oNode = $oFiles.Item($aKeys[$i])
		Local $sPath = $sPrefix & $aKeys[$i]
		Local $oSub = Json_Get($oNode, "files")
		If IsObj($oSub) Then
			_CollectProps($oSub, $sPath & "/", $oMap)
		Else
			$oMap.Item($sPath) = Json_GetStr($oNode, "size") & "|" & Json_GetStr($oNode, "offset") & "|" & Json_GetStr(Json_Get($oNode, "integrity"), "hash")
		EndIf
	Next
EndFunc

ConsoleWrite("== asar 层自检 ==" & @CRLF)
U_EnsureDir($g_work)

If Not FileExists($g_src) Then
	ConsoleWrite("[跳过] 找不到原始 asar 备份：" & $g_src & @CRLF)
	Exit(2)
EndIf

Local $tAll = TimerInit()
Local $t = TimerInit()
Local $o = Asar_Open($g_src)
T(IsObj($o), "打开原版 asar（" & Round(TimerDiff($t)) & " ms）")
If Not IsObj($o) Then
	ConsoleWrite("打开失败，错误码 " & @error & @CRLF)
	Exit(1)
EndIf
Local $aCount = Asar_CountFiles($o)
T($aCount[0] = 540 And $aCount[1] = 60, "文件/目录数 = 540/60（实际 " & $aCount[0] & "/" & $aCount[1] & "）")

Local $sOrigDataSha = _DataSha($o)
Local $oOrigProps = _PropsToList($o)

Local $sRt = $g_work & "\rt.asar"
FileDelete($sRt)
$t = TimerInit()
Local $bSaved = Asar_Save($o, $sRt)
T($bSaved, "重打包写出（" & Round(TimerDiff($t)) & " ms，错误 " & @error & "）")
If Not $bSaved Then
	ConsoleWrite("失败 " & $g_fail & " 项" & @CRLF)
	Exit(1)
EndIf
ConsoleWrite("    原 " & FileGetSize($g_src) & " -> 新 " & FileGetSize($sRt) & " 字节" & @CRLF)

$t = TimerInit()
Local $o2 = Asar_Open($sRt)
T(IsObj($o2), "重新打开重打包结果（" & Round(TimerDiff($t)) & " ms）")
T(_DataSha($o2) = $sOrigDataSha, "数据区字节级一致")

Local $oRtProps = _PropsToList($o2)
Local $iDiff = 0
Local $aKeys = $oOrigProps.Keys()
For $i = 0 To UBound($aKeys) - 1
	Local $k = $aKeys[$i]
	If Not $oRtProps.Exists($k) Then
		$iDiff += 1
		If $iDiff <= 3 Then ConsoleWrite("    缺条目: " & $k & @CRLF)
	ElseIf $oRtProps.Item($k) <> $oOrigProps.Item($k) Then
		$iDiff += 1
		If $iDiff <= 3 Then ConsoleWrite("    不一致: " & $k & " " & $oOrigProps.Item($k) & " vs " & $oRtProps.Item($k) & @CRLF)
	EndIf
Next
T($iDiff = 0, "全部条目 size/offset/integrity 与原版一致（差异 " & $iDiff & "）")

; ---- 注入测试（用假脚本，真脚本在 Patch 层测）----
Local $o3 = Asar_Open($sRt)
Local $sJs = "/* pi-lang-patch */" & @CRLF & "(function(){var x=1;})();" & @CRLF
T(Asar_PutFile($o3, "dist/renderer/pi-lang.js", StringToBinary($sJs, 4)), "写入新条目 pi-lang.js")
Local $sHtml = Asar_ReadText($o3, "dist/renderer/index.html")
Local $sIdx = StringInStr($sHtml, "<script")
T($sIdx > 0, "读到 index.html 且能找到 <script>（" & StringLen($sHtml) & " 字节）")
Local $sNewHtml = StringLeft($sHtml, $sIdx - 1) & "<script defer=defer src=./pi-lang.js></script>" & StringMid($sHtml, $sIdx)
Asar_PutFile($o3, "dist/renderer/index.html", StringToBinary($sNewHtml, 4))

Local $sPatched = $g_work & "\patched.asar"
FileDelete($sPatched)
$t = TimerInit()
Local $bPatched = Asar_Save($o3, $sPatched)
T($bPatched, "带注入重打包（" & Round(TimerDiff($t)) & " ms，错误 " & @error & "）")

Local $o4 = Asar_Open($sPatched)
T(Asar_IsPatched($o4, "dist/renderer/pi-lang.js"), "注入后识别为已打补丁")
T(StringInStr(Asar_ReadText($o4, "dist/renderer/index.html"), "pi-lang.js") > 0, "index.html 含注入脚本")
Local $aCount2 = Asar_CountFiles($o4)
T($aCount2[0] = 541, "文件数 541（实际 " & $aCount2[0] & "）")
T(Asar_ReadText($o4, "dist/renderer/pi-lang.js") = $sJs, "新条目内容可读回")

; 未改动的文件抽样核对
Local $aSample[5] = ["package.json", "dist/main/main.js", "dist/renderer/renderer.js", "dist/renderer/style.css", "dist/main/preload.js"]
Local $iSampleOk = 0
For $i = 0 To 4
	If Not Asar_Has($o4, $aSample[$i]) Then ContinueLoop
	Local $sA = U_Sha256Hex(Asar_ReadBytes($o, $aSample[$i]))
	Local $sB = U_Sha256Hex(Asar_ReadBytes($o4, $aSample[$i]))
	If $sA = $sB Then
		$iSampleOk += 1
	Else
		ConsoleWrite("    内容变了: " & $aSample[$i] & @CRLF)
	EndIf
Next
T($iSampleOk = 5, "抽样 5 个未改动文件内容一致（" & $iSampleOk & "/5）")

; ---- 还原测试 ----
Local $o5 = Asar_Open($sPatched)
Asar_RemoveFile($o5, "dist/renderer/pi-lang.js")
Local $sBack = StringReplace(Asar_ReadText($o5, "dist/renderer/index.html"), "<script defer=defer src=./pi-lang.js></script>", "")
Asar_PutFile($o5, "dist/renderer/index.html", StringToBinary($sBack, 4))
Local $sRestored = $g_work & "\restored.asar"
FileDelete($sRestored)
T(Asar_Save($o5, $sRestored), "还原重打包（错误 " & @error & "）")
Local $o6 = Asar_Open($sRestored)
T(Not Asar_IsPatched($o6, "dist/renderer/pi-lang.js"), "还原后不再是补丁态")
T(_PropsToList($o6).Count = $oOrigProps.Count, "还原后条目数一致")
Local $oRProps = _PropsToList($o6)
Local $iDiff2 = 0
Local $aK2 = $oOrigProps.Keys()
For $i = 0 To UBound($aK2) - 1
	If Not $oRProps.Exists($aK2[$i]) Then
		$iDiff2 += 1
	ElseIf $oRProps.Item($aK2[$i]) <> $oOrigProps.Item($aK2[$i]) Then
		$iDiff2 += 1
	EndIf
Next
T($iDiff2 = 0, "还原后条目属性与原版一致（差异 " & $iDiff2 & "）")

ConsoleWrite("总耗时 " & Round(TimerDiff($tAll) / 1000, 1) & " 秒" & @CRLF)
ConsoleWrite(($g_fail = 0 ? "全部通过" : "失败 " & $g_fail & " 项") & @CRLF)
Exit($g_fail = 0 ? 0 : 1)
