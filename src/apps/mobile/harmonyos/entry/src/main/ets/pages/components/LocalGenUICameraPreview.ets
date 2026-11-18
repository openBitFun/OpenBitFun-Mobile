import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MobileDesignTypography } from '../../generated/MobileDesignTokens';
import {
  LOCAL_GESTURE_SURFACE_HEIGHT,
  LOCAL_GESTURE_SURFACE_WIDTH
} from '../../services/local-genui/LocalGenUIGestureCamera';
import { CONTENT_ON_ACTION, LINE, MEDIA_BACKGROUND, TOAST_BACKGROUND } from './Theme';

/**
 * Small live camera preview shown while a Local GenUI app listens for
 * gestures, so the person knows the camera is on and can frame themselves.
 * Platform leaf: it only owns the surface and reports its id.
 */
@ComponentV2
export struct LocalGenUICameraPreview {
  /** A short (landscape phone) screen gets a smaller preview at the same aspect. */
  @Param compact: boolean = false;
  /** Match the floating preview to the current window orientation. */
  @Param landscape: boolean = false;
  @Event onSurface: (surfaceId: string) => void = (_surfaceId: string) => {};
  @Event onSurfaceGone: () => void = () => {};
  private controller: XComponentController = new XComponentController();

  private previewWidth(): number {
    return this.landscape ? (this.compact ? 80 : 128) : (this.compact ? 60 : 96);
  }

  private previewHeight(): number {
    return this.landscape ? (this.compact ? 60 : 96) : (this.compact ? 80 : 128);
  }

  aboutToDisappear(): void {
    this.onSurfaceGone();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      XComponent({ type: XComponentType.SURFACE, controller: this.controller })
        .onLoad(() => {
          this.controller.setXComponentSurfaceSize({
            surfaceWidth: LOCAL_GESTURE_SURFACE_WIDTH,
            surfaceHeight: LOCAL_GESTURE_SURFACE_HEIGHT
          });
          this.onSurface(this.controller.getXComponentSurfaceId());
        })
        // The front-camera preview arrives rotated in landscape. Rotate the
        // child counter-clockwise while swapping its layout dimensions so the
        // person remains upright inside the horizontal preview card.
        .width(this.landscape ? this.previewHeight() : this.previewWidth())
        .height(this.landscape ? this.previewWidth() : this.previewHeight())
        .rotate({ angle: this.landscape ? -90 : 0 })
      Text(RemoteI18n.t('localGenui.cameraOn'))
        .fontSize(MobileDesignTypography.labelSmall.size)
        .fontColor(CONTENT_ON_ACTION)
        .backgroundColor(TOAST_BACKGROUND)
        .padding({ left: this.compact ? 4 : 6, right: this.compact ? 4 : 6, top: 2, bottom: 2 })
        .borderRadius(8)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
        .margin({ bottom: this.compact ? 4 : 6 })
    }
    .width(this.previewWidth())
    .height(this.previewHeight())
    .borderRadius(this.compact ? 12 : 16)
    .clip(true)
    .backgroundColor(MEDIA_BACKGROUND)
    .border({ width: 1, color: LINE })
    .accessibilityText(RemoteI18n.t('localGenui.cameraOn'))
  }
}
