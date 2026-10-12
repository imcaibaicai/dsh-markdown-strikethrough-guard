# dsh-markdown-strikethrough-guard

> DSH client plugin: protects single-tilde ranges (e.g. `6~8 lines`, `160~180 words`) from mis-triggering GFM strikethrough in chat views, while preserving standard double-tilde (`~~`) strikethrough, code blocks, and LaTeX math.

[中文文档](./README.md)

---

## Background & Problem

In DeepSeek Harness Web GUI, Markdown rendering is powered by `@deepseek-ai/dsh-client-ui-primitives`, which under the hood imports `micromark-extension-gfm-strikethrough`. When invoked without explicit options, `micromark-extension-gfm-strikethrough` defaults to `singleTilde: true`.

In Chinese and technical contexts, single ASCII tildes (`~`) are widely used to denote numeric ranges (e.g. `6~8`, `160~180`, `10~20ms`). The Markdown parser mistakenly treats the first `~` as an opening delimiter for `<del>` (strikethrough) and the second `~` as the closing delimiter, causing everything in-between to be rendered with a strike-through line, and eating both tilde characters.

## How It Works

This plugin dynamically intercepts `MarkdownText` from `@deepseek-ai/dsh-client-ui-primitives`:
1. **Context-Aware Tokenizer**: Accurately skips code fences (`` ``` `` and `~~~`), inline code (`` ` ``), LaTeX math (`$...$` and `$$...$$`), standard GFM strikethrough (`~~`), and already-escaped tildes (`\~`).
2. **Safe Character Escaping**: Escapes isolated lone tildes (`~`) into `\~`. In accordance with CommonMark specifications, `\~` resolves to a literal ASCII `~` in the output DOM without triggering any strikethrough syntax.
3. **Zero Core Modifications**: Cleanly attaches via Cordis client plugin injection; zero changes to `app.asar` or core files; fully reversible via the uninstaller.

## Installation & Removal

### Install
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```
Restart DeepSeek Harness completely for the plugin row to take effect.

### Uninstall
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```
Restart DeepSeek Harness to revert to official stock behavior.

## License

MIT License (c) 2026 imcaibaicai
