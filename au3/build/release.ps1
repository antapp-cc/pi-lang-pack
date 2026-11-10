# 生成发布物：exe + 词表 + 在线更新清单（latest.json）。
#
# 更新源用 GitHub raw，不自建服务器：
#   https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json
# 发布时把本脚本产出的 latest.json 覆盖仓库里的 server/latest.json，
# exe 传到同一 tag 的 GitHub Release，URL 对得上就行。
#
# 用法：
#   pwsh -NoProfile -File build\release.ps1
#   pwsh -NoProfile -File build\release.ps1 -Tag v1.1.0 -OutDir dist\发布

[CmdletBinding()]
param(
    [string]$Tag = 'v1.0.11',
    [string]$Version = '1.0.11',
    [string]$Repo = 'antapp-cc/pi-lang-pack',
    [string]$OutDir = ''
)

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

if (-not $OutDir) { $OutDir = Join-Path $root 'dist\发布' }
# 发布用的文件名保持 ASCII：GitHub Release 下载 URL 里带中文要百分号编码，
# InetGet 对编码后的中文名容易踩坑，程序名（版本资源里的"Pi 多语言包"）不受影响
$exeName = 'PiLang-AU3.exe'

Write-Host '=== 1/4 编译 ==='
& (Join-Path $root 'build\build.ps1')
if ($LASTEXITCODE -ne 0) { throw "编译失败（exit $LASTEXITCODE）" }

$exePath = Join-Path $root "dist\Pi多语言包-AU3.exe"
$langPath = Join-Path $root 'res\zh-CN.json'
foreach ($f in @($exePath, $langPath)) {
    if (-not (Test-Path $f)) { throw "缺少发布文件：$f" }
}

Write-Host '=== 2/4 复制到发布目录 ==='
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $exePath (Join-Path $OutDir $exeName) -Force
Copy-Item $langPath (Join-Path $OutDir 'zh-CN.json') -Force

Write-Host '=== 3/4 计算 SHA256 ==='
$exeSha = (Get-FileHash (Join-Path $OutDir $exeName) -Algorithm SHA256).Hash.ToLower()
$langSha = (Get-FileHash (Join-Path $OutDir 'zh-CN.json') -Algorithm SHA256).Hash.ToLower()
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

# 字段名与 C# 版清单一致：Updater 按 app/lang 读，version 决定更不更新
$manifest = [ordered]@{
    lang = [ordered]@{
        url       = "https://raw.githubusercontent.com/$Repo/main/server/zh-CN.json"
        sha256    = $langSha
        updatedAt = $now
        version   = '0.6.4'
    }
    app  = [ordered]@{
        url       = "https://github.com/$Repo/releases/download/$Tag/$exeName"
        sha256    = $exeSha
        updatedAt = $now
        version   = $Version
    }
}
$manifestPath = Join-Path $OutDir 'latest.json'
$manifest | ConvertTo-Json -Depth 4 | Set-Content $manifestPath -Encoding utf8NoBOM

Write-Host '=== 4/4 完成 ==='
Write-Host "发布目录：$OutDir"
Write-Host "  $exeName  $((Get-Item (Join-Path $OutDir $exeName)).Length) 字节"
Write-Host "  latest.json  app.version=$Version  tag=$Tag"
Write-Host ''
Write-Host '要上线的话：'
Write-Host "  1) 把 exe 传到 GitHub Release $Tag"
Write-Host "  2) 把 $manifestPath 覆盖仓库 server/latest.json"
Write-Host "  3) 把 res\zh-CN.json 覆盖仓库 server/zh-CN.json（词表变了才需要）"


