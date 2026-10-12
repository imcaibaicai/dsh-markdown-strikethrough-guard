# dsh-markdown-strikethrough-guard

> DSH 客户端 Markdown 删除线防御插件：拦截半角波浪号（`~`）表示数值范围时的误触删除线问题，同时完整保留 GFM 双波浪号删除线（`~~`）、代码块与 LaTeX 公式。

## 一、 背景与痛点

在 DSH Web 前端渲染机制中，Markdown 解析依赖 `@deepseek-ai/dsh-client-ui-primitives`，底层引入了 `micromark-extension-gfm-strikethrough`，且默认开启 `singleTilde: true`。

这导致中文与技术表达中常见的数值范围表达（如 `6~8 行`、`160~180 字`）中的两个单个波浪号会被解析器分别误判为 `<del>`（删除线）的开闭标签，导致两个范围之间的整段正文被画上水平删除线，而波浪号本身被吞掉。

## 二、 修复原理

本插件通过 DSH 客户端插件规范注入（依赖 `@deepseek-ai/dsh-client-ui-primitives`），在渲染层的 `MarkdownText` 组件入口处进行无感分词规整：
1. **智能分词保护**：跳过代码围栏（` ``` ` 与 `~~~`）、行内代码（`` ` ``）、LaTeX 公式（`$...$` 与 `$$...$$`）、原生双波浪号删除线（`~~`）以及已转义波浪号（`\~`）；
2. **安全字符转义**：将文本中孤立的单波浪号 `~` 转义为 `\~`。根据 CommonMark 规范，`\~` 被解析后会在最终 DOM 中还原为纯文本的半角 ASCII `~`，绝不触发删除线语法；
3. **零侵入与热插拔**：完全不修改 DSH 核心 `app.asar` 与静态前端代码，可随时通过卸载脚本一键完全恢复。

## 三、 安装与卸载

### 安装
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```
安装后请**完全退出并重启 DeepSeek Harness**以加载插件行。

### 卸载
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```
卸载后重启 DSH 即可恢复官方默认解析行为。
