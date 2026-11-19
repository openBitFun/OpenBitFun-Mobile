import type { GenUIVerification } from '../genUIVerification';
import type { LocalProbeReport, LocalRuntimeBuild, LocalRuntimeSnapshot } from './localRuntimeProtocol';

/** Computed colors serialize with an alpha channel; zero alpha paints nothing. */
function isTransparent(color: string): boolean {
  if (color === 'transparent') return true;
  const channels = color.slice(color.indexOf('(') + 1, color.lastIndexOf(')')).split(',');
  return channels.length === 4 && Number(channels[3]) === 0;
}

/** Frame loading is asynchronous; most pages have no frames and do not wait. */
export async function waitForHtmlViews(): Promise<void> {
  const pending = () => document.querySelector('[data-gen-ui-content] [data-html-view-status="pending"]');
  if (!pending()) return;
  await new Promise<void>(resolve => {
    const finish = () => { observer.disconnect(); clearTimeout(timeout); resolve(); };
    const observer = new MutationObserver(() => { if (!pending()) finish(); });
    observer.observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ['data-html-view-status'] });
    const timeout = setTimeout(finish, 2000);
  });
}

/**
 * Read-only geometry probe for local acceptance. It never dispatches events or
 * runs actions; it reports what the mounted canvas actually rendered.
 */
export function probeLocalCanvas(requestId: string, snapshot: LocalRuntimeSnapshot, build: LocalRuntimeBuild, report?: GenUIVerification, stateTypes: Record<string, string> = {}): LocalProbeReport {
  const canvas = document.querySelector<HTMLElement>('[data-gen-ui-viewport]');
  // Geometry is reported in logical canvas pixels; the canvas may be scaled.
  const scale = (window as { __genuiCanvasScale?: number }).__genuiCanvasScale ?? 1;
  const content = document.querySelector<HTMLElement>('[data-gen-ui-content]');
  const canvasRect = canvas?.getBoundingClientRect();
  let left = Number.POSITIVE_INFINITY;
  let right = Number.NEGATIVE_INFINITY;
  let top = Number.POSITIVE_INFINITY;
  let bottom = Number.NEGATIVE_INFINITY;
  let visible = 0;
  const origin0 = canvasRect ?? { left: 0, top: 0, width: 0 };
  let widest = { right: 0, tag: '', className: '' };
  for (const element of Array.from(content?.querySelectorAll<HTMLElement>('*') ?? [])) {
    // The application root is the page surface: it is meant to fill the
    // screen edge to edge, so it is not content inside the gutter.
    if (element.classList.contains('gen-ui-application')) continue;
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) continue;
    const style = getComputedStyle(element);
    if (style.visibility === 'hidden' || style.display === 'none' || Number(style.opacity) === 0) continue;
    // Painted boxes (cards, fills, borders) count as visible content too;
    // otherwise an overflowing card with in-bounds text would pass.
    const painted = !isTransparent(style.backgroundColor)
      || parseFloat(style.borderLeftWidth) > 0 || parseFloat(style.borderRightWidth) > 0 || style.boxShadow !== 'none';
    const ownContent = element.children.length === 0 ? Boolean(element.textContent?.trim()) : false;
    if (!painted && !ownContent && element.tagName !== 'svg' && element.tagName !== 'IMG' && element.tagName !== 'INPUT') continue;
    if ((rect.right - origin0.left) / scale > widest.right) widest = { right: (rect.right - origin0.left) / scale, tag: element.tagName.toLowerCase(), className: String(element.className).split(' ')[0] ?? '' };
    visible += 1;
    left = Math.min(left, rect.left);
    right = Math.max(right, rect.right);
    top = Math.min(top, rect.top);
    bottom = Math.max(bottom, rect.bottom);
  }
  const origin = canvasRect ?? { left: 0, top: 0, width: 0 };
  const renderErrors = [
    ...Array.from(content?.querySelectorAll<HTMLElement>('[data-html-view-status]') ?? [])
      .filter(frame => frame.dataset.htmlViewStatus !== 'ready')
      .map(frame => `HtmlView: ${frame.dataset.htmlViewError || 'document did not start'}`),
    ...(report?.issues ?? []).filter(issue => issue.severity === 'error').map(issue => `${issue.path}: ${issue.message}`),
    ...Array.from(document.querySelectorAll('.gen-ui-application__error')).map(element => element.textContent ?? ''),
  ].filter(Boolean);
  const unsupportedComponents = Array.from(document.querySelectorAll<HTMLElement>('[data-openbitfun-state="unsupported"]'))
    .map(element => element.dataset.genUiAdapterComponent ?? element.dataset.openbitfunComponent ?? 'unknown');
  return {
    requestId,
    appId: snapshot.identity?.appId ?? '',
    sourceRevision: snapshot.sourceRevision,
    rendererRevision: build.rendererRevision,
    viewport: { width: window.innerWidth, height: window.innerHeight, devicePixelRatio: window.devicePixelRatio },
    canvasWidth: canvas?.offsetWidth ?? 0,
    canvasScale: scale,
    contentBounds: visible === 0 ? { left: 0, right: 0, top: 0, bottom: 0 } : {
      left: Math.round((left - origin.left) / scale),
      right: Math.round((right - origin.left) / scale),
      top: Math.round((top - origin.top) / scale),
      bottom: Math.round((bottom - origin.top) / scale),
    },
    // Real overflow is judged against the device viewport, not the design width.
    scrollWidth: document.documentElement.scrollWidth,
    visibleElements: visible,
    componentCount: content?.querySelectorAll('[class*="gen-ui-"], [class*="hm-"]').length ?? 0,
    renderErrors,
    unsupportedComponents,
    hostPartsInDocument: document.querySelectorAll('.gen-ui-phone-device, .gen-ui-phone-status-bar, [data-gen-ui-host-part="status-bar"], [data-gen-ui-host-part="device-frame"]').length,
    contractOk: snapshot.status === 'ready',
    stateTypes,
    widestElement: `${widest.tag}.${widest.className}@${Math.round(widest.right)}`,
  };
}
