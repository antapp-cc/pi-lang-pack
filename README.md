# Pi 多语言包

给 **Pi Node 桌面版（Pi Network Desktop）** 装界面中文的独立小工具，不修改官方程序、不改签名。

## 特点

- 装一次后界面是简体中文；官方自动更新替换界面文件后，守护程序会自动重新汉化；
- 中文词典、原生菜单栏、确认弹窗都覆盖；
- 可一键还原英文原版（原始界面文件自动备份）；
- 词表按"多语言包"组织，可扩展其他语言；
- 独立托盘程序，和 Pi 守护框互不相干；
- 支持在线更新（词表 + 程序本体，HTTPS + SHA256 校验）。

## 目录

```
src/                     C# 源码（.NET 10 WinForms）
langs/zh-CN.json         中文词表（623 条）
docs/                    设计文档、截图
tools/                   词表提取/采集/验证脚本
server/latest.json       在线更新清单（GitHub raw 可直接作为更新源）
server/zh-CN.json        在线更新用的词表副本
使用说明.txt             用户使用说明
```

## 构建

需要 .NET 10 SDK：

```powershell
cd src
# 免运行时单文件版
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o ..\dist\selfcontained
# 依赖运行时版（小）
dotnet publish -c Release -o ..\dist\framework -p:PublishSingleFile=false
```

## 在线更新

**更新机制、发版步骤、验证方法和已知坑见 [`docs/更新与发布.md`](docs/更新与发布.md)。**

`server/latest.json` 是更新清单；程序启动后和每 6 小时检查一次，也可托盘手动「检查更新」。

- 程序更新：下载 → SHA256 校验 → 退出 → 替换 → 重启（旧版备份为 `.old`）；
- 词表更新：下载 → 校验 → 重新汉化（Pi Node 运行中会等它退出后自动补）。

更新地址默认是 GitHub 上的清单：`https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json`（可在 `%APPDATA%\\PiLang\\config.json` 的 `updateUrl` 改成自己的服务器，GitHub 访问不了时用）。

## 原理

不改 React 源码，只对 `resources\app.asar` 做三件事：

1. 注入 `dist/renderer/pi-lang.js`（内联词表 + DOM 翻译引擎），在 `index.html` 里加载；
2. 替换 `dist/main/main.js` 里的菜单 label（文件/视图/帮助等原生菜单）；
3. 替换 `dist/renderer/renderer.js` 里 `window.confirm` 的消息字符串（原生确认弹窗）。

安装前备份原版 asar，还原时整包恢复。

