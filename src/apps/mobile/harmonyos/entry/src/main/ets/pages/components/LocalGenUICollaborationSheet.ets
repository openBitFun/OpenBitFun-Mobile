import { LocalCollaborationRequest } from '../../services/local-genui/LocalGenUICollaborationHost';
import { LocalCollaborationSnapshot } from '../../services/local-genui/LocalCollaborationSession';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { LocalGenUICollaborationPicker } from './LocalGenUICollaborationPicker';
import { MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { INK, PAGE_BG } from './Theme';

@ComponentV2
export struct LocalGenUICollaborationSheet {
  @Param @Require request: LocalCollaborationRequest;
  @Event onClose: (token: number) => void = () => {};
  @Event onResult: (token: number, state: LocalCollaborationSnapshot) => void = () => {};
  @Param @Require receive: (token: number, data: ArrayBuffer) => Promise<void>;

  aboutToDisappear(): void { this.onClose(this.request.token); }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text(RemoteI18n.t('collaboration.inputTitle')).fontColor(INK)
          .fontSize(MobileDesignTypography.titleLarge.size)
        LocalGenUICollaborationPicker({ kind: this.request.kind, diagnostic: false,
          persist: (data: ArrayBuffer): Promise<void> => this.receive(this.request.token, data),
          onResult: (state: LocalCollaborationSnapshot): void => this.onResult(this.request.token, state) })
        Button(RemoteI18n.t('collaboration.closeInput')).onClick(() => this.onClose(this.request.token))
      }.width('100%').constraintSize({ maxWidth: 760 }).padding(20)
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
