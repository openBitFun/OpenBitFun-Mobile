import { TemplateIcon } from './TemplateIcon';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { SidebarLayoutPolicy } from '../policy/SidebarLayoutPolicy';
import { SIDEBAR_BG, SIDEBAR_LINE, SIDEBAR_MUTED, TRANSPARENT } from './Theme';

/** Pure navigation controls reused in compact and wide sidebars. */
@ComponentV2
export struct SidebarToolsFooter {
  @Param toolsEnabled: boolean = false;
  @Event onOpenTools: () => void = () => {};
  @Event onOpenSettings: () => void = () => {};

  build() {
    Row() {
      Button() {
        Row({ space: SidebarLayoutPolicy.ROW_GAP }) {
          TemplateIcon({ src: $r('app.media.ic_sidebar_tools'),
            iconWidth: MobileDesignGeometry.sidebarFooterIconSize,
            iconHeight: MobileDesignGeometry.sidebarFooterIconSize, tint: SIDEBAR_MUTED })
          Text(RemoteI18n.t('workspaceTools.title'))
            .fontSize(MobileDesignTypography.bodyMedium.size)
            .lineHeight(MobileDesignTypography.bodyMedium.lineHeight)
            .fontWeight(FontWeight.Regular)
            .fontColor(SIDEBAR_MUTED)
            .maxLines(1)
        }.width('100%').justifyContent(FlexAlign.Start)
      }
      .width(SidebarLayoutPolicy.FOOTER_TOOL_MIN_WIDTH)
      .height(SidebarLayoutPolicy.FOOTER_TOOL_HEIGHT)
      .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
      .backgroundColor(TRANSPARENT)
      .border({ width: 0.5, color: TRANSPARENT })
      .borderRadius(10)
      .enabled(this.toolsEnabled)
      .opacity(this.toolsEnabled ? 1 : 0.45)
      .id('sidebar-tools-button')
      .accessibilityText(RemoteI18n.t('workspaceTools.title'))
      .stateEffect(true)
      .onClick(() => this.onOpenTools())
      Blank()
      Button() {
        TemplateIcon({ src: $r('app.media.ic_sidebar_settings'),
          iconWidth: MobileDesignGeometry.sidebarFooterIconSize,
          iconHeight: MobileDesignGeometry.sidebarFooterIconSize, tint: SIDEBAR_MUTED })
      }
      .width(SidebarLayoutPolicy.FOOTER_SETTINGS_SIZE)
      .height(SidebarLayoutPolicy.FOOTER_SETTINGS_SIZE)
      .padding(0)
      .backgroundColor(TRANSPARENT)
      .border({ width: 0, color: TRANSPARENT })
      .borderRadius(10)
      .id('sidebar-settings-button')
      .accessibilityText(RemoteI18n.t('settings.title'))
      .stateEffect(true)
      .onClick(() => this.onOpenSettings())
    }
    .width('100%')
    .height(SidebarLayoutPolicy.FOOTER_HEIGHT)
    .padding({ left: SidebarLayoutPolicy.FOOTER_PADDING, right: 0 })
    .backgroundColor(SIDEBAR_BG)
    .border({ width: { top: 0.5 }, color: SIDEBAR_LINE })
    .alignItems(VerticalAlign.Center)
    .zIndex(2)
  }
}
