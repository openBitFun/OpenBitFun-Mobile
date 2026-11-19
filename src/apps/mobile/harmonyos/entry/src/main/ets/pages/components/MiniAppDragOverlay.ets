import { MiniAppDragState } from '../state/MiniAppDragState';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { CARD, INK, MUTED, MEDIA_BACKGROUND, CONTENT_ON_ACTION, SHADOW_STRONG,
  MEDIA_SCRIM, TRANSPARENT, CONNECT_HERO_ACCENT, CONNECT_HERO_SECONDARY } from './Theme';

@ComponentV2
export struct MiniAppDragOverlay {
  @Require @Param drag: MiniAppDragState;

  @Builder
  private GridTile() {
    Row().width(8).height(8).borderRadius(2.5).backgroundColor(CONTENT_ON_ACTION)
      .opacity(this.drag.overEdge ? 0.85 : 0.55)
  }

  @Builder
  private DesktopGlyph() {
    Column({ space: 2 }) {
      Row({ space: 2 }) {
        this.GridTile()
        Image(this.drag.image).width(8).height(8).objectFit(ImageFit.Cover).borderRadius(2.5)
          .border({ width: 0.5, color: CONTENT_ON_ACTION, radius: 2.5 }).clip(true)
          .rotate({ angle: this.drag.overEdge ? 0 : 12 })
          .translate({ x: this.drag.overEdge ? 0 : 3, y: this.drag.overEdge ? 0 : -5 })
          .animation({ duration: this.drag.reduceMotion ? 0 : 220, curve: Curve.EaseOut })
      }
      Row({ space: 2 }) {
        this.GridTile()
        this.GridTile()
      }
    }
  }

  @Builder
  private DropTarget() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column().width('100%').height('100%')
        .linearGradient({ angle: 180, colors: [[TRANSPARENT, 0], [MEDIA_SCRIM, 0.76], [MEDIA_BACKGROUND, 1]] })
      Column().width('100%').height(MiniAppDragState.GLOW_HEIGHT + this.drag.bottomInset)
        .linearGradient({ angle: 180, colors: [[TRANSPARENT, 0], [CONNECT_HERO_SECONDARY, 0.72], [CONNECT_HERO_ACCENT, 1]] })
        .opacity(this.drag.overEdge ? 0.23 : 0.10)
        .animation({ duration: this.drag.reduceMotion ? 0 : 200, curve: Curve.EaseOut })
      Column().width(236).height(236)
        .radialGradient({ center: ['50%', '50%'], radius: 118,
          colors: [[CONNECT_HERO_ACCENT, 0], [CONNECT_HERO_SECONDARY, 0.22], [TRANSPARENT, 1]] })
        .scale({ x: 1.35, y: 0.32, centerY: '100%' })
        .opacity(this.drag.overEdge ? 0.68 : 0.3)
        .animation({ duration: this.drag.reduceMotion ? 0 : 200, curve: Curve.EaseOut })
        .translate({ x: this.drag.reduceMotion ? 0 :
          (this.drag.fingerX - this.drag.windowX - this.drag.windowWidth / 2) * 0.34, y: 39 })
      Column() {
        Column({ space: 13 }) {
          Row({ space: 12 }) {
            this.DesktopGlyph()
            Text(RemoteI18n.t(this.drag.overEdge ? 'miniapp.releaseShortcut' : 'miniapp.dropShortcut'))
              .fontSize(MobileDesignTypography.bodyMedium.size).fontWeight(FontWeight.Medium)
              .fontColor(CONTENT_ON_ACTION).maxLines(2).textAlign(TextAlign.Center)
          }.padding({ left: 12, right: 12 })
          Row().width(this.drag.overEdge ? '84%' : '56%').height(1)
            .linearGradient({ angle: 90, colors: [[TRANSPARENT, 0], [CONNECT_HERO_SECONDARY, 0.36],
              [CONTENT_ON_ACTION, 0.5], [CONNECT_HERO_ACCENT, 0.64], [TRANSPARENT, 1]] })
            .animation({ duration: this.drag.reduceMotion ? 0 : 240, curve: Curve.EaseOut })
        }.width('100%').constraintSize({ maxWidth: 420 })
      }.width('100%')
        .padding({ top: 10, bottom: MiniAppDragState.GLOW_HEIGHT + this.drag.bottomInset })
        .onAreaChange((_old: Area, area: Area) => {
          this.drag.setTargetTop(Number(area.globalPosition.y));
        })
    }.width('100%').height(MiniAppDragState.GLOW_HEIGHT + this.drag.bottomInset + 86)
      .opacity(this.drag.hintVisible ? 1 : 0)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.drag.active) {
        Column().width('100%').height('100%').backgroundColor(MEDIA_BACKGROUND)
          .opacity(this.drag.contracted ? 0.64 : 0)
        this.DropTarget()

        Column() {
          Image(this.drag.image).width('100%').height(this.drag.coverHeight)
            .objectFit(ImageFit.Cover).draggable(false).flexShrink(0)
          Column({ space: 8 }) {
            Text(this.drag.name).width('100%').fontSize(MobileDesignTypography.titleSmall.size)
              .fontWeight(FontWeight.Bold).fontColor(INK).maxLines(1)
            Text(this.drag.description).width('100%').fontSize(MobileDesignTypography.bodyMedium.size)
              .fontColor(MUTED).maxLines(3)
          }.width(this.drag.initialWidth).padding(20).layoutWeight(1)
            .justifyContent(FlexAlign.Center).opacity(this.drag.contracted ? 0 : 1)
        }.width(this.drag.width).height(this.drag.height).backgroundColor(CARD)
          .borderRadius(this.drag.contracted ? 14 : MobileDesignGeometry.miniappCardRadius).clip(true)
          .shadow({ radius: this.drag.contracted ? 6 : 16, color: SHADOW_STRONG, offsetY: 4 })
          .position({ x: this.drag.fingerX + this.drag.offsetX - this.drag.windowX,
            y: this.drag.fingerY + this.drag.offsetY - this.drag.windowY })
      }
    }.width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
      .onAreaChange((_old: Area, area: Area) => {
        this.drag.windowX = Number(area.globalPosition.x);
        this.drag.windowY = Number(area.globalPosition.y);
        this.drag.windowWidth = Number(area.width);
        this.drag.windowHeight = Number(area.height);
      })
  }
}
