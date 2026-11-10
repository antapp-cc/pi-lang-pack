#include-once
#include <File.au3>
#include <Date.au3>
#include <Crypt.au3>

; 所有模块共用：路径、编码、日志、SHA256、进程检测。

Func U_ConfigDir()
	Local $custom = EnvGet("PILANG_CONFIG_DIR")
	If $custom <> "" Then Return $custom
	Return @AppDataDir & "\PiLang"
EndFunc

Func U_LangDir()
	Return U_ConfigDir() & "\langs"
EndFunc

Func U_BackupDir()
	Return U_ConfigDir() & "\backup"
EndFunc

Func U_UpdateDir()
	Return U_ConfigDir() & "\update"
EndFunc

; 运行期资源目录：FileInstall 释放出来的模板/词表种子放这里，和用户可改的 langs 分开
Func U_ResourceDir()
	Return U_ConfigDir() & "\res"
EndFunc

Func U_LogPath()
	Return U_ConfigDir() & "\PiLang.log"
EndFunc

Func U_EnsureDir($sDir)
	If $sDir = "" Then Return False
	If DirGetSize($sDir) <> -1 Then Return True
	DirCreate($sDir)
	Return DirGetSize($sDir) <> -1
EndFunc

Func U_Log($sMessage)
	_U_EnsureDirNoLog()
	Local $h = FileOpen(U_LogPath(), $FO_APPEND + $FO_CREATEPATH + $FO_UTF8_NOBOM)
	If $h = -1 Then Return
	; 固定 ISO 形状的时间戳：_NowCalc 跟着系统区域设置走，中文系统会写成 2026/11/10
	FileWrite($h, StringFormat("[%04d-%02d-%02d %02d:%02d:%02d] %s%s", _
			@YEAR, @MON, @MDAY, @HOUR, @MIN, @SEC, $sMessage, @CRLF))
	FileClose($h)
EndFunc

; U_EnsureDir 在被 U_Log 调用链里会递归写日志，这里单独绕开
Func _U_EnsureDirNoLog()
	Local $sDir = U_ConfigDir()
	If DirGetSize($sDir) = -1 Then DirCreate($sDir)
EndFunc

; 读文本：先二进制读再判断 BOM，避免无 BOM 的 UTF-8 被按 ANSI 解码
Func U_ReadText($sPath)
	Local $b = U_ReadBinary($sPath)
	If @error Then Return SetError(1, 0, "")
	If BinaryMid($b, 1, 3) = 0xEFBBBF Then $b = BinaryMid($b, 4)
	Return BinaryToString($b, 4)
EndFunc

Func U_WriteText($sPath, $sText)
	Local $sDir = _U_DirName($sPath)
	If $sDir <> "" Then U_EnsureDir($sDir)
	Local $h = FileOpen($sPath, $FO_OVERWRITE + $FO_CREATEPATH + $FO_UTF8_NOBOM)
	If $h = -1 Then Return SetError(1, 0, False)
	FileWrite($h, $sText)
	FileClose($h)
	Return True
EndFunc

Func U_ReadBinary($sPath)
	Local $h = FileOpen($sPath, $FO_READ + $FO_BINARY)
	If $h = -1 Then Return SetError(1, 0, Binary(""))
	Local $b = FileRead($h, FileGetSize($sPath))
	FileClose($h)
	If @error Then Return SetError(2, 0, Binary(""))
	Return $b
EndFunc

Func U_WriteBinary($sPath, $bData)
	Local $sDir = _U_DirName($sPath)
	If $sDir <> "" Then U_EnsureDir($sDir)
	Local $h = FileOpen($sPath, $FO_OVERWRITE + $FO_CREATEPATH + $FO_BINARY)
	If $h = -1 Then Return SetError(1, 0, False)
	FileWrite($h, $bData)
	FileClose($h)
	Return True
EndFunc

Func U_AppendBinary($hFile, $bData)
	FileWrite($hFile, $bData)
EndFunc

Func _U_DirName($sPath)
	Local $i = StringInStr($sPath, "\", 0, -1)
	If $i <= 1 Then Return ""
	Return StringLeft($sPath, $i - 1)
EndFunc

; SHA256 十六进制小写，与 C# Convert.ToHexString 输出对齐
Func U_Sha256Hex($vData)
	Local $b = _Crypt_HashData($vData, $CALG_SHA_256)
	If @error Then Return SetError(1, 0, "")
	Return _U_BinToHexLower($b)
EndFunc

Func U_Sha256File($sPath)
	Local $b = U_ReadBinary($sPath)
	If @error Then Return SetError(1, 0, "")
	Return U_Sha256Hex($b)
EndFunc

Func _U_BinToHexLower($bData)
	Local $iLen = BinaryLen($bData), $sOut = "", $i
	Local $aHex[256]
	For $i = 0 To 255
		$aHex[$i] = Hex($i, 2) ; Hex 对整数补零，避免逐字节拼接字符串时大小写混乱
	Next
	For $i = 1 To $iLen
		$sOut &= $aHex[Number(BinaryMid($bData, $i, 1))]
	Next
	Return StringLower($sOut)
EndFunc

Func U_FileSize($sPath)
	Return FileGetSize($sPath)
EndFunc

Func U_FileTicks($sPath)
	Return FileGetTime($sPath, 1) & FileGetTime($sPath, 0) & FileGetTime($sPath, 2)
EndFunc

Func U_ProcessRunning($sExeName)
	Return ProcessExists($sExeName) <> 0
EndFunc

Func U_ShellOpen($sPath)
	Run(@ComSpec & ' /c start "" "' & $sPath & '"', "", @SW_HIDE)
EndFunc

Func U_ShellOpenDir($sDir)
	U_EnsureDir($sDir)
	Run("explorer.exe " & '"' & $sDir & '"')
EndFunc
