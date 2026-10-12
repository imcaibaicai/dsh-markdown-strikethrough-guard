window.__ModuleLoader__.load({
	id: "dsh-markdown-strikethrough-guard",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		exports.inject = ["@deepseek-ai/dsh-client-ui-primitives"];
		exports.apply = function apply() {
			patchPrimitives();
		};

		if (window.__DSH_MARKDOWN_STRIKETHROUGH_GUARD_INSTALLED__) return module.exports;
		window.__DSH_MARKDOWN_STRIKETHROUGH_GUARD_INSTALLED__ = true;

		let react = require("react");
		let react_jsx_runtime = require("react/jsx-runtime");
		let primitives = null;
		try {
			primitives = require("@deepseek-ai/dsh-client-ui-primitives");
		} catch (e) {
			console.warn("[dsh-markdown-strikethrough-guard] failed to require primitives:", e);
		}

		/**
		 * Safely escape lone tildes (ASCII 126) that are not part of GFM double-tilde strikethrough (~~),
		 * code blocks, inline code backticks, or LaTeX math.
		 * 
		 * When escaped as \~, CommonMark decodes \~ back to a literal ASCII ~ in the final DOM,
		 * preventing GFM's singleTilde: true from treating lone tildes as <del> openers/closers.
		 */
		function sanitizeTildes(md) {
			if (!md || typeof md !== "string" || !md.includes("~")) return md;

			// Token regex matches constructs where ~ must be preserved:
			// 1. Fenced code: ```...``` or ~~~...~~~ (including streaming unclosed fences)
			// 2. Inline code: `...`
			// 3. Display math: $$...$$
			// 4. Inline math: $...$
			// 5. GFM strikethrough: ~~
			// 6. Escaped tilde: \~
			// 7. Or lone ~ (group 2) -> replace with \~
			const tokenRegex = /(```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)|`[^`\r\n]*`|\$\$[\s\S]*?(?:\$\$|$)|(?<!\$)\$(?!\$)[^$\r\n]+(?<!\$)\$(?!\$)|~~|\\~)|(~)/g;

			return md.replace(tokenRegex, (match, preserve, loneTilde) => {
				if (preserve) return preserve;
				if (loneTilde) return "\\~";
				return match;
			});
		}

		function patchPrimitives() {
			if (!primitives || !primitives.MarkdownText) {
				try {
					primitives = require("@deepseek-ai/dsh-client-ui-primitives");
				} catch (e) {}
			}
			if (!primitives || !primitives.MarkdownText) return;
			if (primitives.MarkdownText.__strikethroughGuardPatched) return;

			const OriginalMarkdownText = primitives.MarkdownText;

			const PatchedMarkdownText = react.memo(function PatchedMarkdownText(props) {
				if (props && typeof props.text === "string" && props.text.includes("~")) {
					const safeText = sanitizeTildes(props.text);
					return react_jsx_runtime.jsx(OriginalMarkdownText, {
						...props,
						text: safeText
					});
				}
				return react_jsx_runtime.jsx(OriginalMarkdownText, props);
			});

			PatchedMarkdownText.__strikethroughGuardPatched = true;
			PatchedMarkdownText.displayName = "PatchedMarkdownText(" + (OriginalMarkdownText.displayName || OriginalMarkdownText.name || "MarkdownText") + ")";
			primitives.MarkdownText = PatchedMarkdownText;
		}

		// Patch immediately on factory materialization
		patchPrimitives();

		exports.sanitizeTildes = sanitizeTildes;
		exports.patchPrimitives = patchPrimitives;
		return module.exports;
	}
});
