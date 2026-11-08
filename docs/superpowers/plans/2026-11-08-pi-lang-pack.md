# Pi 多语言包 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做一个独立的 C# WinForms 托盘工具，给 Pi Node 桌面版注入简体中文界面，并在官方自动更新覆盖 `app.asar` 后自动重打；词表独立成多语言包，可一键还原。

**Architecture:** 不重编译 Pi Node。工具向 `resources\app.asar` 注入 `dist/renderer/pi-lang.js`（内联语言包 + DOM 翻译引擎），并在 `index.html` 里加载它；常驻守护轮询 asar 补丁标记，官方更新后自动备份并重打。所有 asar 读写用纯 C# 实现（pickle 头 + JSON 索引 + 数据区），无第三方依赖。

**Tech Stack:** C# / .NET 10 WinForms（`net10.0-windows`）、System.Text.Json、Roslyn 无需、Node 仅用于一次性验证原型。

**Spec:** `docs/2026-11-08-design.md`

## Global Constraints

- 目标程序：Pi Node 桌面版 v0.6.4，安装目录 `C:\Users\Administrator\AppData\Local\Programs\pi-network-desktop`，界面资源在 `resources\app.asar`。
- 注入文件名固定 `dist/renderer/pi-lang.js`；补丁标记 = asar 中存在该文件且其内容含 `/* pi-lang-patch */`。
- 词条只做**整句精确匹配**；危险词条带 `"danger": true`；不做模糊匹配。
- 不改 `Pi Network.exe`、不改 CSP、不依赖 Node 运行时（最终 exe 自包含）。
- 用户可见文案全部简体中文；程序自身 UI/日志/使用说明也用中文。
- 配置目录 `%APPDATA%\PiLang`；日志 `PiLang.log`；备份 `backup\app.asar.<version>.orig`。
- 与 PiGuard 无代码/进程/文件耦合，独立托盘、独立自启任务（任务名 `Pi多语言包`）。
- 写 asar 一律"临时文件 + 原子替换"，失败用备份回滚。

## Review Focus

- **官方更新后的坏状态**：新版 asar 结构变化（index.html 路径变更/文件改名）时，工具必须回滚并报警，而不是留下坏 asar。
- **还原后被打回**：`desiredState=restored` 时守护不得自动重打。
- **运行中写入**：Pi Node 运行中 asar 被占用，写入必须失败得干净（提示重启/关闭），不能留下半写文件。
- **词表版本不匹配**：新版应用上旧词表照打，但危险词条匹配不上必须保留英文。
- **翻译循环/闪烁**：注入脚本自改 DOM 不得触发自身再次翻译造成死循环。

---

### Task 0: 副本验证（Node 原型，一次性）

**Files:**
- Create: `tools/proto/asar-lite.js`（读/写 asar 的最小实现，throwaway）
- Create: `tools/proto/pi-lang-proto.js`（最小词表 + DOM 翻译）
- Create: `tools/proto/verify.js`（启动副本 + CDP 取页面文本）
- 副本目录：`C:\Users\Administrator\Desktop\_pi_verify\pi-copy`（验证完删除）

**Interfaces:**
- Produces: 结论——注入后的 asar 能否被 Electron 正常加载、DOM 翻译在真实页面是否生效；验证通过才继续 Task 1+。

- [ ] **Step 1:** 复制安装目录到 `_pi_verify\pi-copy`，把 `Pi Network.exe` 改名为 `Pi Node Test.exe`（避免 PiGuard 误管）。
- [ ] **Step 2:** 用 `asar-lite.js` 对副本 asar 注入 `pi-lang-proto.js` + 改 index.html，结构回读校验（文件数 + 每个文件 SHA256 一致）。
- [ ] **Step 3:** 启动 `Pi Node Test.exe --remote-debugging-port=9333 --user-data-dir=<副本临时目录>`，等窗口出现。
- [ ] **Step 4:** 用 Node 内置 WebSocket 连 CDP，`Runtime.evaluate` 取 `document.body.innerText`，确认含中文（例如"节点"）且无 JS 异常。
- [ ] **Step 5:** 关闭副本进程，记录证据（截图/文本）到 `_pi_verify\result.md`；清理副本。

### Task 1: 词表

**Files:**
- Create: `langs/zh-CN.json`
- Create: `tools/extract-strings.js`（从 sourcemap 提取，保留来源 file:line 便于校对）
- Test: 结构校验脚本（每条 value 非空、key 唯一、danger 条目人工清单核对）

**Interfaces:**
- Produces: `langs/zh-CN.json`，格式 `{ "version": "0.6.4", "name": "简体中文", "locale": "zh-CN", "entries": { "<英文原文>": "<中文>" }, "danger": ["<英文原文>", ...] }`；总条数 ≥ 470。

- [ ] **Step 1:** 跑提取脚本产出 `_pi_inspect/to-translate.json`（本会话已产出 477 条，复用）。
- [ ] **Step 2:** 分批翻译（每批 ~120 条），关键界面人工校对；危险操作（移除数据、迁移、卸载、停止节点）逐条核对。
- [ ] **Step 3:** 写结构校验脚本并跑通：无空值、无重复键、danger 条目都在 entries 里。
- [ ] **Step 4:** 用 20 条抽样在 Task 0 副本页面上验证词条能命中（CDP 检查）。

### Task 2: C# 工程骨架 + AsarEditor

**Files:**
- Create: `src/PiLang.csproj`（`net10.0-windows`，WinForms，AssemblyName `PiLang`，图标 `antnest.ico`）
- Create: `src/Asar/AsarArchive.cs`（解析/序列化/改文件/写回）
- Create: `src/Asar/Pickle.cs`（asar 头 pickle 读写）
- Create: `src/Log.cs`、`src/Config.cs`、`src/InstallLocator.cs`
- Test: `--selftest` 分支里的断言（读原 asar → 写新 asar → 再读 → 文件数/内容一致；注入一个文件再移除 → 还原）

**Interfaces:**
- Consumes: 无
- Produces:
  - `AsarArchive.Open(string path)` / `.Save(string outPath)` / `.Files` / `.TryAddFile(string relPath, byte[] data)` / `.RemoveFile(string relPath)` / `.ReadFile(string relPath)`
  - `Pickle.ReadHeader(byte[] headerBuf)` / `Pickle.WriteHeader(IDictionary<string,object> header)`
  - `InstallLocator.Find()` → `string?` 安装目录（config → 注册表 DisplayIcon → 默认路径）
  - `Config.Load()/Save()`，字段见 Spec §8

- [ ] **Step 1:** 对原始 asar 写往返自检（读→写→读，540 文件逐字节一致）并跑通。
- [ ] **Step 2:** 注入/移除自检（加 `pi-lang.js`、改 index.html、再移除）并跑通。
- [ ] **Step 3:** 损坏输入自检（截断 asar、非法 header）必须抛清晰异常不崩溃。

### Task 3: 注入脚本（DOM 翻译引擎）

**Files:**
- Create: `src/Patch/pi-lang.js.template`（资源；注入时替换 `__LANGPACK_JSON__`）
- Create: `src/Patch/Injector.cs`（生成最终脚本、修改 index.html、写补丁标记）
- Test: `--selftest` 里用最小 HTML + 词表断言翻译结果（用 C# 内嵌 JS 引擎不可行 → 改为把注入脚本的逻辑在 Node 里测，C# 只测"生成产物结构正确、标记存在、index.html 插入位置正确"）

**Interfaces:**
- Produces: `Injector.BuildScript(LangPack pack, string locale)` → `string`；`Injector.PatchIndexHtml(string html)` → `string`；`Injector.UnpatchIndexHtml(string html)` → `string`；`Injector.IsPatched(AsarArchive asar)` → `bool`

- [ ] **Step 1:** 写模板：扫描 Text 节点 / placeholder / title / aria-label / alt / label；精确匹配；MutationObserver 节流；防循环标记；中文字体 CSS；内联语言包。
- [ ] **Step 2:** 用 Node 在 JSDOM 缺失情况下用最小字符串替换逻辑单测（把匹配函数抽成可在 Node 里跑的纯函数），确认动态插入节点也能翻、不重复翻。
- [ ] **Step 3:** C# 自检：生成的脚本含语言包与标记；index.html 插入/移除位置正确。

### Task 4: PatchEngine（安装/还原/状态）

**Files:**
- Create: `src/Patch/PatchEngine.cs`
- Test: `--selftest`：对临时 asar 跑安装→状态→还原→状态，断言状态机与文件内容。

**Interfaces:**
- Produces: `PatchEngine.Install(installDir, LangPack, locale, Config cfg)` → `PatchResult`；`Restore(installDir, Config cfg)`；`GetState(installDir)` → `Patched | NotPatched | Unknown`；`Ensure(installDir, LangPack, Config cfg)`（守护用，幂等）

- [ ] **Step 1:** 安装：检测进程运行（运行中拒绝写并提示）；备份；注入；原子替换；更新 config（desiredState=zh、appliedAsarHash）。
- [ ] **Step 2:** 还原：就地移除注入（重打包），失败用备份；更新 config（desiredState=restored）。
- [ ] **Step 3:** Ensure：读状态；`desiredState=zh` 且未打 → 安装；已打且指纹不符 → 重打；`restored/paused` → 不动。
- [ ] **Step 4:** 自检覆盖 Review Focus 的 4 个场景。

### Task 5: Guard + 托盘

**Files:**
- Create: `src/Guard/GuardService.cs`
- Create: `src/Tray/PiLangApp.cs`（托盘图标、菜单、状态、自启任务）
- Modify: `src/Program.cs`（无参=托盘；CLI：`--ensure/--install/--restore/--status/--selftest`）
- Test: `--selftest` + 手动托盘验证

**Interfaces:**
- Consumes: Task 4 的 `PatchEngine`、Task 2 的 `Config`
- Produces: `GuardService.Start()`（2s 轮询）、托盘菜单动作、`--ensure` 退出码（0=正常）

- [ ] **Step 1:** GuardService：轮询指纹 + 状态机 + 日志 + 托盘气泡；异常不退出进程。
- [ ] **Step 2:** 托盘菜单：状态行、安装中文、还原英文、语言选择、开机自启、打开配置目录、退出。
- [ ] **Step 3:** CLI 各参数自检通过；`--ensure` 幂等可重复调用。
- [ ] **Step 4:** 自启任务创建/删除（schtasks，任务名 `Pi多语言包`）。

### Task 6: 端到端验收

**Files:**
- Create: `使用说明.txt`
- Test: 副本 + 正式安装目录验收

- [ ] **Step 1:** 副本验收：新装 → 中文；用原版 asar 覆盖模拟更新 → 5 秒内自动重打；还原 → 英文。
- [ ] **Step 2:** 正式安装验收（先问用户/确认 Pi Node 已关闭）：安装 → 启动 → 截图确认中文；不验收不宣布完成。
- [ ] **Step 3:** 构建双 exe：`dotnet publish -c Release -r win-x64 --self-contained false`（0.6MB）与 `--self-contained true`（约 50MB）。
- [ ] **Step 4:** 写使用说明（格式仿 PiGuard 使用说明.txt）。
