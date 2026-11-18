import type { Ref, ReactNode } from 'react';
import type { GenUIDesignSpec } from './genUIContract';

/**
 * `emulated` draws the phone frame and status bar for desktop previews. `native`
 * is used when the real device host (ArkUI on Harmony) already owns the frame
 * and status bar: the logical app canvas keeps the design width but no host
 * parts are duplicated inside the document.
 */
export type GenUIHostShellMode = 'emulated' | 'native';

export default function GenUIHostSurface({ specification, viewportRef, harmony = false, harmonyTheme = 'blue', harmonyFont = 'sans', harmonyScheme = 'light', shell = 'emulated', children }: {
  specification?: GenUIDesignSpec;
  shell?: GenUIHostShellMode;
  viewportRef?: Ref<HTMLDivElement>;
  harmony?: boolean;
  harmonyTheme?: string;
  harmonyFont?: string;
  harmonyScheme?: string;
  children: ReactNode;
}) {
  if (specification?.shell.kind !== 'phone') {
    return <div ref={viewportRef} className="gen-ui-host-viewport" data-gen-ui-viewport data-gen-ui-host-part="application-frame">{children}</div>;
  }
  const { width, height } = specification.viewport;
  if (shell === 'native') {
    return <div ref={viewportRef} className="gen-ui-phone-viewport gen-ui-phone-viewport--native" data-gen-ui-host-shell="phone-native" data-gen-ui-viewport data-gen-ui-viewport-width={width} data-gen-ui-viewport-height={height} data-hm-theme={harmony ? harmonyTheme : undefined} data-hm-font={harmony ? harmonyFont : undefined} data-hm-scheme={harmony ? harmonyScheme : undefined}>
      <main className="gen-ui-phone-content gen-ui-phone-content--native" data-gen-ui-content>{children}</main>
    </div>;
  }
  return <div className="gen-ui-phone-device" data-gen-ui-host-shell="phone" data-gen-ui-host-part="device-frame" data-hm-theme={harmony ? harmonyTheme : undefined} data-hm-font={harmony ? harmonyFont : undefined} data-hm-scheme={harmony ? harmonyScheme : undefined}>
    <div ref={viewportRef} className="gen-ui-phone-viewport" data-gen-ui-viewport data-gen-ui-viewport-width={width} data-gen-ui-viewport-height={height}>
      <div className="gen-ui-phone-status-bar" data-gen-ui-host-part="status-bar" style={{ height: specification.shell.statusBarHeight }} aria-label="Host status bar">
        <span>9:41</span><span aria-hidden="true" className="gen-ui-phone-status-bar__indicators">5G&nbsp; &#9679;</span>
      </div>
      <main className="gen-ui-phone-content" data-gen-ui-host-part="screen-viewport" data-gen-ui-content>{children}</main>
    </div>
  </div>;
}
