#include-once

; 原生控件翻译：Electron 菜单栏和 window.confirm 弹窗都不在 DOM 里，注入脚本碰不到；
; 只能改 asar 里的 main.js（菜单模板）和 renderer.js（confirm 消息字符串）。
; 只替换字符串常量，不碰任何逻辑。还原时优先用整包备份，这里只是备份丢失时的兜底。
;
; 表内容与顺序照抄 C# 版 StaticPatches.cs。主菜单的长串必须排在短串前面：
; 短串先替换会把长串里的片段吃掉，后半段就再也匹配不上了。

Global Const $SP_MAINJS = "dist/main/main.js"
Global Const $SP_RENDERERJS = "dist/renderer/renderer.js"

Global Const $SP_MAIN_MAP[30][2] = [ _
	['label:"Toggle &Full Screen"', 'label:"&全屏切换"'], _
	['label:"Toggle Full Screen"', 'label:"切换全屏"'], _
	['label:"&Close window"', 'label:"&关闭窗口"'], _
	['label:"About Pi Network"', 'label:"关于 Pi Network"'], _
	['label:"Hide Pi Network"', 'label:"隐藏 Pi Network"'], _
	['label:"Hide Others"', 'label:"隐藏其他"'], _
	['label:"Bring All to Front"', 'label:"全部置于顶层"'], _
	['label:"&File"', 'label:"&文件"'], _
	['label:"&View"', 'label:"&视图"'], _
	['label:"&Reload"', 'label:"&重新加载"'], _
	['label:"Select All"', 'label:"全选"'], _
	['label:"Learn More"', 'label:"了解更多"'], _
	['label:"White Paper"', 'label:"白皮书"'], _
	['label:"Inspect element"', 'label:"检查元素"'], _
	['label:"Show All"', 'label:"显示全部"'], _
	['label:"Services"', 'label:"服务"'], _
	['label:"Minimize"', 'label:"最小化"'], _
	['label:"Window"', 'label:"窗口"'], _
	['label:"Help"', 'label:"帮助"'], _
	['label:"Exit"', 'label:"退出"'], _
	['label:"Quit"', 'label:"退出"'], _
	['label:"Edit"', 'label:"编辑"'], _
	['label:"Undo"', 'label:"撤销"'], _
	['label:"Redo"', 'label:"重做"'], _
	['label:"Cut"', 'label:"剪切"'], _
	['label:"Copy"', 'label:"复制"'], _
	['label:"Paste"', 'label:"粘贴"'], _
	['label:"Close"', 'label:"关闭"'], _
	['label:"View"', 'label:"视图"'], _
	['label:"Open"', 'label:"打开"'] _
]

Global Const $SP_RENDERER_MAP[8][2] = [ _
	['You are in the middle of the catching up process, which will take some time.', _
		'你正处于追赶区块的过程中，这会需要一些时间。'], _
	['If you stop or interrupt the process midway, it will cause the process to restart from the beginning  when you turn on the node again.', _
		'如果在过程中停止或中断，重新打开节点时进程会从头开始。'], _
	['Do you want to stop?', '要停止吗？'], _
	['Do you really want to remove all blockchain data?', '你确实要删除所有区块链数据吗？'], _
	['It may take a while for you to restore your local blockchain data.', _
		'恢复本地区块链数据可能需要一段时间。'], _
	['Migration is required to run the Horizon blockchain API. This process cannot be interrupted and may take time.', _
		'运行 Horizon 区块链 API 需要先迁移。此过程不能被中断，可能需要一些时间。'], _
	['Do you want to start now? You will be redirected to the Troubleshooting page.', _
		'要现在开始吗？你将被转到疑难解答页面。'], _
	['Do you want to proceed with the Stellar Horizon migration? This process may take up to 15 minutes. Do not turn off your computer or Docker during this time, as it may result in data loss.', _
		'要继续进行 Stellar Horizon 迁移吗？此过程最多需要 15 分钟。在此期间请勿关闭计算机或 Docker，否则可能导致数据丢失。'] _
]

Func SP_ApplyMain($sText)
	Return _SP_Apply($sText, $SP_MAIN_MAP)
EndFunc

Func SP_RevertMain($sText)
	Return _SP_Revert($sText, $SP_MAIN_MAP)
EndFunc

Func SP_ApplyRenderer($sText)
	Return _SP_Apply($sText, $SP_RENDERER_MAP)
EndFunc

Func SP_RevertRenderer($sText)
	Return _SP_Revert($sText, $SP_RENDERER_MAP)
EndFunc

Func SP_HasAny($sText, $sWhich)
	Switch StringLower($sWhich)
		Case "main"
			Return _SP_HasAny($sText, $SP_MAIN_MAP)
		Case "renderer"
			Return _SP_HasAny($sText, $SP_RENDERER_MAP)
	EndSwitch
	Return SetError(1, 0, False)
EndFunc

; C# 用 StringComparison.Ordinal：区分大小写。AU3 的 StringReplace/StringInStr 默认是
; 不区分大小写的，第 5 / 3 个参数必须显式传 1，否则 label:"Open" 会连带命中 label:"open"。
Func _SP_Apply($sText, $aMap)
	Local $i
	For $i = 0 To UBound($aMap) - 1
		$sText = StringReplace($sText, $aMap[$i][0], $aMap[$i][1], 0, 1)
	Next
	Return $sText
EndFunc

; 逆序撤消：正向是依次全局替换，反向也必须从最后一条往回撤，否则链式改写无法还原
Func _SP_Revert($sText, $aMap)
	Local $i
	For $i = UBound($aMap) - 1 To 0 Step -1
		$sText = StringReplace($sText, $aMap[$i][1], $aMap[$i][0], 0, 1)
	Next
	Return $sText
EndFunc

Func _SP_HasAny($sText, $aMap)
	Local $i
	For $i = 0 To UBound($aMap) - 1
		If StringInStr($sText, $aMap[$i][1], 0, 1) > 0 Then Return True
	Next
	Return False
EndFunc
