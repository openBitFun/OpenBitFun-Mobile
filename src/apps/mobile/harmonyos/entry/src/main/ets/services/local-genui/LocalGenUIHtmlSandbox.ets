// A locally answered document with its own response policy. The parent keeps
// its rawfile script policy; only this opaque, offline frame runs authored JS.
export const HTML_SANDBOX_URL: string = 'https://genui-sandbox.openbitfun.invalid/view';
const POLICY: string = "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; " +
  "style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; font-src data:; " +
  "connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'";
export function htmlSandboxResponse(): WebResourceResponse {
  const response = new WebResourceResponse();
  response.setResponseHeader([
    { headerKey: 'Content-Security-Policy', headerValue: POLICY },
    { headerKey: 'Cache-Control', headerValue: 'no-store' },
    { headerKey: 'Referrer-Policy', headerValue: 'no-referrer' }
  ]);
  response.setResponseMimeType('text/html');
  response.setResponseEncoding('utf-8');
  response.setResponseCode(200);
  response.setReasonMessage('OK');
  response.setResponseData($rawfile('genui/html-view.html'));
  return response;
}
