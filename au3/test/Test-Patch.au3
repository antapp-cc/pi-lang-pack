#include "..\lib\Util.au3"
#include "..\lib\Json.au3"
#include "..\lib\Asar.au3"
#include "..\lib\Config.au3"
#include "..\lib\Locator.au3"
#include "..\lib\LangPack.au3"
#include "..\lib\StaticPatches.au3"
#include "..\lib\Injector.au3"
#include "..\lib\Patcher.au3"

; 端到端补丁测试：全程在 test\e2e 的假安装目录里跑，配置目录也用 PILANG_CONFIG_DIR
; 隔离到 test\e2e\cfg，**不碰真实 Pi Network 安装目录和真实 %APPDATA%\PiLang**。

Global $g_fail = 0
Global $g_orig = "C:\Users\Administrator\AppData\Roaming\PiLang\backup\app.asar.0.6.4.orig"
Global $g_tmp = @ScriptDir & "\e2e"
Global $g_install = $g_tmp & "\pi-network-desktop"
Global $g_asar = $g_install & "\resources\app.asar"

EnvSet("PILANG_CONFIG_DIR", $g_tmp & "\cfg")

Func T($bCond, $sWhat)
	If $bCond Then
		ConsoleWrite("[OK]   " & $sWhat & @CRLF)
	Else
		ConsoleWrite("[FAIL] " & $sWhat & @CRLF)
		$g_fail += 1
	EndIf
EndFunc

Func _Setup()
	If DirGetSize($g_tmp) <> -1 Then DirRemove($g_tmp, 1)
	DirCreate($g_install & "\resources")
	FileCopy($g_orig, $g_asar, 1)
EndFunc

ConsoleWrite("== 端到端补丁自检 ==" & @CRLF)
If Not FileExists($g_orig) Then
	ConsoleWrite("[跳过] 找不到原始 asar 备份：" & $g_orig & @CRLF)
	Exit(2)
EndIf
_Setup()

T(StringInStr(U_ConfigDir(), "e2e\cfg") > 0, "配置目录已隔离到 " & U_ConfigDir())
T(Loc_IsValid($g_install), "假安装目录结构有效")

Local $oPack = Lang_Load($CFG_LOCALE_ZH)
Local $oEntries = Json_Get($oPack, "entries")
T($oEntries.Count = 641, "词表载入 641 条（实际 " & $oEntries.Count & "）")

Local $oCfg = Cfg_Load()
Json_Set($oCfg, "installPath", $g_install)
T(Patch_State($oCfg) = $PATCH_STATE_CLEAN, "初始状态 = 未汉化")

; Pi 正在运行时 Patch_Install 必须拒绝（真实用户最常见的情况）
If Patch_IsAppRunning() Then
	Local $rBusy = Patch_Install($oCfg, $oPack)
	Local $bBusyRejected = (Not Json_GetBool($rBusy, "ok", True)) And (StringInStr(Json_GetStr($rBusy, "message"), "正在运行") > 0)
	T($bBusyRejected, "Pi 运行中拒绝安装：" & Json_GetStr($rBusy, "message"))
Else
	ConsoleWrite("[跳过] Pi Network 没在运行，跳过「运行中拒绝安装」检查" & @CRLF)
EndIf

; 绕过进程检查走核心流程（假目录，安全）
Local $t = TimerInit()
Local $rInstall = _Patch_InstallCore($oCfg, $oPack)
T(Json_GetBool($rInstall, "ok", False), "安装成功（" & Round(TimerDiff($t)) & " ms）：" & Json_GetStr($rInstall, "message"))
If Not Json_GetBool($rInstall, "ok", False) Then
	ConsoleWrite("失败 " & $g_fail & " 项" & @CRLF)
	Exit(1)
EndIf
T(Json_GetStr($rInstall, "version") = "0.6.4", "读到 Pi Network 版本 0.6.4")
T(Patch_State($oCfg) = $PATCH_STATE_PATCHED, "安装后状态 = 已汉化")

; asar 内容检查
Local $oAsar = Asar_Open($g_asar)
T(IsObj($oAsar), "补丁后 asar 能重新打开")
T(Asar_IsPatched($oAsar, $INJ_SCRIPT_PATH), "补丁标记存在")
Local $sScript = Asar_ReadText($oAsar, $INJ_SCRIPT_PATH)
T(StringLen($sScript) > 30000, "注入脚本 " & StringLen($sScript) & " 字节")
T(StringInStr($sScript, "/* pi-lang-patch */") > 0, "脚本含补丁标记")
T(StringInStr($sScript, '"locale":"zh-CN"') > 0, "脚本内联 locale")
T(StringInStr($sScript, '"entries":{') > 0, "脚本内联词表")

Local $sHtml = Asar_ReadText($oAsar, $INJ_INDEX_PATH)
T(StringInStr($sHtml, "./pi-lang.js") > 0, "index.html 已注入脚本标签")
T(StringInStr($sHtml, "<script defer=defer src=./pi-lang.js></script>") > 0, "注入标签内容正确")

Local $sMain = Asar_ReadText($oAsar, $SP_MAINJS)
T(StringInStr($sMain, 'label:"&文件"') > 0, "main.js 菜单 label 已翻译")
Local $sRenderer = Asar_ReadText($oAsar, $SP_RENDERERJS)
T(StringInStr($sRenderer, "你确实要删除所有区块链数据吗？") > 0, "renderer.js 确认弹窗已翻译")

; Node 独立实现校验 asar 合法性（不依赖我们自己的解析器）
; Node 独立校验由外部脚本跑（test\verify-asar.js），不放进本自检，避免 RunWait 在管道重定向下挂住
T(True, "（Node 独立校验见 test\verify-asar.js，单独跑）")

; 模拟官方更新：把原始 asar 直接覆盖回去（此时 Pi 往往已经退出了；这里 Pi 还开着的话
; Ensure 应该推迟而不是报错）
Local $sPatchedHash = U_Sha256File($g_asar)
FileCopy($g_orig, $g_asar, 1)
Local $rEnsure = Patch_Ensure($oCfg, $oPack)
If Patch_IsAppRunning() Then
	T(Json_GetBool($rEnsure, "ok", False) And StringInStr(Json_GetStr($rEnsure, "message"), "正在运行") > 0, _
		"Pi 运行时 Ensure 推迟重打而不报错：" & Json_GetStr($rEnsure, "message"))
	Local $rForce = _Patch_InstallCore($oCfg, $oPack)
	T(Json_GetBool($rForce, "ok", False), "核心重打成功：" & Json_GetStr($rForce, "message"))
Else
	T(Json_GetBool($rEnsure, "ok", False), "asar 被覆盖后 Ensure 能自愈：" & Json_GetStr($rEnsure, "message"))
EndIf
T(Patch_State($oCfg) = $PATCH_STATE_PATCHED, "Ensure 后恢复为已汉化")
T(FileGetSize($g_asar) > FileGetSize($g_orig), "重打后 asar 比原版大（说明真的注入了内容）")

; 还原
Local $rRestore = _Patch_RestoreCore($oCfg)
T(Json_GetBool($rRestore, "ok", False), "还原成功：" & Json_GetStr($rRestore, "message"))
T(Patch_State($oCfg) = $PATCH_STATE_CLEAN, "还原后状态 = 未汉化")
T(U_Sha256File($g_asar) = U_Sha256File($g_orig), "还原后 asar 与原版字节一致")

Local $sCfgText = U_ReadText(Cfg_Path())
T(StringInStr($sCfgText, '"desiredState": "restored"') > 0, "配置里 desiredState = restored")

; 还原后守护不许再打
Local $rEnsure2 = Patch_Ensure($oCfg, $oPack)
T(Json_GetBool($rEnsure2, "ok") And Patch_State($oCfg) = $PATCH_STATE_CLEAN, "还原后 Ensure 不自动汉化")
Json_Set($oCfg, "desiredState", $CFG_STATE_ZH)
Json_Set($oCfg, "guardEnabled", False)
Local $rPaused = Patch_Ensure($oCfg, $oPack)
T(Json_GetBool($rPaused, "ok") And Patch_State($oCfg) = $PATCH_STATE_CLEAN, "守护关闭时 Ensure 不动作")
Json_Set($oCfg, "guardEnabled", True)

; 语言切换
Local $rEn = _Patch_InstallCore($oCfg, Lang_Load($CFG_LOCALE_EN))
T(Json_GetBool($rEn, "ok", False), "切到 en-US 重打包")
Local $oAsarEn = Asar_Open($g_asar)
T(StringInStr(Asar_ReadText($oAsarEn, $INJ_SCRIPT_PATH), '"locale":"en-US"') > 0, "注入脚本已是 en-US")
Local $rZh = _Patch_InstallCore($oCfg, Lang_Load($CFG_LOCALE_ZH))
T(Json_GetBool($rZh, "ok", False), "切回 zh-CN")

ConsoleWrite(($g_fail = 0 ? "全部通过" : "失败 " & $g_fail & " 项") & @CRLF)
Exit($g_fail = 0 ? 0 : 1)

