import { MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { HarnessProfileMenu } from './HarnessProfileMenu';
import { SidebarGlyph } from './SidebarGlyphs';
import { CARD, INK, LINE, MUTED, SHADOW_SUBTLE, TRANSPARENT } from './Theme';

/** Workspace context actions share the existing creation intents and profile choices. */
@ComponentV2
export struct WorkspaceSessionMenu {
  @Param assistant: boolean = false;
  @Event onSelect: (agentType: string) => void = (_agentType: string) => {};

  build() {
    Column() {
      if (this.assistant) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            SidebarGlyph({ kind: 'assistant', iconSize: 18, tint: MUTED })
            Text(RemoteI18n.t('remote.startSession'))
              .fontSize(MobileDesignTypography.titleSmall.size)
              .fontColor(INK)
          }
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
        }
        .width('100%').height(46).padding({ left: 14, right: 14 })
        .backgroundColor(TRANSPARENT).borderRadius(10)
        .accessibilityText(RemoteI18n.t('remote.startSession'))
        .onClick(() => this.onSelect('claw'))
      } else {
        Text(RemoteI18n.t('remote.startSession'))
          .fontSize(MobileDesignTypography.labelSmall.size)
          .fontColor(MUTED)
          .width('100%').height(28).padding({ left: 14, right: 14 })
        HarnessProfileMenu({ embedded: true, showTitle: false, onSelect: this.onSelect })
      }
    }
    .width(160)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(CARD)
    .borderRadius(16)
    .border({ width: 0.5, color: LINE })
    .shadow({ radius: 10, color: SHADOW_SUBTLE, offsetY: 3 })
    .transition(TransitionEffect.opacity(0).animation({ duration: 150, curve: Curve.EaseOut }))
  }
}
