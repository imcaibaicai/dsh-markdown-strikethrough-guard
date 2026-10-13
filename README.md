# dsh-markdown-strikethrough-guard

> ## ⚠️ 重大更正（2026-10-13）：本插件在当前 DSH 构建下**无效**，请勿安装
>
> v0.1.0 声称通过"替换 `MarkdownText` 组件"来修掉「单波浪号被误判成删除线」的问题。
> 经对 `app.asar` 的逐层逆向核实，**该方案在本构建里架构上就不可能生效**：
> DSH 交给客户端插件的**所有模块命名空间都被 `Object.freeze` 冻结**，对导出对象赋值会**静默失败**。
>
> 本仓库因此保留为**避坑分析记录**，而不是一个可用工具。完整证据见下文《三、为什么无效（全链路证据）》。
> 真正可用的替代方案见《五、那还能怎么修》。

---

## 一、现象

DSH 正文里写数值区间（`6~8 行`、`160~180 字`、`第一~二节`、`10~20ms`）时：

- 出现横贯整段的**删除线**；
- 两处 `~` 本体**消失**，文字变成 `68` / `第一二节`；
- 复制出来的文本也**缺掉波浪号**。

## 二、根因

DSH 前端 Markdown 解析链路：`MarkdownText` → `parseGfmWithMath()` → `fromMarkdown(text, { extensions: [gfm(), ...] })`。
其中 `gfm()` 来自 `micromark-extension-gfm`，其 strikethrough 子扩展在**未显式传参时默认 `singleTilde: true`**：

> **单个 ASCII `~`（U+007E）即构成删除线定界符。**

于是第一个 `~` 被当成 `<del>` 开标签、第二个被当成闭标签，两者之间整段进入 `<del>`，而两个 `~` 作为语法符号被消费掉、不再出现在 DOM 里。

## 三、为什么无效（全链路证据）

以下结论来自对 `<DSH 安装目录>\resources\app.asar` 内
`@deepseek-ai/dsh-web-frontend/dist/assets/index-*.js`（壳层打包产物）
与 `@deepseek-ai/dsh-client-ui-primitives/lib/index.js`（未压缩源码）的核对。

### 1. 插件 `require` 到的是**冻结的**模块命名空间

壳层里有一张静态模块表（`staticModules`），插件 `require` 拿到的就是这些标识符：

```js
function rM(){return{react:Ef,"react/jsx-runtime":If,"react-dom":Rf,"react-dom/client":Df,
  "@deepseek-ai/cordis":sf,"@deepseek-ai/dsh-client-store":lh,
  "@deepseek-ai/dsh-client-ui-slots":hh,
  "@deepseek-ai/dsh-client-ui-primitives":sE,
  "@deepseek-ai/dsh-client-ui-dockkit":XS}}
```

而 `sE` 的定义是：

```js
const sE = Object.freeze(Object.defineProperty({ __proto__: null,
  BrandWordmark: K_, Button: cc, ...,
  MarkdownDelegateProvider: jb, MarkdownText: z8, ... },
  Symbol.toStringTag, { value: "Module" }));
```

`Object.freeze` 之后，`primitives.MarkdownText = Patched` 在**非严格模式下静默失效**（严格模式下直接抛错）。
→ v0.1.0 的全部补丁逻辑等于什么都没做。

### 2. React 的命名空间也一样冻结

它们的工厂函数是：

```js
function as(e, n){
  ...
  return Object.freeze(Object.defineProperty(e, Symbol.toStringTag, { value: "Module" }));
}
```

所以"改 `react/jsx-runtime` 的 `jsx` 来拦截元素创建"这条路同样不成立。

### 3. `MarkdownText` 直接调用模块内部的解析闭包，没有任何注入点

```js
var z8 = j.memo(function({ text, streaming = false, labels, fileMentions, pathImages, variant = "body" }){
  ...
  // $b = renderSettled，Bb = StreamingRenderer
  g = o ? streamRef.render(text) : $b(text, labels, fileMentions, pathImages);
  ...
});
```

`$b` 与 `Bb` 都是模块内部的局部闭包，**既没有导出、也不读任何可注入的配置**。
因此不存在"把 `singleTilde` 关掉"或"替换解析器"的官方口子。

### 4. 唯一名字像扩展点的 `MarkdownDelegate` 与解析无关

未压缩源码（`markdown/MarkdownDelegate.js`）写得很清楚：

```js
const MarkdownDelegateContext = createContext({});
function MarkdownDelegateProvider({ children, openExternalLink, openFile, fileImages }) { ... }
function useMarkdownDelegate() { return useContext(MarkdownDelegateContext); }
```

它的 value **只承载「打开外链 / 打开文件 / 图片解析」三类回调**（消费处形如
`const { openExternalLink } = useMarkdownDelegate();`），
**没有任何解析或渲染覆写能力**，指望不上。

### 5. 调用方全部走"渲染时属性读取"

`dsh-client-ui-chat` / `-plan` / `-tool` / `-trajectory` / `-agent-preset` /
`-sidebar-documentpreview` / `-user-questions` 都是这个写法：

```js
jsx(_deepseek_ai_dsh_client_ui_primitives.MarkdownText, { text, labels })
```

由于被读取的对象是冻结的 `sE`，**从外部无法替换**。

### 结论

> 在本构建下，**纯客户端插件无法改变 Markdown 的解析结果或渲染组件**。
> 所有"换组件 / 改 jsx 运行时 / 换模块缓存"的思路都因 `Object.freeze` 而不成立。

---

## 四、v0.1.0 的第二个、独立的 bug：装进了没人读的 profile

即使补丁能生效，v0.1.0 也**根本不会被加载**：

- 运行中的宿主进程命令行会写明它加载哪个 profile，例如
  `...\dsh-desktop-host\lib\index.js ... <DSH_HOME>\profiles\desktop ...`
- 而 v0.1.0 的安装脚本把 loader 行**硬编码写进了 `profiles\web`**。

正确做法（本仓库的 `install.ps1` 已按此重写）：

1. 用 `Get-CimInstance Win32_Process` 确认宿主实际加载的 profile；
2. **所有**存在 `cordis.patch.yml` 的 profile 都追加 loader 行；
3. 在 `profiles\<profile>\node_modules` 与共享的 `profiles\node_modules` 下都建 junction；
4. host 插件在启动时装载 —— 必须**完全退出并重启** DSH 才生效；
5. 删除 junction 必须用 `[System.IO.Directory]::Delete($p, $false)`，
   `Remove-Item -Recurse` 会顺着链接删掉真包。

---

## 五、那还能怎么修？

| 方案 | 是否可行 | 代价 |
|---|---|---|
| 替换 `MarkdownText` 组件（本插件的做法） | **不可行** | 命名空间冻结，静默失效 |
| 改 `react/jsx-runtime` 拦截元素创建 | **不可行** | 同上冻结 |
| 修改解析器配置 `gfm({ singleTilde: false })` | 不可行（除非改核心） | 需改 `app.asar`，升级即被覆盖 |
| 覆盖 `conversation.chat.node` 座位里 `key: "assistant-step"` 的正文渲染器 | 原理可行，**不建议** | 该座位是**整块**助手节点的渲染器；覆盖会连带丢掉工具行、推理折叠、过程分组、操作按钮，而插件拿不到原组件的引用（它是冻结模块内的局部变量），等于重写整个组件 |
| DOM 事后修复（MutationObserver） | 原理可行，**脆弱** | 需从"已渲染结果"反推原定界符（且不能误伤真正的 `~~删除线~~`）、要跟 React 的协调机制抢 DOM；本仓库未做端到端验证 |
| 包装可写的 Service 实例方法（数据层，在文本进入 Markdown 之前） | 原理可行，**依赖未公开内部结构** | 需包装 `ctx.sessions` / 投影存储的内部方法，跨版本易碎 |
| **让源头不产生半角 `~`**（推荐） | **有效、零风险** | 约定输出数值区间时使用全角 `～`（U+FF5E）或「至/到」；对**之后**的消息彻底生效，历史消息不变 |

> 一句话：**能改的是"文本"，改不了的是"渲染"。**
> 所以对这个现象，源头约定（`～` / 「至」）才是性价比最高、且唯一可验证的做法。

---

## 六、安装（仅供研究复现，不解决问题）

```powershell
# 安装到所有 profile
powershell -ExecutionPolicy Bypass -File .\install.ps1
# 一键回滚（移除 junction 与 loader 行）
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

## License

MIT
