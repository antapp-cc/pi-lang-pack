#include-once

; 配置读写。字段名与 C# 版 config.json 完全一致（camelCase），已有的用户配置能直接续用。

Global Const $CFG_LOCALE_ZH = "zh-CN"
Global Const $CFG_LOCALE_EN = "en-US"
Global Const $CFG_STATE_ZH = "zh"
Global Const $CFG_STATE_RESTORED = "restored"
Global Const $CFG_STATE_PAUSED = "paused"

Func Cfg_Default()
	Local $o = Json_NewObject()
	$o.Item("installPath") = ""
	$o.Item("locale") = $CFG_LOCALE_ZH
	$o.Item("desiredState") = $CFG_STATE_ZH
	$o.Item("guardEnabled") = True
	$o.Item("appliedAsarHash") = ""
	$o.Item("lastPatchVersion") = ""
	$o.Item("autoStart") = False
	; 更新源必须是 GitHub 上的清单（用户要求，不自建服务器）。
	; 清单里 app.url 指向发布包的 exe，AU3 版按版本号判断要不要更新；版本号与 C# 版
	; 对齐在 1.0.11，所以两边在更新系统里等价，不会互相替换。
	$o.Item("updateUrl") = "https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json"
	$o.Item("autoUpdate") = True
	$o.Item("lastUpdateCheck") = ""
	$o.Item("pendingRepatch") = False
	$o.Item("lastLangUpdatedAt") = ""
	Return $o
EndFunc

Func Cfg_Path()
	Return U_ConfigDir() & "\config.json"
EndFunc

; 读不到/读坏了都返回默认值：守护不能因为一个坏配置就停摆
Func Cfg_Load()
	Local $o = Cfg_Default()
	Local $sPath = Cfg_Path()
	If Not FileExists($sPath) Then Return $o
	Local $s = U_ReadText($sPath)
	If @error Or $s = "" Then Return $o
	Local $oParsed = Json_Parse($s)
	If Not IsObj($oParsed) Then Return $o

	Local $aKeys = $oParsed.Keys()
	Local $i
	For $i = 0 To UBound($aKeys) - 1
		Local $sKey = $aKeys[$i]
		If $o.Exists($sKey) Then $o.Item($sKey) = $oParsed.Item($sKey)
	Next
	Return $o
EndFunc

Func Cfg_Save($o)
	U_EnsureDir(U_ConfigDir())
	U_WriteText(Cfg_Path(), Json_Stringify($o, True) & @CRLF)
	Return @error = 0
EndFunc

; 守护每 2 秒重读配置，用这个取"用户是否刚点了还原"等状态
Func Cfg_GetStr($o, $sKey, $sDefault = "")
	Return Json_GetStr($o, $sKey, $sDefault)
EndFunc
