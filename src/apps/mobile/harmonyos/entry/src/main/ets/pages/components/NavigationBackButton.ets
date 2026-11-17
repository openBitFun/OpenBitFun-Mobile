import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MobileDesignGeometry } from '../../generated/MobileDesignTokens';
import { TemplateIcon } from './TemplateIcon';
import { TRANSPARENT } from './Theme';

/** App-wide floating page return affordance. */
@ComponentV2
export struct NavigationBackButton {
  @Param controlSize: number = 48;
  @Param isEnabled: boolean = true;
  @Event onBack: () => void = () => {};

  build() {
    Button() {
      TemplateIcon({
        src: $r('app.media.remote_ref_back'),
        iconWidth: MobileDesignGeometry.navigationBackIconSize * 15 / 23,
        iconHeight: MobileDesignGeometry.navigationBackIconSize
      })
    }
    .width(this.controlSize)
    .height(this.controlSize)
    .padding(0)
    .backgroundColor(TRANSPARENT)
    .borderRadius(12)
    .stateEffect(true)
    .opacity(this.isEnabled ? 1 : 0.4)
    .enabled(this.isEnabled)
    .accessibilityText(RemoteI18n.t('common.back'))
    .onClick(() => {
      this.onBack();
    })
  }
}
