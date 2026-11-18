/**
 * Visual-only presentation for a streamed GenUI document.
 *
 * The renderer owns the DOM and this helper only adds temporary attributes.
 * It can therefore be used by the desktop preview and the Harmony ArkWeb
 * bundle without introducing another renderer or a second source format.
 */
export interface GenUIGenerationPresentation {
  update: () => void;
  finish: () => Promise<void>;
  dispose: () => void;
}

interface GenerationWindow extends Window {
  __openbitfunGenUIGeneration?: GenUIGenerationPresentation;
}

const STYLE = `
html[data-genui-generation-phase]{isolation:isolate}
html[data-genui-generation-phase="wire"] [data-genui-generation-surface],
html[data-genui-generation-phase="background"] [data-genui-generation-surface]{background:transparent!important}
html[data-genui-generation-phase="wire"] [data-genui-generation-wire],
html[data-genui-generation-phase="background"] [data-genui-generation-wire]{
  color:transparent!important;-webkit-text-fill-color:transparent!important;
  background-color:transparent!important;background-image:none!important;
  border-color:var(--openbitfun-color-border-default)!important;box-shadow:none!important;text-shadow:none!important;
  caret-color:transparent!important;outline:1px solid var(--openbitfun-color-border-default)!important;outline-offset:-1px
}
html[data-genui-generation-phase="wire"] [data-genui-generation-wire] :is(h1,h2,h3,p,label,span){
  background-image:linear-gradient(var(--openbitfun-color-border-default),var(--openbitfun-color-border-default))!important;
  background-size:70% 1px!important;background-position:left center!important;
  background-repeat:no-repeat!important
}
html[data-genui-generation-phase="wire"] [data-genui-generation-wire] :is(img,svg,canvas,video),
html[data-genui-generation-phase="background"] [data-genui-generation-wire] :is(img,svg,canvas,video){opacity:0!important}
html[data-genui-generation-phase="background"]::before{
  content:"";position:fixed;inset:0;pointer-events:none;z-index:2147483645;
  background:var(--genui-generation-background);opacity:.82;
  animation:genui-generation-fill 280ms linear both
}
@keyframes genui-generation-fill{from{transform:translateY(-100%)}to{transform:translateY(0)}}
`;

function isVisible(element: Element): boolean {
  return !element.closest('[hidden],[aria-hidden="true"],template') &&
    (element as HTMLElement).getClientRects().length > 0;
}

function isTransparentColor(color: string): boolean {
  if (!color || color === 'transparent') return true;
  // Computed colors may use legacy rgba() or modern slash-alpha notation.
  const alpha = color.match(/^rgba\([^)]*,\s*([\d.]+%?)\s*\)$/i)?.[1] ??
    color.match(/\/\s*([\d.]+%?)\s*\)$/)?.[1];
  return alpha !== undefined && Number.parseFloat(alpha) === 0;
}

function authoredBackground(elements: Element[]): string {
  for (const element of elements) {
    const style = window.getComputedStyle(element);
    if (style.backgroundImage !== 'none') return style.background;
    if (!isTransparentColor(style.backgroundColor)) {
      return style.backgroundColor;
    }
  }
  return 'transparent';
}

/** Install the three-stage presentation on the current streamed document. */
export function installGenUIGenerationPresentation(options: { root?: HTMLElement; stepMs?: number } = {}): GenUIGenerationPresentation {
  const pageWindow = window as GenerationWindow;
  pageWindow.__openbitfunGenUIGeneration?.dispose();
  const root = document.documentElement;
  const style = document.createElement('style');
  style.dataset.genuiGenerationStyle = 'true';
  style.textContent = STYLE;
  const timers = new Set<number>();
  const groups = new Map<string, number>();
  let ordinal = 0;
  let finishing = false;
  let disposed = false;
  let completion: Promise<void> | undefined;
  let resolveCompletion: (() => void) | undefined;

  const schedule = (callback: () => void, delay: number) => {
    const timer = window.setTimeout(() => {
      timers.delete(timer);
      if (!disposed) callback();
    }, delay);
    timers.add(timer);
  };

  const page = () => options.root ?? document.querySelector<HTMLElement>('[data-gen-ui-app]') ?? document.body;

  const clear = () => {
    root.removeAttribute('data-genui-generation-phase');
    root.style.removeProperty('--genui-generation-background');
    document.querySelectorAll('[data-genui-generation-wire]').forEach(element => element.removeAttribute('data-genui-generation-wire'));
    document.querySelectorAll('[data-genui-generation-surface]').forEach(element => element.removeAttribute('data-genui-generation-surface'));
    style.remove();
  };

  const dispose = () => {
    if (disposed) return;
    disposed = true;
    observer.disconnect();
    timers.forEach(timer => window.clearTimeout(timer));
    timers.clear();
    clear();
    resolveCompletion?.();
    if (pageWindow.__openbitfunGenUIGeneration === api) delete pageWindow.__openbitfunGenUIGeneration;
  };

  const update = () => {
    if (disposed || finishing) return;
    const host = page();
    if (!host) return;
    if (!style.isConnected) (document.head ?? root).appendChild(style);
    const surfaces = [host, ...Array.from(host.querySelectorAll(':scope > main,:scope > .page,:scope > .pk'))];
    surfaces.forEach(element => element.setAttribute('data-genui-generation-surface', 'true'));
    root.dataset.genuiGenerationPhase = 'wire';
    const selectors = '[data-openbitfun-component],[data-gen-ui-node],button,input,select,textarea,form,figure,table,[role="list"],[role="listitem"]';
    const nodes = Array.from(host.querySelectorAll<HTMLElement>(selectors)).filter(isVisible);
    if (nodes.length === 0 && isVisible(host)) nodes.push(host);
    nodes.forEach((element, index) => {
      const key = element.id || `${element.tagName}:${element.className}:${index}`;
      if (!groups.has(key)) groups.set(key, ordinal++);
      element.setAttribute('data-genui-generation-wire', String(groups.get(key)));
    });
    root.style.setProperty('--genui-generation-background', authoredBackground([host, document.body, root]));
  };

  const finish = () => {
    if (completion) return completion;
    if (disposed || window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      dispose();
      return Promise.resolve();
    }
    update();
    finishing = true;
    observer.disconnect();
    completion = new Promise<void>(resolve => { resolveCompletion = resolve; });
    root.dataset.genuiGenerationPhase = 'background';
    schedule(() => {
      root.dataset.genuiGenerationPhase = 'paint';
      const ordered = Array.from(document.querySelectorAll<HTMLElement>('[data-genui-generation-wire]'))
        .sort((left, right) => Number(left.dataset.genuiGenerationWire) - Number(right.dataset.genuiGenerationWire));
      const step = Math.min(120, Math.max(16, options.stepMs ?? 58), 720 / Math.max(1, ordered.length));
      ordered.forEach((element, index) => schedule(() => element.removeAttribute('data-genui-generation-wire'), index * step));
      schedule(dispose, ordered.length * step + 30);
    }, 280);
    return completion;
  };

  const observer = new MutationObserver(() => update());
  const api: GenUIGenerationPresentation = { update, finish, dispose };
  pageWindow.__openbitfunGenUIGeneration = api;
  (document.head ?? root).appendChild(style);
  root.dataset.genuiGenerationPhase = 'wire';
  observer.observe(document, { childList: true, subtree: true });
  update();
  return api;
}
