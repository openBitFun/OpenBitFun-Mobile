import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
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
  @Param active: boolean = false;
  @Event onSurface: (surfaceId: string) => void = (_surfaceId: string) => {};
  @Event onSurfaceGone: () => void = () => {};
  private controller: XComponentController = new XComponentController();

  private previewWidth(): number {
    return this.landscape ? this.longEdge() : this.shortEdge();
  }

  private previewHeight(): number {
    return this.landscape ? this.shortEdge() : this.longEdge();
  }

  private shortEdge(): number {
    return this.compact ? MobileDesignGeometry.genuiCameraCompactShortEdge : MobileDesignGeometry.genuiCameraShortEdge;
  }

  private longEdge(): number {
    return this.compact ? MobileDesignGeometry.genuiCameraCompactLongEdge : MobileDesignGeometry.genuiCameraLongEdge;
  }

  private labelInset(): number {
    return this.compact ? MobileDesignGeometry.genuiCameraCompactLabelInset : MobileDesignGeometry.genuiCameraLabelInset;
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
      if (this.active) {
        Text(RemoteI18n.t('localGenui.cameraOn'))
          .fontSize(MobileDesignTypography.labelSmall.size)
          .fontColor(CONTENT_ON_ACTION)
          .backgroundColor(TOAST_BACKGROUND)
          .padding({
            left: this.labelInset(), right: this.labelInset(),
            top: MobileDesignGeometry.genuiCameraLabelVerticalPadding,
            bottom: MobileDesignGeometry.genuiCameraLabelVerticalPadding
          })
          .borderRadius(MobileDesignGeometry.genuiCameraLabelRadius)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
          .margin({ bottom: this.labelInset() })
      }
    }
    .width(this.previewWidth())
    .height(this.previewHeight())
    .borderRadius(this.compact ? MobileDesignGeometry.genuiCameraCompactRadius : MobileDesignGeometry.genuiCameraRadius)
    .clip(true)
    .backgroundColor(MEDIA_BACKGROUND)
    .border({ width: 1, color: LINE })
    .accessibilityText(this.active ? RemoteI18n.t('localGenui.cameraOn') : '')
  }
}
