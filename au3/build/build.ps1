# 编译 dist\Pi多语言包-AU3.exe（x64）。
# Aut2Exe 命令行不能嵌入文件资源和版本信息：文件资源靠 PiLang.au3 里的 FileInstall
# 运行期释放，版本信息在编译后用 Win32 UpdateResource 写进 PE。

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$aut2exe = 'C:\Program Files (x86)\AutoIt3\Aut2Exe\Aut2exe_x64.exe'
$au3check = 'C:\Program Files (x86)\AutoIt3\Au3Check.exe'
$main = Join-Path $root 'PiLang.au3'
$icon = Join-Path $root 'res\antnest.ico'
$dist = Join-Path $root 'dist'
$output = Join-Path $dist 'Pi多语言包-AU3.exe'

# Au3Check/Aut2Exe 拿到含中文的绝对路径时找不到 #include 的兄弟文件（实测），
# 所以后面统一在工作目录下用相对路径调用它们。
Set-Location $root

# ---- 版本资源构造 ----
# VS_VERSIONINFO 是 UTF-16 编码的树：root(VS_FIXEDFILEINFO) -> StringFileInfo/VarFileInfo。
# wLength 必须回填整棵节点长度，长度不够会被资源管理器当成损坏。

function Get-Utf16([string]$s) {
    # 返回不带结尾的 UTF-16 字节
    return ,([System.Text.Encoding]::Unicode.GetBytes($s))
}

function Get-U16([int]$v) {
    return ,([byte[]]@(($v -band 0xFF), (($v -shr 8) -band 0xFF)))
}

function Get-U32([uint32]$v) {
    return ,([byte[]]@(($v -band 0xFF), (($v -shr 8) -band 0xFF), (($v -shr 16) -band 0xFF), (($v -shr 24) -band 0xFF)))
}

function Add-Pad4($list) {
    while ($list.Count % 4 -ne 0) { $list.Add([byte]0) }
}

function New-VersionNode {
    param(
        [string]$Key,
        [byte[]]$Value = @(),
        [int]$ValueLength = 0,
        [int]$NodeType = 1,
        [byte[]]$Children = @()
    )
    $b = New-Object 'System.Collections.Generic.List[byte]'
    $b.AddRange((Get-U16 0))                # wLength 先占位，最后回填
    $b.AddRange((Get-U16 $ValueLength))
    $b.AddRange((Get-U16 $NodeType))
    $b.AddRange((Get-Utf16 $Key))
    $b.AddRange((Get-U16 0))                # key 以 NUL 结尾
    Add-Pad4 $b
    if ($Value.Length -gt 0) { $b.AddRange($Value) }
    Add-Pad4 $b
    if ($Children.Length -gt 0) { $b.AddRange($Children) }
    $len = $b.Count
    $b[0] = [byte]($len -band 0xFF)
    $b[1] = [byte](($len -shr 8) -band 0xFF)
    return ,$b.ToArray()
}

function Set-ExeVersionInfo {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ProductName = 'Pi 多语言包',
        [string]$FileDescription = 'Pi 多语言包',
        [string]$CompanyName = '蚁巢',
        [string]$FileVersion = '1.0.11.0',
        [string]$ProductVersion = '1.0.11.0',
        [string]$OriginalFilename = 'Pi多语言包-AU3.exe',
        [string]$InternalName = 'PiLang'
    )
    $ver = [version]$FileVersion
    $prod = [version]$ProductVersion

    $fixed = New-Object 'System.Collections.Generic.List[byte]'
    $signature = [Convert]::ToUInt32('FEEF04BD', 16)
    foreach ($dw in @(
            $signature, 0x00010000,
            ([uint32](($ver.Major -shl 16) -bor $ver.Minor)),
            ([uint32](($ver.Build -shl 16) -bor $ver.Revision)),
            ([uint32](($prod.Major -shl 16) -bor $prod.Minor)),
            ([uint32](($prod.Build -shl 16) -bor $prod.Revision)),
            0x3F,           # dwFileFlagsMask
            0,              # dwFileFlags
            0x00040004,     # dwFileOS: VOS_NT_WINDOWS32
            1,              # dwFileType: VFT_APP
            0,              # dwFileSubtype
            0, 0)) {        # dwFileDate
        $fixed.AddRange((Get-U32 $dw))
    }

    # LegalCopyright 故意不写：原版 PiLang.exe 的版权字段就是空的（csproj 里也没有 Copyright）
    $strings = [ordered]@{
        'CompanyName'      = $CompanyName
        'FileDescription'  = $FileDescription
        'FileVersion'      = $FileVersion
        'InternalName'     = $InternalName
        'OriginalFilename' = $OriginalFilename
        'ProductName'      = $ProductName
        'ProductVersion'   = $ProductVersion
    }
    $stringNodes = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($key in $strings.Keys) {
        $value = $strings[$key]
        $valueBytes = [byte[]]((Get-Utf16 $value) + [byte[]]@(0, 0))
        $stringNodes.AddRange((New-VersionNode -Key $key -Value $valueBytes -ValueLength ($value.Length + 1) -NodeType 1))
    }
    $stringTable = New-VersionNode -Key '040904B0' -NodeType 1 -Children $stringNodes.ToArray()
    $stringFileInfo = New-VersionNode -Key 'StringFileInfo' -NodeType 1 -Children $stringTable
    $translation = New-VersionNode -Key 'Translation' -Value (Get-U32 0x04B00409) -ValueLength 4 -NodeType 0
    $varFileInfo = New-VersionNode -Key 'VarFileInfo' -NodeType 1 -Children $translation
    $rootNode = New-VersionNode -Key 'VS_VERSION_INFO' -Value $fixed.ToArray() -ValueLength 52 -NodeType 0 `
        -Children ([byte[]]($stringFileInfo + $varFileInfo))

    if (-not ('PiLangResWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PiLangResWriter {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr BeginUpdateResource(string fileName, bool deleteExistingResources);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, uint cbData);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool EndUpdateResource(IntPtr hUpdate, bool discard);
}
'@
    }

    $handle = [PiLangResWriter]::BeginUpdateResource($Path, $false)
    if ($handle -eq [IntPtr]::Zero) {
        throw "BeginUpdateResource 失败，错误码 $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    try {
        # RT_VERSION = 16，资源 ID = 1，语言与 StringTable 的 040904B0 对齐
        if (-not [PiLangResWriter]::UpdateResource($handle, [IntPtr]16, [IntPtr]1, [uint16]0x0409, $rootNode, [uint32]$rootNode.Length)) {
            throw "UpdateResource 失败，错误码 $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
    }
    catch {
        [void][PiLangResWriter]::EndUpdateResource($handle, $true)
        throw
    }
    if (-not [PiLangResWriter]::EndUpdateResource($handle, $false)) {
        throw "EndUpdateResource 失败，错误码 $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
}

# ---- 构建流程 ----

# 1. 源文件补 BOM（AutoIt 靠 BOM 判断 UTF-8，否则中文按 ANSI 解）
& (Join-Path $PSScriptRoot 'AddBom.ps1')

# 2. FileInstall 的源文件必须在编译时就位，缺一个编出来的 exe 就缺功能
foreach ($rel in @('res\antnest.ico', 'res\pi-lang.js.template', 'res\zh-CN.json')) {
    if (-not (Test-Path (Join-Path $root $rel))) {
        Write-Error "缺少资源文件 $rel，无法编译"
        exit 1
    }
}

# 3. 主脚本是并行开发的最后一块，还没写就明确跳过（不算编译失败）
if (-not (Test-Path $main)) {
    Write-Host "主脚本不存在，跳过编译：$main"
    exit 0
}
if (-not (Test-Path $aut2exe)) {
    Write-Error "找不到 Aut2Exe：$aut2exe"
    exit 1
}

# 4. 预检：Aut2Exe 碰到语法错误会弹模态框卡住，先用 Au3Check 拦住
& $au3check -w 2 'PiLang.au3' 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    Write-Error "Au3Check 未通过（退出码 $LASTEXITCODE），编译中止"
    exit 1
}

# 5. 编译
New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $output) { Remove-Item $output -Force }
$argLine = '/in "PiLang.au3" /out "dist\Pi多语言包-AU3.exe" /icon "res\antnest.ico" /comp 4'
$proc = Start-Process -FilePath $aut2exe -ArgumentList $argLine -PassThru -WorkingDirectory $root
if (-not $proc.WaitForExit(120000)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Write-Error "Aut2Exe 超时（120 秒未退出，可能在弹错误对话框）"
    exit 1
}
if ($proc.ExitCode -ne 0) {
    Write-Error "Aut2Exe 编译失败，退出码 $($proc.ExitCode)"
    exit 1
}
if (-not (Test-Path $output) -or (Get-Item $output).Length -le 0) {
    Write-Error "Aut2Exe 没有产出 exe：$output"
    exit 1
}

# 6. 版本信息（Aut2Exe 命令行不支持，只能编译后补）
try {
    Set-ExeVersionInfo -Path $output
}
catch {
    Write-Error "写入版本信息失败：$($_.Exception.Message)"
    exit 1
}
$info = (Get-Item $output).VersionInfo
if ($info.ProductName -ne 'Pi 多语言包' -or $info.FileVersion -ne '1.0.11.0') {
    Write-Error "版本信息校验失败（ProductName=$($info.ProductName), FileVersion=$($info.FileVersion)）"
    exit 1
}

Write-Host "编译完成：$output"
Write-Host ("  大小 {0} 字节，版本 {1}，产品 {2}" -f (Get-Item $output).Length, $info.FileVersion, $info.ProductName)

