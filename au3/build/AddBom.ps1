# 给所有 .au3 源文件加 UTF-8 BOM（AutoIt 靠 BOM 判断源文件编码，中文才不会按 ANSI 解）
# 幂等：已有 BOM 就跳过。构建前跑一次。

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$files = Get-ChildItem -Path $root -Filter *.au3 -Recurse -File
$enc = New-Object System.Text.UTF8Encoding($true)
$changed = 0
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) { continue }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    [System.IO.File]::WriteAllText($f.FullName, $text, $enc)
    $changed++
}
"BOM added: $changed / $($files.Count) files"
