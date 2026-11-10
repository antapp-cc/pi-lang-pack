#include-once

; 往 asar 里塞翻译脚本、改 index.html。这里的路径全是 asar 内部路径，不是磁盘路径。

Global Const $INJ_SCRIPT_PATH = "dist/renderer/pi-lang.js"
Global Const $INJ_INDEX_PATH = "dist/renderer/index.html"
Global Const $INJ_TEMPLATE_NAME = "pi-lang.js.template"
Global Const $INJ_SCRIPT_TAG = '<script defer=defer src=./pi-lang.js></script>'

; 模板每次启动都要在运行期资源目录里：编译后由主脚本 FileInstall 释放，这里只兜底补一次。
; 0 字节也算没释放——FileInstall 失败留下的空文件不补就会生成空脚本。
Func Inj_EnsureResources()
	Local $sTarget = U_ResourceDir() & "\" & $INJ_TEMPLATE_NAME
	Local $bOk = FileExists($sTarget) And FileGetSize($sTarget) > 0
	If $bOk Then Return True

	Local $sSrc = _Inj_SourceTemplatePath()
	If $sSrc = "" Then Return SetError(1, 0, False)
	Local $sText = U_ReadText($sSrc)
	If @error Then Return SetError(2, 0, False)
	If Not U_WriteText($sTarget, $sText) Then Return SetError(3, 0, False)
	Return True
EndFunc

; 运行期资源目录优先；后两个候选是开发期（以及 test\ 下自检脚本）直接跑源码用的
Func _Inj_SourceTemplatePath()
	Local $aCand[3] = [ _
		U_ResourceDir() & "\" & $INJ_TEMPLATE_NAME, _
		@ScriptDir & "\res\" & $INJ_TEMPLATE_NAME, _
		@ScriptDir & "\..\res\" & $INJ_TEMPLATE_NAME _
	]
	Local $i
	For $i = 0 To UBound($aCand) - 1
		If FileExists($aCand[$i]) And FileGetSize($aCand[$i]) > 0 Then Return $aCand[$i]
	Next
	Return ""
EndFunc

Func Inj_BuildScript($oPack)
	Inj_EnsureResources()
	Local $sPath = _Inj_SourceTemplatePath()
	If $sPath = "" Then Return SetError(1, 0, "")
	Local $sTemplate = U_ReadText($sPath)
	If @error Or $sTemplate = "" Then Return SetError(2, 0, "")

	Local $oData = Json_NewObject()
	Json_Set($oData, "locale", Json_GetStr($oPack, "locale", "zh-CN"))
	Json_Set($oData, "version", Json_GetStr($oPack, "version", ""))
	Local $oEntries = Json_Get($oPack, "entries", Null)
	If Not IsObj($oEntries) Then $oEntries = Json_NewObject()
	Json_Set($oData, "entries", $oEntries)
	Local $vDanger = Json_Get($oPack, "danger", Null)
	If Not IsArray($vDanger) Then $vDanger = _Json_NewArray()
	Json_Set($oData, "danger", $vDanger)
	Local $vPatterns = Json_Get($oPack, "patterns", Null)
	If Not IsArray($vPatterns) Then $vPatterns = _Json_NewArray()
	Json_Set($oData, "patterns", $vPatterns)

	; JSON 直接内联进脚本字面量。Json_Stringify 会把非 ASCII 转成 \uXXXX，
	; 脚本里不出现裸中文，落盘编码就不用操心。
	Local $sJson = Json_Stringify($oData)
	Local $sOut = StringReplace($sTemplate, "__PI_LANG_DATA__", $sJson, 0, 1)

	; 补丁态判定（Asar_IsPatched）靠这行标记，模板被改坏时宁可报错也别产出白板脚本
	If StringInStr($sOut, "/* pi-lang-patch */", 0, 1) = 0 Then Return SetError(3, 0, "")
	Return $sOut
EndFunc

; 插在首个 <script 之前：defer 脚本按文档顺序执行，我们的必须排在 renderer.js 前面
Func Inj_PatchHtml($sHtml)
	If StringInStr($sHtml, "pi-lang.js", 0, 1) > 0 Then Return $sHtml

	Local $iAnchor = StringInStr($sHtml, "<script", 0, 1)
	If $iAnchor = 0 Then Return SetError(1, 0, $sHtml)
	Return StringLeft($sHtml, $iAnchor - 1) & $INJ_SCRIPT_TAG & StringMid($sHtml, $iAnchor)
EndFunc

Func Inj_UnpatchHtml($sHtml)
	Return StringReplace($sHtml, $INJ_SCRIPT_TAG, "", 0, 1)
EndFunc
