import { MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { SHEET_HEADER_HEIGHT, SHEET_HEADER_SIDE_PADDING } from './SheetLayout';
import { SheetCloseButton } from './SheetCloseButton';
import { INK, LINE, MUTED } from './Theme';

/** Standard top-right dismissal header for modal and replace-in-place Sheet pages. */
@ComponentV2
export struct SheetCloseHeader {
  @Param uniformGlyph: boolean = true;
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param showDivider: boolean = false;
  @Param isEnabled: boolean = true;
  @Event onClose: () => void = () => {};

  build() {
    Row() {
      Column({ space: 2 }) {
        if (this.title.length > 0) {
          Text(this.title)
            .fontSize(MobileDesignTypography.conversationHeaderTitle.size)
            .lineHeight(MobileDesignTypography.conversationHeaderTitle.lineHeight)
            .fontWeight(FontWeight.Medium)
            .fontColor(INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(MobileDesignTypography.bodySmall.size)
            .lineHeight(MobileDesignTypography.bodySmall.lineHeight)
            .fontColor(MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SheetCloseButton({
        isEnabled: this.isEnabled,
        uniformGlyph: this.uniformGlyph,
        onClose: this.onClose
      })
    }
    .width('100%')
    .height(SHEET_HEADER_HEIGHT)
    .padding({ left: SHEET_HEADER_SIDE_PADDING + 8, right: SHEET_HEADER_SIDE_PADDING })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: this.showDivider ? 0.5 : 0 }, color: LINE })
  }
}
