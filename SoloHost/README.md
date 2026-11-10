# 蚁巢 Pi 多语言助手（SoloHost App）

装在 Pi Node 里的展示页：一个 nginx 容器 + 内嵌静态页面，作为 **SoloHost 应用**
添加到节点应用列表，在 Pi 界面里打开（默认 `http://127.0.0.1:8090/`）。

## 它是什么

一个"展示 + 引导"页面，不含任何写入或上报逻辑：

- 显示最新程序版本（含体积）、词表版本（含词条数）、更新时间 —— 数据来自 GitHub 清单；
- 提供汉化工具的下载入口（清单里的 `app.url`，指向 GitHub Release 直链）；
- 三步使用说明（下载运行 → 退出 Pi Node 后装补丁 → 重启生效）；
- 汉化范围说明（能翻什么、翻不了什么）；
- 中/英切换（页面自带 i18n，选择记在 localStorage）；
- 标签 `pi.ui.primary: "true"`，会被 Pi 识别为主 UI 应用。

页面本身**不会修改 Pi Node 客户端** —— 汉化由 Windows 上的托盘工具完成
（`Pi多语言包-AU3.exe`，1.4MB；C# 版 `PiLang.exe` 51.8MB 也还在 Release 里）。

## 目录

```
docker-compose.yml    SoloHost 应用定义（nginx 容器 + 内嵌 index.html 页面）
config_options.yml    SoloHost 安装时的配置界面（端口）
README.md             本说明
```

## 当前对应版本

| 项目 | 值 |
|---|---|
| 工具版本 | 1.0.11（`PiLang-AU3.exe`，1.4MB） |
| 适配 Pi Network | 0.6.4 |
| 词表 | 0.6.4，641 条 |
| 原生菜单 | 30 条 |
| 确认弹窗 | 8 条 |

页面上的数字从清单实时读，升级后自动变，不用改页面。

## 安装（Pi Node 里）

在 Pi Node 里把这个 `docker-compose.yml` 添加为节点应用（Add a Node App / SoloHost），
安装后页面以 `http://127.0.0.1:8090/` 运行。配置项 `PILANG_PORT` 默认 `8090`
（避开 SoloHost 助手默认的 8080）。

## 页面数据来源

只请求两个只读地址（HTTPS）：

- `https://raw.githubusercontent.com/antapp-cc/pi-lang-pack/main/server/latest.json`
- `https://cdn.jsdelivr.net/gh/antapp-cc/pi-lang-pack@main/server/latest.json`（备选）

读的字段：`app.version`、`app.size`、`app.url`、`lang.version`、`lang.entries`、`lang.updatedAt`。
清单怎么维护见主项目 `docs/更新与发布.md`。

CSP 只放行上面两个域名，`script-src` 允许内联（页面脚本内联在 HTML 里）。

## 本地预览

把 `docker-compose.yml` 里 `cat > ... <<'EOF'` 与 `EOF` 之间的 HTML 复制成 `index.html`，
浏览器直接打开即可（版本信息需要联网）。
