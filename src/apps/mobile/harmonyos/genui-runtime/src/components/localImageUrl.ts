const hostImages = 'https://genui-assets.openbitfun.invalid/';

/** WKWebView resolves the same host image reference through its custom resource scheme. */
export function localImageUrl(source: string): string {
  if (typeof location === 'undefined' || location.protocol !== 'openbitfun-genui:' ||
    location.hostname !== 'runtime' || !source.startsWith(hostImages)) return source;
  return 'openbitfun-genui://runtime/host-image/' + source.slice(hostImages.length);
}
