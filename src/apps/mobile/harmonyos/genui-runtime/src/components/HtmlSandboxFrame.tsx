"use client";

import { useEffect, useMemo, useRef } from "react";
import { useColorScheme } from "./openui/scheme";

// ArkWeb serves this URL locally. Its response policy applies to the whole
// authored document, independently of the stricter parent rawfile policy.
const SANDBOX_URL = "https://genui-sandbox.openbitfun.invalid/view";
const REPORTER = `<script>
(function () {
  function post(type, details) { parent.postMessage(Object.assign({ type: type }, details), "*"); }
  addEventListener("error", function (e) { post("html-view-error", { message: String(e.message || "Script error").slice(0, 200) }); });
  addEventListener("unhandledrejection", function () { post("html-view-error", { message: "Unhandled script rejection" }); });
  addEventListener("securitypolicyviolation", function (e) {
    if (e.effectiveDirective.startsWith("script-src")) post("html-view-error", { message: "Game script blocked by policy" });
  });
  addEventListener("load", function () { post("html-view-loaded", {}); });
})();
</script>`;

function documentFor(html: string, scheme: "light" | "dark") {
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>:root{color-scheme:${scheme}}html,body{margin:0}body{font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}</style>${REPORTER}${html}`;
}

export function HtmlSandboxFrame({ html, height, title }: { html: string; height: number; title: string }) {
  const frame = useRef<HTMLIFrameElement>(null);
  const scheme = useColorScheme(frame);
  const srcDoc = useMemo(() => documentFor(html, scheme), [html, scheme]);
  const gameInput = useMemo(() => /data-openbitfun-game|<canvas(?:\s|>)/i.test(html), [html]);

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const iframe = frame.current;
      if (!iframe || event.source !== iframe.contentWindow || event.origin !== "null") return;
      const data = event.data;
      if (data?.type === "html-view-error") {
        iframe.dataset.htmlViewStatus = "error";
        iframe.dataset.htmlViewError = String(data.message || "Script error").slice(0, 200);
      } else if (data?.type === "html-view-loaded" && iframe.dataset.htmlViewStatus !== "error") {
        iframe.dataset.htmlViewStatus = "ready";
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, []);

  return (
    <iframe
      key={srcDoc}
      ref={frame}
      className="gen-ui-oi-html"
      title={title}
      style={{ height, touchAction: gameInput ? "none" : "auto" }}
      sandbox="allow-scripts"
      src={SANDBOX_URL}
      referrerPolicy="no-referrer"
      data-html-view-status="pending"
      onLoad={event => {
        const iframe = event.currentTarget;
        if (iframe.dataset.mountSent) return;
        iframe.dataset.mountSent = "true";
        iframe.contentWindow?.postMessage({ type: "html-view-mount", html: srcDoc }, "*");
      }}
    />
  );
}
