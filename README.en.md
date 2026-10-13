# dsh-markdown-strikethrough-guard

> ## ⚠️ Correction (2026-10-13): this plugin does **NOT work** on current DSH builds — do not install it
>
> v0.1.0 claimed to fix "a lone tilde becomes a strikethrough" by **replacing the `MarkdownText` component**.
> A layer-by-layer audit of `app.asar` shows that approach **cannot work architecturally**: every module
> namespace handed to a client plugin is wrapped in **`Object.freeze`**, so assigning to an export
> (`primitives.MarkdownText = Patched`) **fails silently**.
>
> This repository is therefore kept as **an analysis / pitfall record**, not as a usable tool.
> Full evidence below; the realistic alternatives are in "Can it be fixed at all?".

[中文文档（更详细）](./README.md)

---

## Symptom

Writing numeric ranges in chat (`6~8`, `160~180`, `sections 1~2`) produces a **strikethrough line**
across the text, and both `~` characters **disappear** (the text reads `68` instead of `6~8`).
Copied text loses the tildes too.

## Root cause

`MarkdownText` → `parseGfmWithMath()` → `fromMarkdown(text, { extensions: [gfm(), ...] })`.
`gfm()` comes from `micromark-extension-gfm`, whose strikethrough sub-extension defaults to
**`singleTilde: true`** when called without options:

> **A single ASCII `~` (U+007E) is a valid strikethrough delimiter.**

So the first `~` opens a `<del>` and the second closes it; everything in between is struck through,
and both tildes are consumed as syntax and never reach the DOM.

## Why it cannot work (evidence chain)

### 1. Plugin `require` receives frozen module namespaces

The shell bundle builds a static module table (`staticModules`) — these identifiers are exactly what
plugins get from `require`:

```js
function rM(){return{react:Ef,"react/jsx-runtime":If,"react-dom":Rf,"react-dom/client":Df,
  "@deepseek-ai/cordis":sf,"@deepseek-ai/dsh-client-store":lh,
  "@deepseek-ai/dsh-client-ui-slots":hh,
  "@deepseek-ai/dsh-client-ui-primitives":sE,
  "@deepseek-ai/dsh-client-ui-dockkit":XS}}
```

and `sE` is defined as:

```js
const sE = Object.freeze(Object.defineProperty({ __proto__: null,
  BrandWordmark: K_, Button: cc, ..., MarkdownText: z8, ... },
  Symbol.toStringTag, { value: "Module" }));
```

After `Object.freeze`, `primitives.MarkdownText = Patched` is a **silent no-op** in sloppy mode
(and throws in strict mode). → All of v0.1.0's patching logic did nothing.

### 2. React namespaces are frozen the same way

```js
function as(e, n){ ...
  return Object.freeze(Object.defineProperty(e, Symbol.toStringTag, { value: "Module" }));
}
```

So "patch `react/jsx-runtime`'s `jsx` to intercept element creation" is dead too.

### 3. `MarkdownText` calls a module-internal parser closure — no injection point

```js
var z8 = j.memo(function({ text, streaming = false, labels, fileMentions, pathImages, variant = "body" }){
  // $b = renderSettled, Bb = StreamingRenderer
  g = o ? streamRef.render(text) : $b(text, labels, fileMentions, pathImages);
});
```

`$b` / `Bb` are local closures: not exported, and they read no injectable configuration.
There is no supported way to disable `singleTilde` or swap the parser.

### 4. The one promisingly-named extension point is unrelated

`markdown/MarkdownDelegate.js` (unminified source):

```js
const MarkdownDelegateContext = createContext({});
function MarkdownDelegateProvider({ children, openExternalLink, openFile, fileImages }) { ... }
```

Its value carries **only** "open external link / open file / image resolution" callbacks. No parsing
or rendering override whatsoever.

### 5. Every call site reads the component off the frozen namespace

```js
jsx(_deepseek_ai_dsh_client_ui_primitives.MarkdownText, { text, labels })
```

…in `dsh-client-ui-chat` / `-plan` / `-tool` / `-trajectory` / `-agent-preset` /
`-sidebar-documentpreview` / `-user-questions`. Since `sE` is frozen, it cannot be replaced from outside.

## Second, independent bug in v0.1.0: installed into the wrong profile

Even a working patch would never have loaded: the running host names its profile on the command line
(`...\dsh-desktop-host\lib\index.js ... <DSH_HOME>\profiles\desktop ...`), while v0.1.0's installer
hardcoded the loader row into `profiles\web`. `install.ps1` has been rewritten to:

1. identify the active profile via `Get-CimInstance Win32_Process`;
2. append the loader row to **every** profile that has a `cordis.patch.yml`;
3. junction the package into each `profiles\<profile>\node_modules` and the shared `profiles\node_modules`;
4. require a **full restart** (host plugins load at startup);
5. remove junctions with `[System.IO.Directory]::Delete($p, $false)` — `Remove-Item -Recurse` would
   follow the link and delete the real package.

## Can it be fixed at all?

| Approach | Feasible? | Cost |
|---|---|---|
| Replace `MarkdownText` (what v0.1.0 did) | **No** | Frozen namespace → silent no-op |
| Patch `react/jsx-runtime` | **No** | Frozen by the same helper |
| Set `gfm({ singleTilde: false })` | Only by patching core | `app.asar` edits are wiped on upgrade |
| Override the `conversation.chat.node` seat at `key: "assistant-step"` | Technically yes, **not advisable** | That seat renders the whole assistant node; overriding it drops tool rows, reasoning folding, process grouping and action buttons, and a plugin cannot obtain a reference to the original component (module-local closure) |
| DOM post-processing (MutationObserver) | Technically yes, **fragile** | Must re-derive delimiters from rendered output without harming genuine `~~strike~~`, and fight React reconciliation; not verified end-to-end |
| Wrapping a writable Service instance method (data layer, before Markdown) | Technically yes, **undocumented internals** | Depends on private projection-store internals; brittle across versions |
| **Never emit a lone ASCII `~` at the source** (recommended) | **Yes, zero risk** | Agree to write ranges as full-width `～` (U+FF5E) or the word "to"; fully effective for *future* messages, historical ones unchanged |

> **What can be changed is the text; what cannot be changed is the rendering.**

## Install (for research reproduction only — it does not fix anything)

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

## License

MIT
