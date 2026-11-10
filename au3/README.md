# Pi 多语言包 · AutoIt3 版

给 **Pi Node 桌面版（Pi Network Desktop）** 装界面中文的独立托盘小工具。
这是 `..\Pi多语言包`（C# .NET 10 版）的完整 AutoIt3 重写，功能一一对应，
配置目录共用（`%APPDATA%\PiLang`），产物从 50MB 降到 1.4MB，不需要任何运行时。

## 产物

- `dist\Pi多语言包-AU3.exe` —— x64，1.4MB，图标与版本资源已嵌入，双击即用
- `dist\发布\` —— 发布物：`PiLang-AU3.exe` + `zh-CN.json` + `latest.json`
  （`build\release.ps1` 生成，直接传 GitHub Release 即可）
- `使用说明.txt` —— 给最终用户看的说明

## 在线更新

更新源是 GitHub 上的清单，不自建服务器：

```
https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json
```

- 直连不通时自动换 jsDelivr 镜像（`cdn.jsdelivr.net/gh/antapp-cc/pi-lang-pack@main/...`）再试；
  这台机器实测：没开代理时 raw 和镜像都超时，开了代理 0.9 秒拉到清单。
- 清单 `app.version` 不比本机新就不下载。AU3 版版本号与 GitHub 上现有的 C# 版保持一致
  （**1.0.11**），两个实现在更新系统里等价，谁也不会把谁替换掉。实测：清单 1.0.11 →
  本机 1.0.11 → 输出「已是最新版本」，一个字节都不下载。
- **以后发新版必须把版本号 +1**（`lib\Updater.au3` 的 `$UPD_APP_VERSION`、`build\release.ps1`
  的 `-Version`）：更新只比版本号，不比内容哈希，同版本号重新发内容老用户拿不到。
- 发布流程：`pwsh -NoProfile -File build\release.ps1` → 把 `dist\发布\PiLang-AU3.exe`
  传 GitHub Release `v1.0.11` → 用生成的 `latest.json` 覆盖仓库 `server/latest.json`。
- 手动检查更新会弹进度小窗（`lib\UpdateForm.au3`）；自动检查只写日志和托盘提示。
- 演练模式：环境变量 `PILANG_DRY_RUN=1` 或 `$UPD_DRY_RUN=True` 时，下载和批处理照做，
  但不启动自替换（测试用，别在正式使用里设）。

## 目录

```
PiLang.au3                主入口（无参数=托盘，有参数=CLI）
lib\Util.au3              路径、UTF-8 读写、日志、SHA256、进程检测
lib\Json.au3              JSON 解析/序列化（对象=Scripting.Dictionary，数组=AU3 数组）
lib\Asar.au3              asar 读写：解析 header、重建、integrity、原子替换
lib\Config.au3            config.json（字段名与 C# 版一致）
lib\Locator.au3           找安装目录（配置 → 卸载注册表 → 默认路径）
lib\LangPack.au3          词表加载（内置打底 + 外部覆盖/并集/追加）
lib\StaticPatches.au3     原生菜单 30 条 + 确认弹窗 8 条 字符串替换
lib\Injector.au3          生成注入脚本、改 index.html
lib\Patcher.au3           安装/还原/状态机/备份/跨进程互斥
lib\Tray.au3              托盘菜单、2 秒守护、自动更新检查、开机自启
lib\Updater.au3           在线更新（清单/镜像/下载/SHA256/自替换批处理）
lib\SelfTest.au3          --selftest：词表、脚本、注入、替换、asar 往返
res\                      词表种子、注入脚本模板、图标（编译后由 FileInstall 释放）
test\                     各模块自检脚本
build\AddBom.ps1          给所有 .au3 加 UTF-8 BOM（AutoIt 靠 BOM 判断源文件编码）
build\build.ps1           Au3Check 预检 → Aut2Exe x64 编译 → 写版本资源
docs\CONTRACT.md          模块接口契约（并行开发时定的，改接口前先看）
```

## 构建

```powershell
cd C:\Users\Administrator\Desktop\Pi多语言包-AU3
pwsh -NoProfile -File build\build.ps1
```

需要 AutoIt v3.3.18（`C:\Program Files (x86)\AutoIt3`）。脚本会先跑 Au3Check，
有语法错误直接失败（Aut2Exe 遇到语法错误会弹框卡死，所以预检是必须的）。

## 自检

```powershell
# 内置自检（不碰正式安装目录，asar 往返用备份文件）
.\dist\Pi多语言包-AU3.exe --selftest

# 各模块
AutoIt3.exe /ErrorStdOut test\Test-Asar.au3
AutoIt3.exe /ErrorStdOut test\Test-Inject.au3
AutoIt3.exe /ErrorStdOut test\Test-Patch.au3    # 端到端：假安装目录里装/还原/自愈
AutoIt3.exe /ErrorStdOut test\Test-Tray.au3
AutoIt3.exe /ErrorStdOut test\Test-Update.au3

# 独立参照实现校验 asar 合法性（Node 按 Electron 的读法解析并核对 integrity）
node test\verify-asar.js <app.asar>
```

测试脚本用 `PILANG_CONFIG_DIR` 把配置隔离到临时目录，不会污染真实的 `%APPDATA%\PiLang`。

## 命令行

```
--status                 安装目录、汉化状态、期望状态、词表条数
--install / --restore    安装 / 还原
--ensure                 守护用的幂等入口（按 desiredState 决定）
--lang zh-CN|en-US       切语言
--update                 检查在线更新
--selftest               自检
--dir <安装目录>          临时指定目录（验证副本、排障）
```

## 实现要点

- **asar 重打包**：保持原文件在数据区里的先后顺序，只改被替换文件的内容与全表 offset，
  新增文件追加末尾；未改动文件的 integrity 原样复用，不必重算全部哈希。
  重打包是确定性的：同一输入两次输出字节一致。
- **补丁态快速判定**：先在 header 原文里搜条目名（`Asar_Open($path, False)` 不解析 JSON 树），
  托盘菜单打开时才不会卡半秒。
- **状态机**：`desiredState` = `zh` / `restored` / `paused`，配 `appliedAsarHash` 识别
  "官方更新覆盖了 asar"。保证"永远中文"与"可还原"不打架。
- **进程检查在对外入口**：`Patch_Install` / `Patch_Restore` 检查 Pi 是否在运行，
  内部的 `*_Core` 是纯逻辑，自检可以直接调用。
- **跨进程互斥**：`Local\pi-lang-asar-write` 命名 Mutex，托盘守护和 CLI 不会同时写 asar。
- **资源随 exe 走**：Aut2Exe 命令行不能嵌文件，用 `FileInstall` 在启动时释放到
  `%APPDATA%\PiLang\res\`。
- **原生控件翻译**：菜单栏和 `window.confirm` 不在 DOM 里，只能替换 asar 内
  `main.js` / `renderer.js` 的字符串常量；还原时优先用整包备份恢复。

## 已知限制

- 不像 Pi 应用内嵌的 webview 内容、服务端通知正文、日志/报错堆栈。
- 官方改版后 `index.html` 结构变了会拒绝安装并保留原文件（不会写坏）。
- AutoIt 编译产物比 .NET 更容易被杀软误报（行为本身是"改别的软件的安装目录"）。
- 与 C# 版共用一个托盘互斥名，两个版本不能同时常驻。
