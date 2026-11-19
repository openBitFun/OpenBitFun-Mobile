import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { GenUIAppearance } from '../state/GenUIAppearance';
import BuildProfile from 'BuildProfile';
import { LocalGenUIRuntimeBridge } from '../../services/local-genui/LocalGenUIRuntimeBridge';
import { LOCAL_GENUI_ICON3D_ROOT } from '../../services/local-genui/LocalGenUIIcon3DStore';
import { LOCAL_GENUI_PHOTO_ROOT } from '../../services/local-genui/LocalGenUIImageSearch';
import { LOCAL_GENUI_COLLABORATION_ROOT } from '../../services/local-genui/LocalGenUICollaborationAssets';
import { RemoteLogger } from '../../services/RemoteLogger';

const LOCAL_GENUI_WEB_ID: string = 'local-genui-runtime-web';

/** ArkWeb javaScriptProxy object. Every message is untrusted input. */
class LocalGenUINativeChannel {
  private readonly dispatch: (raw: string) => void;
  constructor(dispatch: (raw: string) => void) { this.dispatch = dispatch; }
  post(raw: string): void { this.dispatch(raw); }
}

/**
 * Platform leaf for the Local GenUI runtime. It owns only the WebView
 * lifecycle and message transport; parsing and rendering stay in the bundle.
 */
@ComponentV2
export struct LocalGenUIWebSurface {
  @Param @Require bridge: LocalGenUIRuntimeBridge;
  @Local appearance: GenUIAppearance = GenUIAppearance.connect();
  @Param scheme: string = 'light';
  @Param locale: string = 'zh-CN';
  private controller: webview.WebviewController = new webview.WebviewController();
  private alive: boolean = true;
  // Offline documents repeat the same blocked-resource warning on every render.
  private loggedConsole: Set<string> = new Set<string>();
  private channel: LocalGenUINativeChannel = new LocalGenUINativeChannel((raw: string): void => {
    if (this.alive) this.bridge.receive(raw);
  });

  aboutToAppear(): void {
    if (BuildProfile.DEBUG) {
      // Debug builds only: lets native acceptance evidence inspect the real DOM.
      webview.WebviewController.setWebDebuggingAccess(true);
    }
    this.bridge.setAppearance(this.scheme, this.locale, this.appearance.current());
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.bridge.detach();
  }

  @Monitor('scheme', 'locale', 'appearance.look')
  onAppearanceChange(): void {
    this.bridge.setAppearance(this.scheme, this.locale, this.appearance.current());
  }

  private send(json: string): void {
    if (!this.alive) return;
    try {
      this.controller.runJavaScript(`window.__genuiHost && window.__genuiHost.receive(${JSON.stringify(json)})`)
        .catch((err: Error) => RemoteLogger.warn(`local genui runtime send failed: ${err.message}`));
    } catch (err) {
      RemoteLogger.warn(`local genui runtime send failed: ${String(err)}`);
    }
  }

  private async capture(): Promise<image.PixelMap | undefined> {
    // Component snapshot of the Web node: what the runtime actually rendered.
    try {
      const pixels = await this.getUIContext().getComponentSnapshot().get(LOCAL_GENUI_WEB_ID);
      if (pixels) {
        return pixels;
      }
    } catch (err) {
      RemoteLogger.warn(`local genui component snapshot failed: ${String(err)}`);
    }
    return new Promise<image.PixelMap | undefined>((resolve: (value: image.PixelMap | undefined) => void) => {
      try {
        this.controller.webPageSnapshot({ id: 'local-genui-thumbnail' }, (err, result) => {
          resolve(!err && result && result.status !== false ? result.imagePixelMap : undefined);
        });
      } catch (err) {
        RemoteLogger.warn(`local genui page snapshot failed: ${String(err)}`);
        resolve(undefined);
      }
    });
  }

  build() {
    Web({ src: $rawfile('genui/runtime/index.html'), controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(false)
      .imageAccess(true)
      // Network images stay closed by the document CSP (img-src data:, blob: and
      // the host picture address). The host address is answered below and never
      // reaches the network; this switch only lets those requests be issued.
      .onlineImageAccess(true)
      .geolocationAccess(false)
      .mediaPlayGestureAccess(true)
      .darkMode(WebDarkMode.Off)
      .forceDarkAccess(false)
      .overScrollMode(OverScrollMode.NEVER)
      .javaScriptProxy({ object: this.channel, name: 'genuiNative', methodList: ['post'], controller: this.controller })
      .onControllerAttached(() => {
        this.bridge.attach((json: string): void => this.send(json));
        this.bridge.attachSnapshot((): Promise<image.PixelMap | undefined> => this.capture());
      })
      .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => {
        // Host-served 3D pictures; nothing else is intercepted. Answers are
        // asynchronous: the picture may need one download before the cache has it.
        const url = event.request.getRequestUrl();
        const collaborationImage = url.startsWith(LOCAL_GENUI_COLLABORATION_ROOT);
        const photo = url.startsWith(LOCAL_GENUI_PHOTO_ROOT);
        if (!url.startsWith(LOCAL_GENUI_ICON3D_ROOT) && !collaborationImage && !photo) {
          return null;
        }
        RemoteLogger.info('local genui host image request');
        const response = new WebResourceResponse();
        response.setResponseIsReady(false);
        response.setResponseHeader([
          { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' },
          { headerKey: 'Cache-Control', headerValue: collaborationImage ? 'no-store' : 'max-age=31536000, immutable' }
        ]);
        void this.bridge.picture(url).then((bytes: ArrayBuffer | undefined) => {
          RemoteLogger.info(`local genui host image ${bytes ? `served ${bytes.byteLength} bytes` : 'not found'}`);
          if (bytes) {
            response.setResponseData(bytes);
            response.setResponseMimeType(collaborationImage || photo ? 'image/jpeg' : 'image/png');
            response.setResponseCode(200);
            response.setReasonMessage('OK');
          } else {
            response.setResponseData('');
            response.setResponseMimeType('text/plain');
            response.setResponseCode(404);
            response.setReasonMessage('Not Found');
          }
          response.setResponseIsReady(true);
        });
        return response;
      })
      .onOverrideUrlLoading((request: WebResourceRequest) => {
        // The runtime never navigates. Generated content cannot open pages.
        return request.getRequestUrl().indexOf('genui/runtime/index.html') < 0;
      })
      .onConsole((event) => {
        if (event && event.message.getMessageLevel() === MessageLevel.Error) {
          const text = event.message.getMessage().slice(0, 300);
          if (!this.loggedConsole.has(text) && this.loggedConsole.size < 50) {
            this.loggedConsole.add(text);
            RemoteLogger.warn(`local genui runtime console: ${text}`);
          }
        }
        return false;
      })
      .id(LOCAL_GENUI_WEB_ID)
      .width('100%')
      .height('100%')
  }
}
