import { LocalGenUICollaborationPicker } from '../components/LocalGenUICollaborationPicker';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { INK, MUTED, PAGE_BG } from '../components/Theme';

/** Real SDK probe, not simulated devices or a fake transfer. */
@ComponentV2
export struct CollaborationPreview {
  @Local generation: number = 0;
  @Local compact: boolean = false;

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text(RemoteI18n.t('collaboration.title')).fontColor(INK)
          .fontSize(MobileDesignTypography.titleLarge.size)
        Text(RemoteI18n.t('collaboration.emulatorNotice')).fontColor(MUTED)
          .fontSize(MobileDesignTypography.bodyMedium.size)
        ForEach([this.generation], (_generation: number) => {
          LocalGenUICollaborationPicker()
        }, (generation: number) => String(generation))
        Button(RemoteI18n.t('collaboration.reset')).id('collaboration-reset')
          .onClick(() => { this.generation += 1; })
        Button(RemoteI18n.t('collaboration.resize')).id('collaboration-resize')
          .onClick(() => { this.compact = !this.compact; })
        Text(RemoteI18n.t('collaboration.resetNotice')).fontColor(MUTED)
          .fontSize(MobileDesignTypography.labelSmall.size)
      }.padding({ top: 64, left: 20, right: 20, bottom: 40 })
        .width(this.compact ? 340 : '100%').constraintSize({ maxWidth: 840 })
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
