import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { ChatMessageAppCard } from '../../model/RemoteModels';
import {
  CARD, CONNECT_HERO_ACCENT, CONNECT_HERO_BG, CONNECT_HERO_SURFACE, CONTENT_ON_ACTION, INK, LINE, MUTED,
  PRIMARY_ACTION, SHADOW_FAINT, TOAST_BACKGROUND
} from './Theme';

/**
 * A generated mini app inside an assistant message: its rendered preview,
 * name, status and an open action. Same visual language as the MiniApp
 * gallery tile, so the app looks the same wherever it appears.
 */
@ComponentV2
export struct MessageAppCard {
  @Param card: ChatMessageAppCard = { appId: '', title: '', status: '', thumbnailPath: '', link: '' };
  @Event onOpen: (link: string, title: string) => void = (_link: string, _title: string) => {};

  build() {
    Row({ space: MobileDesignGeometry.messageAppCardPadding }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.card.thumbnailPath.length > 0) {
          Image(`file://${this.card.thumbnailPath}`)
            .width('100%').height('100%').objectFit(ImageFit.Cover)
            .draggable(false).accessibilityLevel('no')
        } else {
          Text(this.initial())
            .fontSize(MobileDesignTypography.displayLarge.size).fontWeight(FontWeight.Bold)
            .fontColor(CONNECT_HERO_ACCENT)
            .width('100%').height('100%').textAlign(TextAlign.Center)
            .linearGradient({ angle: 145, colors: [[CONNECT_HERO_SURFACE, 0], [CONNECT_HERO_BG, 1]] })
        }
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.wand_and_stars')).fontSize(11).fontColor([CONTENT_ON_ACTION])
        }
        .width(MobileDesignGeometry.messageAppBadgeSize).height(MobileDesignGeometry.messageAppBadgeSize)
        .borderRadius(MobileDesignGeometry.messageAppBadgeSize / 2)
        .backgroundColor(TOAST_BACKGROUND).backgroundBlurStyle(BlurStyle.Thin).margin(MobileDesignGeometry.messageAppBadgeInset)
      }
      .width(MobileDesignGeometry.messageAppPreviewSize).height(MobileDesignGeometry.messageAppPreviewSize)
      .borderRadius(MobileDesignGeometry.messageAppPreviewRadius).clip(true)
      .border({ width: 0.5, color: LINE })

      Column({ space: 4 }) {
        Text(this.card.title)
          .fontSize(MobileDesignTypography.titleSmall.size).fontWeight(FontWeight.Medium).fontColor(INK)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.card.status)
          .fontSize(MobileDesignTypography.labelSmall.size).fontColor(MUTED)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(RemoteI18n.t('common.open'))
          .fontSize(MobileDesignTypography.labelMedium.size).fontWeight(FontWeight.Medium)
          .fontColor(CONTENT_ON_ACTION).backgroundColor(PRIMARY_ACTION)
          .padding({
            left: MobileDesignGeometry.messageAppOpenHorizontalPadding, right: MobileDesignGeometry.messageAppOpenHorizontalPadding,
            top: MobileDesignGeometry.messageAppOpenVerticalPadding, bottom: MobileDesignGeometry.messageAppOpenVerticalPadding
          }).borderRadius(MobileDesignGeometry.messageAppOpenRadius)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(MobileDesignGeometry.messageAppCardPadding)
    .backgroundColor(CARD)
    .borderRadius(MobileDesignGeometry.messageAppCardRadius)
    .border({ width: 0.5, color: LINE })
    .shadow({ radius: 12, color: SHADOW_FAINT, offsetY: 4 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`${this.card.title}, ${this.card.status}`)
    .onClick(() => this.onOpen(this.card.link, this.card.title))
  }

  private initial(): string {
    const trimmed = this.card.title.trim();
    return trimmed.length > 0 ? Array.from(trimmed)[0] : 'AI';
  }
}
