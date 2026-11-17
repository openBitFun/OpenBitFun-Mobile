import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { MUTED } from './Theme';

/** Shared section rhythm for account, connection and preference groups. */
@ComponentV2
export struct SettingsSectionTitle {
  @Require @Param title: string;

  build() {
    Text(this.title)
      .fontSize(MobileDesignTypography.labelSmall.size)
      .lineHeight(MobileDesignTypography.labelSmall.lineHeight)
      .fontWeight(FontWeight.Regular)
      .fontColor(MUTED)
      .width('100%')
      .padding({ left: MobileDesignGeometry.settingsRowPadding, right: MobileDesignGeometry.settingsRowPadding })
      .margin({ bottom: 8 })
  }
}
