# Pi 多语言包 · AU3 版模块契约

这份契约是并行开发的唯一依据。**函数签名、文件名、全局常量不许自行改动**；确实需要改，先告诉 Lead。

## 环境

- AutoIt **v3.3.18**，装在 `C:\Program Files (x86)\AutoIt3`。
- 语法检查：`& "C:\Program Files (x86)\AutoIt3\Au3Check.exe" -w 2 <脚本>`
- 运行脚本：`& "C:\Program Files (x86)\AutoIt3\AutoIt3.exe" /ErrorStdOut <脚本>`（`/ErrorStdOut` 必须有，否则语法错误会弹框卡住）
- 编译 x64：`Aut2Exe\Aut2exe_x64.exe`
- 项目根：`C:\Users\Administrator\Desktop\Pi多语言包-AU3`

## 硬性约定

1. **源文件 UTF-8 带 BOM**。写完文件后跑 `pwsh -NoProfile -File build\AddBom.ps1`（幂等），AU3 靠 BOM 判断编码，否则中文变乱码。
2. **每个 lib 只 include 标准库**（`<FileConstants.au3>`、`<Crypt.au3>` 之类），**不要 include 兄弟 lib**。include 顺序由主脚本/测试脚本控制。
3. 源文件里的中文直接写，不用转义。
4. 注释只写"为什么"（非显然的约束、踩过的坑），不复述代码。
5. 只改你负责的文件。别人的文件一行都别动；发现别处有 bug 就报告，别顺手改。

## 数据目录（与现有 C# 版共用，不能改路径和字段名）

```
%APPDATA%\PiLang\
  config.json       camelCase 字段：installPath, locale, desiredState, guardEnabled,
                    appliedAsarHash, lastPatchVersion, autoStart, updateUrl, autoUpdate,
                    lastUpdateCheck, pendingRepatch, lastLangUpdatedAt
  langs\zh-CN.json  词表（UTF-8 无 BOM）
  backup\           app.asar.<version>.orig
  res\              运行期释放的资源（pi-lang.js.template、zh-CN.json 种子）
  update\           在线更新下载目录
  PiLang.log        UTF-8 无 BOM，行格式 [yyyy-mm-dd hh:mm:ss] 消息
```

## 类型约定

- JSON 对象 = `Scripting.Dictionary`（`Json_NewObject()` 创建，BinaryCompare，保留插入顺序）
- JSON 数组 = AU3 一维数组，只能通过 `_Json_NewArray()` / `Json_ArrayPush` / `Json_ArrayLen` / `Json_ArrayGet` 操作
- 函数结果统一用 Dictionary：`{"ok": True/False, "message": "中文提示", ...}`
- 文本文件读写一律走 `U_ReadText` / `U_WriteText`（UTF-8 无 BOM）；二进制走 `U_ReadBinary` / `U_WriteBinary`

## 已完成、别改的模块

### lib\Util.au3
```
U_ConfigDir() U_LangDir() U_BackupDir() U_UpdateDir() U_LogPath() U_ResourceDir()
U_EnsureDir($dir) U_Log($msg)
U_ReadText($path) U_WriteText($path,$text) U_ReadBinary($path) U_WriteBinary($path,$data)
U_Sha256Hex($data) U_Sha256File($path) U_FileSize($path) U_FileTicks($path)
U_ProcessRunning($exeName) U_ShellOpen($path) U_ShellOpenDir($dir)
```

### lib\Json.au3
```
Json_Parse($text) Json_NewObject() Json_Null() Json_IsNull($v) Json_IsObject($v) Json_IsArray($v)
Json_Get($obj,$key,$default) Json_GetStr($obj,$key,$default) Json_GetInt(...) Json_GetBool(...)
Json_Has($obj,$key) Json_Set($obj,$key,$value)
Json_Stringify($value[,$indent]) Json_Quote($s)
Json_ArrayPush($arr,$v) Json_ArrayLen($arr) Json_ArrayGet($arr,$i) _Json_NewArray()
```
注意：`_Json_NewArray()` 返回带哨兵的数组，**只当不透明句柄用**，不要直接 `UBound()`。

### lib\Asar.au3
```
Asar_Open($asarPath) -> 对象(0=失败)      Asar_GetRoot($o)  Asar_FilesObject($o)
Asar_GetNode($o,$innerPath)               Asar_Has($o,$innerPath)
Asar_ReadBytes($o,$innerPath) -> Binary   Asar_ReadText($o,$innerPath) -> String
Asar_PutFile($o,$innerPath,$binary)       Asar_RemoveFile($o,$innerPath)
Asar_IsPatched($o,$scriptPath)            Asar_Save($o,$outPath)
Asar_CountFiles($o) -> [文件数, 目录数]
常量：$ASAR_MARKER = "/* pi-lang-patch */"，$ASAR_BLOCK = 4194304
```
`Asar_Save` 语义：保持原文件顺序，被替换文件用新内容，新增追加末尾，未改动文件复用原 integrity。已实测：原版 asar 往返字节级一致。

## 各模块接口（签名固定）

### lib\Config.au3（Lead 写）
```
$CFG_LOCALE_ZH = "zh-CN"   $CFG_LOCALE_EN = "en-US"
$CFG_STATE_ZH = "zh"       $CFG_STATE_RESTORED = "restored"   $CFG_STATE_PAUSED = "paused"
Cfg_Load()  -> Dictionary（文件不存在/损坏时返回默认值，绝不失败）
Cfg_Save($cfg)
Cfg_Default() -> Dictionary
```

### lib\Locator.au3（Lead 写）
```
$LOC_PROCESS_NAME = "Pi Network.exe"
Loc_IsValid($dir) -> bool（$dir\resources\app.asar 存在）
Loc_AsarPath($dir) -> String
Loc_Find($cfg) -> String（配置里记的 → 卸载注册表 DisplayIcon → 默认路径；找不到返回 ""）
```

### lib\LangPack.au3（au3-inject 写）
```
Lang_SeedIfMissing()            把内置 res\zh-CN.json 释放到 langs\（不存在才写）
Lang_Load($locale) -> Dictionary {
    "locale": "zh-CN", "name": "简体中文", "version": "0.6.4",
    "entries": Dictionary(英文原文 -> 译文，区分大小写),
    "danger": AU3 数组(只允许整句精确匹配的键),
    "patterns": AU3 数组(每项 Dictionary{"p": 正则, "r": 替换})
}
```
词表文件结构（res\zh-CN.json，UTF-8 无 BOM）：
```json
{"locale":"zh-CN","name":"简体中文","version":"0.6.4",
 "entries":{"英文":"中文"},
 "danger":["Remove all blockchain data", ...],
 "patterns":[{"pattern":"^(\\d+) seconds? ago$","replacement":"$1 秒前"}]}
```
注意：词表里存在仅大小写不同的键（`Awaiting config` / `AWAITING CONFIG`），必须保留。
注意：`patterns` 的字段名是 `pattern`/`replacement`，输出给注入脚本时要转成 `p`/`r`。

### lib\StaticPatches.au3（au3-inject 写）
```
$SP_MAINJS = "dist/main/main.js"    $SP_RENDERERJS = "dist/renderer/renderer.js"
SP_ApplyMain($text)      SP_RevertMain($text)
SP_ApplyRenderer($text)  SP_RevertRenderer($text)
SP_HasAny($text, "main"|"renderer") -> bool
```
替换表照抄 `C:\Users\Administrator\Desktop\Pi多语言包\src\Patch\StaticPatches.cs`（30 条菜单 label + 9 条 confirm 文案），**顺序不能变**（长串在前）。替换是纯字符串常量替换，不碰逻辑。

### lib\Injector.au3（au3-inject 写）
```
$INJ_SCRIPT_PATH = "dist/renderer/pi-lang.js"   $INJ_INDEX_PATH = "dist/renderer/index.html"
Inj_EnsureResources()   把 res\pi-lang.js.template 释放到 U_ResourceDir()（每次启动调用，幂等）
Inj_BuildScript($pack)  -> String（模板里把 __PI_LANG_DATA__ 换成内联 JSON，结果含 $ASAR_MARKER）
Inj_PatchHtml($html)    -> String（首个 <script 前插入 "<script defer=defer src=./pi-lang.js></script>"，幂等）
Inj_UnpatchHtml($html)  -> String
```
注入脚本模板在 `res\pi-lang.js.template`（已就位），内联 JSON 结构照 `src\Patch\Injector.cs`：
`{"locale":..,"version":..,"entries":{..},"danger":[..],"patterns":[{"p":..,"r":..}]}`

### lib\Patcher.au3（Lead 写）
```
Patch_State($cfg) -> "patched" | "notpatched" | "missing" | "unknown"
Patch_Install($cfg, $pack) -> {"ok":bool,"message":str,"version":str}
Patch_Restore($cfg) -> {"ok":bool,"message":str}
Patch_Ensure($cfg, $pack) -> {"ok":bool,"message":str}
Patch_ReadAppVersion($asarObj) -> String
Patch_IsAppRunning() -> bool
```

### lib\Tray.au3（au3-tray 写）
```
Tray_Run($cfg)   阻塞运行到用户退出（内含 2 秒守护定时器、15 秒启动更新检查、30 分钟周期检查）
```

### lib\Updater.au3（au3-update 写）
```
Upd_CurrentAppVersion() -> "1.0.0"
Upd_ShouldCheckNow($cfg) -> bool
Upd_CheckAndApply($cfg, $fnProgress = 0) -> {"ok":bool,"message":str,"appUpdated":bool,"langUpdated":bool}
```
`$fnProgress` 可选回调：`$fnProgress($stage, $percent)`。

### lib\SelfTest.au3（au3-update 写）
```
ST_Run($cfg, $pack) -> exit code（0 全过）
```

## 目录

```
PiLang.au3                主入口（CLI + 托盘）
lib\*.au3                 模块
res\pi-lang.js.template   注入脚本模板
res\zh-CN.json            词表种子
res\antnest.ico           托盘图标
test\Test-*.au3           各自模块自检
build\AddBom.ps1          加 BOM（构建前跑）
build\build.ps1           编译出 exe
```

## Agent 交付要求

每个模块交付时必须附上：

1. `Au3Check -w 2` 对**你自己的测试脚本** 0 error 0 warning；
2. 自检脚本实际跑过，输出贴关键行（不是"应该没问题"）；
3. 跑之前先 `pwsh -NoProfile -File build\AddBom.ps1`。
