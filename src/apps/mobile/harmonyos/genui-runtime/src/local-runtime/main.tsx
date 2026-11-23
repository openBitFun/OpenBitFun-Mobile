import '../disableOpenUIDevtools';
import { createRoot } from 'react-dom/client';
import '@openbitfun/theme-openbitfun/default.css';
import { i18nService } from "./i18n";
import LocalRuntimeApp, { type LocalRuntimeBridge } from './LocalRuntimeApp';
import type { LocalHostMessage, LocalRuntimeBuild, LocalRuntimeMessage } from './localRuntimeProtocol';
import './localRuntime.scss';

declare const __LOCAL_GENUI_BUILD__: LocalRuntimeBuild;

declare global {
  interface Window {
    /** Host -> runtime entry point called through runJavaScript. */
    __genuiHost?: { receive(raw: string): void };
    __genuiCanvasScale?: number;
  }
}

const build = __LOCAL_GENUI_BUILD__;
const listeners = new Set<(message: LocalHostMessage) => void>();
const backlog: LocalHostMessage[] = [];

let nativePort: MessagePort | undefined;
const pendingPosts: string[] = [];
window.addEventListener('message', event => {
  if (event.source !== null || event.data !== 'local-genui-port' || event.ports.length !== 1) return;
  nativePort?.close();
  nativePort = event.ports[0];
  for (const raw of pendingPosts.splice(0)) nativePort.postMessage(raw);
});

const bridge: LocalRuntimeBridge = {
  post(message: LocalRuntimeMessage) {
    const raw = JSON.stringify(message);
    if (nativePort) nativePort.postMessage(raw);
    else pendingPosts.push(raw);
  },
  subscribe(listener) {
    listeners.add(listener);
    backlog.splice(0).forEach(message => listener(message));
    return () => listeners.delete(listener);
  },
};

function deliver(message: LocalHostMessage) {
  if (!listeners.size) { backlog.push(message); return; }
  listeners.forEach(listener => listener(message));
}

function applyLocale(locale: string | undefined) {
  i18nService.setLocale(locale === 'en-US' ? 'en-US' : 'zh-CN');
}

function applyScheme(scheme: 'light' | 'dark') {
  document.documentElement.dataset.colorScheme = scheme;
  document.documentElement.dataset.openbitfunAppearanceMode = scheme;
  document.documentElement.style.colorScheme = scheme;
}

/**
 * The page runs edge to edge under the native host: the status bar, a side
 * cutout in landscape, the navigation strip and the floating back control lie
 * over it. The host reports that space; the Harmony page kit keeps its title
 * and blocks clear of it while its wash still reaches the screen edges.
 */
function applyInsets(insets: { top: number; left: number; right: number; bottom: number }) {
  const px = (value: number) => `${Math.max(0, Math.round(Number(value) || 0))}px`;
  const root = document.documentElement.style;
  root.setProperty('--genui-host-top', px(insets.top));
  root.setProperty('--genui-host-left', px(insets.left));
  root.setProperty('--genui-host-right', px(insets.right));
  root.setProperty('--genui-host-bottom', px(insets.bottom));
}

window.__genuiHost = {
  receive(raw: string) {
    let message: LocalHostMessage;
    try { message = JSON.parse(raw) as LocalHostMessage; } catch { return; }
    if (message.type === 'init') { void applyLocale(message.locale); void applyScheme(message.scheme); }
    if (message.type === 'theme') void applyScheme(message.scheme);
    if (message.type === 'insets') { applyInsets(message); return; }
    deliver(message);
  },
};

window.addEventListener('error', event => {
  bridge.post({ type: 'error', appId: '', code: 'runtime', message: String(event.message) });
});

/**
 * The page fills the device viewport: a phone stacks the blocks and an
 * unfolded or wide screen sets them side by side (the Harmony page kit owns
 * the reflow). There is no logical canvas scale; probes report 1.
 */
window.__genuiCanvasScale = 1;

// ArkWeb loads this bundle as a classic script from rawfile; no top-level await.
applyLocale(navigator.language.toLowerCase().startsWith('en') ? 'en-US' : 'zh-CN');
applyScheme(window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
createRoot(document.getElementById('root')!).render(<LocalRuntimeApp bridge={bridge} build={build} />);
bridge.post({ type: 'boot', rendererRevision: build.rendererRevision });
