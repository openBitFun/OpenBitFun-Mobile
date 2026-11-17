import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MUTED, TRANSPARENT } from './Theme';

@ComponentV2
export struct SidebarToggleButton {
  @Param restore: boolean = false;
  @Param controlSize: number = 44;
  @Event onToggle: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Text('')
          .width(6)
          .height(16)
          .backgroundColor(MUTED)
          .opacity(0.18)
          .borderRadius({ topLeft: 2, bottomLeft: 2 })
        Divider()
          .vertical(true)
          .height(16)
          .color(MUTED)
          .opacity(0.7)
        Blank()
          .layoutWeight(1)
      }
      .width(22)
      .height(20)
      .padding({ left: 2, right: 2 })
      .alignItems(VerticalAlign.Center)
      .border({ width: 1.5, color: MUTED })
      .borderRadius(4)
    }
    .width(this.controlSize)
    .height(this.controlSize)
    .backgroundColor(TRANSPARENT)
    .borderRadius(8)
    .accessibilityText(RemoteI18n.t(this.restore ? 'sidebar.restore' : 'sidebar.collapse'))
    .onClick(() => {
      this.onToggle();
    })
  }
}
