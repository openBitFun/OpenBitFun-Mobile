import { CollaborationDeviceFilterType, CollaborationServiceFilter, createCollaborationServiceMenuItems,
  CollaborationServiceStateDialog } from '@kit.ServiceCollaborationKit';
import { image } from '@kit.ImageKit';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { HarmonyCollaborationService, HarmonyCollaborationEnvironment } from '../../services/local-genui/HarmonyCollaborationService';
import { LocalCollaborationKind, LocalCollaborationSnapshot } from '../../services/local-genui/LocalCollaborationSession';
import { INK, MUTED, CARD } from './Theme';

/** Platform leaf: the OS owns device discovery, selection and remote consent. */
@ComponentV2
export struct LocalGenUICollaborationPicker {
  @Param kind: string = '';
  @Param diagnostic: boolean = true;
  @Param persist: ((data: ArrayBuffer) => Promise<void>) | undefined = undefined;
  @Event onResult: (state: LocalCollaborationSnapshot) => void = () => {};
  @Local environment: HarmonyCollaborationEnvironment = HarmonyCollaborationService.environment();
  @Local status: LocalCollaborationSnapshot = { phase: 'ready', kind: 'photo', received: 0, code: 0, reason: '' };
  @Local picture: image.PixelMap | undefined = undefined;
  private service?: HarmonyCollaborationService;

  aboutToAppear(): void {
    this.service = new HarmonyCollaborationService((state: LocalCollaborationSnapshot): void => {
      this.status = state;
      this.onResult(state);
    }, (picture: image.PixelMap | undefined): void => { this.picture = picture; }, this.persist);
    if (this.environment.unavailable.length > 0) {
      this.service.session.begin('photo', this.environment.unavailable);
    }
  }

  aboutToDisappear(): void {
    this.service?.dispose();
    this.service = undefined;
  }

  private begin(kind: LocalCollaborationKind): void {
    this.service?.session.begin(kind, this.environment.unavailable);
  }

  @Builder
  private photoMenu() {
    Menu() {
      if (this.environment.api >= 23) {
        createCollaborationServiceMenuItems([CollaborationServiceFilter.TAKE_PHOTO], 1,
          [CollaborationDeviceFilterType.PHONE, CollaborationDeviceFilterType.TABLET])
      }
    }
  }

  @Builder
  private scanMenu() {
    Menu() {
      if (this.environment.api >= 23) {
        createCollaborationServiceMenuItems([CollaborationServiceFilter.SCAN_DOCUMENT], 1,
          [CollaborationDeviceFilterType.PHONE, CollaborationDeviceFilterType.TABLET])
      }
    }
  }

  @Builder
  private galleryMenu() {
    Menu() {
      if (this.environment.api >= 23) {
        createCollaborationServiceMenuItems([CollaborationServiceFilter.IMAGE_PICKER], 1,
          [CollaborationDeviceFilterType.PHONE, CollaborationDeviceFilterType.TABLET, CollaborationDeviceFilterType.PC_2IN1])
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      Text(RemoteI18n.t('collaboration.requirements')).fontColor(MUTED)
        .fontSize(MobileDesignTypography.bodyMedium.size)
      if (this.diagnostic) {
        Text(`API ${this.environment.api} · ${this.environment.deviceType} · SysCap ${this.environment.syscap}`)
          .id('collaboration-environment').fontColor(MUTED).fontSize(MobileDesignTypography.labelSmall.size)
      }
      if (this.environment.unavailable.length === 0) {
        if (this.kind === '' || this.kind === 'photo') {
        Button(RemoteI18n.t('collaboration.photo')).id('collaboration-photo')
          .enabled(this.status.phase === 'ready').onClick(() => this.begin('photo')).bindMenu(this.photoMenu)
        }
        if (this.kind === '' || this.kind === 'scan') {
        Button(RemoteI18n.t('collaboration.scan')).id('collaboration-scan')
          .enabled(this.status.phase === 'ready').onClick(() => this.begin('scan')).bindMenu(this.scanMenu)
        }
        if (this.kind === '' || this.kind === 'gallery') {
        Button(RemoteI18n.t('collaboration.gallery')).id('collaboration-gallery')
          .enabled(this.status.phase === 'ready').onClick(() => this.begin('gallery')).bindMenu(this.galleryMenu)
        }
        CollaborationServiceStateDialog({
          onState: (code: number, type: string, buffer: ArrayBuffer): void => {
            void this.service?.session.accept(code, type, buffer);
          }
        })
      }
      Text(RemoteI18n.t(`collaboration.phase.${this.status.phase}`))
        .id('collaboration-status').fontColor(INK).fontSize(MobileDesignTypography.bodyMedium.size)
      if (this.status.reason.length > 0) {
        Text(RemoteI18n.t(`collaboration.reason.${this.status.reason}`))
          .id('collaboration-reason').fontColor(MUTED).fontSize(MobileDesignTypography.bodyMedium.size)
      }
      if (this.diagnostic) {
        Text(RemoteI18n.f2('collaboration.result', String(this.status.received), String(this.status.code)))
          .id('collaboration-result').fontColor(MUTED).fontSize(MobileDesignTypography.labelSmall.size)
      }
      if (this.picture) {
        Image(this.picture).width('100%').height(240).objectFit(ImageFit.Contain)
          .accessibilityText(RemoteI18n.t('collaboration.receivedImage'))
      }
    }.width('100%').padding(16).backgroundColor(CARD).borderRadius(16)
  }
}
