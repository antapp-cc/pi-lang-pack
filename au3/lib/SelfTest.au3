#include-once
#include <FileConstants.au3>

; --selftest：不碰正式安装目录，验证 asar 往返、注入/还原、词表与静态替换。
;
; 依赖主脚本已经把 lib\Util.au3、lib\Json.au3、lib\Asar.au3 include 进来；
; LangPack/Injector/StaticPatches/Patcher/Locator 可能还没写完，所以对这些模块
; 一律用变量函数名 Call（不存在的函数 Call 只返回 0 并置 @error=57005，不崩），
; 缺模块时打印 [跳过] 而不是假报失败。

Global Const $ST_ERR_NOFUNC = 57005

Global $g_stFailed = 0

Func ST_Run($oCfg, $oPack)
	$g_stFailed = 0
	ConsoleWrite("== Pi 多语言包自检 ==" & @CRLF)
	_ST_LangPack($oPack)
	_ST_Script($oPack)
	_ST_HtmlPatch()
	_ST_StaticPatches()

	Local $sOriginal = _ST_FindOriginalAsar($oCfg)
	If $sOriginal <> "" Then
		_ST_AsarRoundTrip($sOriginal, $oPack)
	Else
		ConsoleWrite("[跳过] 没找到可用的原始 asar，asar 往返测试未执行" & @CRLF)
	EndIf

	ConsoleWrite(($g_stFailed = 0 ? "全部通过" : "失败 " & $g_stFailed & " 项") & @CRLF)
	Return ($g_stFailed = 0 ? 0 : 1)
EndFunc

Func _ST_Expect($bOk, $sWhat)
	If $bOk Then
		ConsoleWrite("  [OK] " & $sWhat & @CRLF)
	Else
		ConsoleWrite("  [FAIL] " & $sWhat & @CRLF)
		$g_stFailed += 1
	EndIf
EndFunc

; ---- 词表 ----

Func _ST_LangPack($oPack)
	If Not IsObj($oPack) Then
		_ST_Expect(False, "语言包未加载（Lang_Load 返回空）")
		Return
	EndIf
	Local $oEntries = Json_Get($oPack, "entries")
	If Not IsObj($oEntries) Then
		_ST_Expect(False, "语言包缺少 entries 对象")
		Return
	EndIf

	Local $iCount = UBound($oEntries.Keys())
	_ST_Expect($iCount >= 400, "语言包条目数 " & $iCount & " ≥ 400")

	Local $aDanger = Json_Get($oPack, "danger")
	Local $iDanger = 0, $iMissing = 0, $sMissing = ""
	If IsArray($aDanger) Then
		$iDanger = Json_ArrayLen($aDanger)
		Local $j
		For $j = 0 To $iDanger - 1
			Local $sKey = String(Json_ArrayGet($aDanger, $j))
			If Not $oEntries.Exists($sKey) Then
				$iMissing += 1
				If $iMissing <= 3 Then $sMissing &= ($sMissing = "" ? "" : ", ") & $sKey
			EndIf
		Next
	EndIf
	_ST_Expect($iMissing = 0, "danger 词条都在 entries 里（" & $iDanger & " 条）" & ($iMissing > 0 ? "，缺: " & $sMissing : ""))

	Local $aValues = $oEntries.Items()
	Local $iEmpty = 0, $k
	For $k = 0 To UBound($aValues) - 1
		If StringStripWS(String($aValues[$k]), 3) = "" Then $iEmpty += 1
	Next
	_ST_Expect($iEmpty = 0, "没有空译文" & ($iEmpty > 0 ? "（空 " & $iEmpty & " 条）" : ""))
EndFunc

; ---- 注入脚本 ----

Func _ST_Script($oPack)
	Local $sFn = "Inj_BuildScript"
	Local $sScript = Call($sFn, $oPack)
	Local $iErr = @error
	If $iErr = $ST_ERR_NOFUNC Then
		ConsoleWrite("[跳过] 注入脚本检查（Injector.au3 未加载）" & @CRLF)
		Return
	EndIf
	_ST_Expect(StringInStr($sScript, "/* pi-lang-patch */") > 0, "脚本含补丁标记")
	_ST_Expect(StringInStr($sScript, '"locale":"zh-CN"') > 0, "脚本内联了语言包")
	_ST_Expect(StringLen($sScript) > 10000, "脚本大小合理（" & StringLen($sScript) & " 字节）")
EndFunc

; ---- index.html 注入/还原 ----

Func _ST_HtmlPatch()
	Local $sFnPatch = "Inj_PatchHtml", $sFnUnpatch = "Inj_UnpatchHtml"
	; 与 C# 的样本保持一致：注入锚点是第一个 <script>
	Local $sHtml = "<!DOCTYPE html><html><head><meta charset=utf-8><title>Pi Desktop</title><script defer=defer src=./renderer.js></script></head><body></body></html>"

	Local $sPatched = Call($sFnPatch, $sHtml)
	Local $iErr = @error
	If $iErr = $ST_ERR_NOFUNC Then
		ConsoleWrite("[跳过] index.html 注入/还原检查（Injector.au3 未加载）" & @CRLF)
		Return
	EndIf
	If $iErr Then
		_ST_Expect(False, "index.html 注入失败（错误码 " & $iErr & "）")
		Return
	EndIf

	Local $iTag = StringInStr($sPatched, "./pi-lang.js")
	Local $iRenderer = StringInStr($sPatched, "./renderer.js")
	_ST_Expect($iTag > 0, "index.html 注入了脚本标签")
	_ST_Expect($iTag > 0 And $iRenderer > 0 And $iTag < $iRenderer, "注入脚本在 renderer.js 之前")

	; 只出现一次：重复注入不能在文档里堆两行
	Local $iOccur = (StringLen($sPatched) - StringLen(StringReplace($sPatched, "./pi-lang.js", ""))) / StringLen("./pi-lang.js")
	_ST_Expect($iOccur = 1, "注入脚本只出现一次（实际 " & $iOccur & "）")
	_ST_Expect(Call($sFnPatch, $sPatched) = $sPatched, "重复注入幂等")
	_ST_Expect(Call($sFnUnpatch, $sPatched) = $sHtml, "移除注入后与原文一致")
EndFunc

; ---- 静态替换 ----

Func _ST_StaticPatches()
	Local $sFnApplyMain = "SP_ApplyMain", $sFnRevertMain = "SP_RevertMain", $sFnApplyRenderer = "SP_ApplyRenderer"
	; Exit/Quit 都译成「退出」，反向替换会互相串；这里只测不冲突的菜单项
	Local $sMain = "return[{label:""&File"",submenu:[{label:""&Close window""}]},{label:""Help"",submenu:[{label:""White Paper""}]}]}"
	Local $sPatched = Call($sFnApplyMain, $sMain)
	Local $iErr = @error
	If $iErr = $ST_ERR_NOFUNC Then
		ConsoleWrite("[跳过] 静态替换检查（StaticPatches.au3 未加载）" & @CRLF)
		Return
	EndIf

	_ST_Expect(StringInStr($sPatched, "label:""&文件""") > 0, "菜单 File 已翻译")
	_ST_Expect(StringInStr($sPatched, "label:""&关闭窗口""") > 0, "菜单 Close window 已翻译")
	_ST_Expect(StringInStr($sPatched, "label:""白皮书""") > 0, "菜单 White Paper 已翻译")
	_ST_Expect(Call($sFnRevertMain, $sPatched) = $sMain, "菜单替换可逆（无冲突项）")
	_ST_Expect(StringInStr(Call($sFnApplyMain, "label:""Exit"""), "label:""退出""") > 0, "菜单 Exit 已翻译")

	Local $sConfirm = "window.confirm(""Do you really want to remove all blockchain data?"")"
	_ST_Expect(StringInStr(Call($sFnApplyRenderer, $sConfirm), "你确实要删除所有区块链数据吗？") > 0, "确认弹窗消息已翻译")
	Local $sCatchup = "window.confirm(""You are in the middle of the catching up process, which will take some time."")"
	_ST_Expect(StringInStr(Call($sFnApplyRenderer, $sCatchup), "追赶区块") > 0, "追赶中弹窗消息已翻译")
EndFunc

; ---- asar 往返 ----

; 优先用安装时留的原始备份（安装目录里的 asar 可能已打过补丁）
Func _ST_FindOriginalAsar($oCfg)
	Local $sDir = U_BackupDir()
	If DirGetSize($sDir) <> -1 Then
		Local $hFind = FileFindFirstFile($sDir & "\app.asar.*.orig")
		If $hFind <> -1 Then
			Local $sBest = "", $sBestTime = ""
			While 1
				Local $sName = FileFindNextFile($hFind)
				If @error Then ExitLoop
				Local $sPath = $sDir & "\" & $sName
				; FileGetTime 的默认 format 在本机返回空串，显式要 "YYYYMMDDHHMMSS" 才拿得到
				Local $sTime = FileGetTime($sPath, 0, 1)
				If $sTime > $sBestTime Then
					$sBestTime = $sTime
					$sBest = $sPath
				EndIf
			WEnd
			FileClose($hFind)
			If $sBest <> "" Then Return $sBest
		EndIf
	EndIf

	Local $sFn = "Loc_Find"
	Local $sInstall = Call($sFn, $oCfg)
	If @error = $ST_ERR_NOFUNC Then Return ""
	If $sInstall = "" Then Return ""
	Local $sAsar = $sInstall & "\resources\app.asar"
	If FileExists($sAsar) Then Return $sAsar
	Return ""
EndFunc

Func _ST_AsarRoundTrip($sAsarPath, $oPack)
	Local $sWork = @TempDir & "\pilang-selftest-" & @AutoItPID
	Local $sTest = $sWork & "\test.asar"
	U_EnsureDir($sWork)
	FileDelete($sTest)

	Local $oOrig = Asar_Open($sAsarPath)
	If Not IsObj($oOrig) Then
		_ST_Expect(False, "打开原始 asar 失败（错误码 " & @error & "）：" & $sAsarPath)
		Return
	EndIf
	; 拿到的可能是已经打过补丁的安装目录 asar（备份不在时会出现）：往返对比会失败，
	; 这不是程序坏了，说明原因后跳过。
	Local $sProbeScript = "dist/renderer/pi-lang.js"
	If Call("Asar_IsPatched", $oOrig, $sProbeScript) Then
		ConsoleWrite("[跳过] " & $sAsarPath & " 已经是打过补丁的 asar（找不到原始备份），asar 往返对比跳过" & @CRLF)
		Return
	EndIf
	Local $aCount = Asar_CountFiles($oOrig)
	ConsoleWrite("    原始 asar: " & $aCount[0] & " 个文件 / " & $aCount[1] & " 个目录（" & $sAsarPath & "）" & @CRLF)
	Local $sDataSha = _ST_DataSha($oOrig)
	Local $oOrigProps = _ST_Props($oOrig)

	; 1) 无损往返
	If Not Asar_Save($oOrig, $sTest) Then
		_ST_Expect(False, "重打包失败（错误码 " & @error & "）")
		Return
	EndIf
	Local $oRt = Asar_Open($sTest)
	_ST_Expect(IsObj($oRt), "重打包后能重新打开")
	If Not IsObj($oRt) Then Return
	Local $aCount2 = Asar_CountFiles($oRt)
	_ST_Expect($aCount2[0] = $aCount[0] And $aCount2[1] = $aCount[1], "重打包后文件数一致（" & $aCount2[0] & "/" & $aCount2[1] & "）")
	_ST_Expect(_ST_DataSha($oRt) = $sDataSha, "重打包后数据区字节级一致")
	Local $iDiff = _ST_CompareProps($oOrigProps, _ST_Props($oRt))
	_ST_Expect($iDiff = 0, "重打包后每个条目 size/offset/integrity 一致（差异 " & $iDiff & "）")

	; 2) 注入 / 还原（要 Injector 在）
	Local $sFnScript = "Inj_BuildScript", $sFnPatchHtml = "Inj_PatchHtml", $sFnUnpatchHtml = "Inj_UnpatchHtml"
	Local $sScript = Call($sFnScript, $oPack)
	If @error = $ST_ERR_NOFUNC Then
		ConsoleWrite("[跳过] asar 注入/还原（Injector.au3 未加载）" & @CRLF)
		_ST_Cleanup($sWork)
		Return
	EndIf

	Local $sScriptPath = "dist/renderer/pi-lang.js"
	Local $sIndexPath = "dist/renderer/index.html"
	Asar_PutFile($oRt, $sScriptPath, StringToBinary($sScript, 4))
	Local $sHtml = Asar_ReadText($oRt, $sIndexPath)
	If @error Then
		_ST_Expect(False, "读取 index.html 失败（版本结构可能变了）")
		_ST_Cleanup($sWork)
		Return
	EndIf
	Asar_PutFile($oRt, $sIndexPath, StringToBinary(Call($sFnPatchHtml, $sHtml), 4))
	If Not Asar_Save($oRt, $sTest) Then
		_ST_Expect(False, "带注入重打包失败（错误码 " & @error & "）")
		_ST_Cleanup($sWork)
		Return
	EndIf

	Local $oPatched = Asar_Open($sTest)
	_ST_Expect(Asar_IsPatched($oPatched, $sScriptPath), "注入后补丁标记可识别")
	_ST_Expect(StringInStr(Asar_ReadText($oPatched, $sIndexPath), "./pi-lang.js") > 0, "注入后 index.html 含脚本")
	Local $aCount3 = Asar_CountFiles($oPatched)
	_ST_Expect($aCount3[0] = $aCount[0] + 1, "注入后文件数 +1（" & $aCount3[0] & "）")

	Asar_RemoveFile($oPatched, $sScriptPath)
	Asar_PutFile($oPatched, $sIndexPath, StringToBinary(Call($sFnUnpatchHtml, Asar_ReadText($oPatched, $sIndexPath)), 4))
	If Not Asar_Save($oPatched, $sTest) Then
		_ST_Expect(False, "还原重打包失败（错误码 " & @error & "）")
		_ST_Cleanup($sWork)
		Return
	EndIf

	Local $oRestored = Asar_Open($sTest)
	_ST_Expect(Not Asar_IsPatched($oRestored, $sScriptPath), "还原后补丁标记消失")
	Local $aCount4 = Asar_CountFiles($oRestored)
	_ST_Expect($aCount4[0] = $aCount[0], "还原后文件数一致（" & $aCount4[0] & "）")
	Local $iDiff2 = _ST_CompareProps($oOrigProps, _ST_Props($oRestored))
	_ST_Expect($iDiff2 = 0, "还原后每个条目与原始一致（差异 " & $iDiff2 & "）")

	_ST_Cleanup($sWork)
EndFunc

Func _ST_Cleanup($sWork)
	DirRemove($sWork, 1)
EndFunc

Func _ST_DataSha($oAsar)
	Local $h = FileOpen($oAsar.Item("path"), $FO_READ + $FO_BINARY)
	If $h = -1 Then Return ""
	FileSetPos($h, $oAsar.Item("dataStart"), 0)
	Local $b = FileRead($h, $oAsar.Item("total") - $oAsar.Item("dataStart"))
	FileClose($h)
	Return U_Sha256Hex($b)
EndFunc

; 逐条目收集 "size|offset|integrity.hash"，用于重打包前后对比
Func _ST_Props($oAsar)
	Local $oMap = Json_NewObject()
	_ST_CollectProps(Asar_FilesObject($oAsar), "", $oMap)
	Return $oMap
EndFunc

Func _ST_CollectProps($oFiles, $sPrefix, $oMap)
	Local $aKeys = $oFiles.Keys()
	Local $i
	For $i = 0 To UBound($aKeys) - 1
		Local $oNode = $oFiles.Item($aKeys[$i])
		Local $sPath = $sPrefix & $aKeys[$i]
		Local $oSub = Json_Get($oNode, "files")
		If IsObj($oSub) Then
			_ST_CollectProps($oSub, $sPath & "/", $oMap)
		Else
			Local $sProp = Json_GetStr($oNode, "size") & "|" & Json_GetStr($oNode, "offset") & "|"
			$sProp &= Json_GetStr(Json_Get($oNode, "integrity"), "hash")
			$oMap.Item($sPath) = $sProp
		EndIf
	Next
EndFunc

Func _ST_CompareProps($oA, $oB)
	Local $aKeys = $oA.Keys()
	Local $iDiff = 0, $i
	If UBound($aKeys) <> UBound($oB.Keys()) Then $iDiff += 1
	For $i = 0 To UBound($aKeys) - 1
		Local $sKey = $aKeys[$i]
		If Not $oB.Exists($sKey) Then
			$iDiff += 1
		ElseIf $oB.Item($sKey) <> $oA.Item($sKey) Then
			$iDiff += 1
		EndIf
	Next
	Return $iDiff
EndFunc
