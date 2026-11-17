import { SettingsSectionTitle } from './SettingsSectionTitle';
import { TemplateIcon } from './TemplateIcon';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { CARD, INK, LINE, MUTED, SOFT, STATUS_DANGER } from './Theme';

/**
 * Current control target card on the single settings page. Legacy room
 * targets stay readable and can still be disconnected; only the account
 * device directory creates new targets.
 */
@ComponentV2
export struct CurrentControlSection {
  @Param desktopName: string = '';
  @Param desktopId: string = '';
  @Param controlTargetType: string = 'none';
  @Param connectionState: string = 'idle';
  @Param statusText: string = '';
  @Event onDisconnect: () => void = () => {};
  @Event onClearPairing: () => void = () => {};
  @Event onReconnect: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      if (this.hasControlTarget()) {
        SettingsSectionTitle({ title: RemoteI18n.t('remote.settings.currentControl') })
        this.Card()
      }
    }
    .width('100%')
  }

  @Builder
  private Card() {
    Column() {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          TemplateIcon({ src: $r('app.media.sidebar_device_desktop'),
            iconWidth: MobileDesignGeometry.settingsIconSize, iconHeight: MobileDesignGeometry.settingsIconSize, tint: MUTED })
        }
        .width(18)
        .height(18)

        Column({ space: 3 }) {
          Text(this.connectionTitle())
            .fontSize(MobileDesignTypography.bodyMedium.size)
            .fontWeight(FontWeight.Medium)
            .fontColor(INK)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.connectionDetail())
            .fontSize(MobileDesignTypography.bodySmall.size)
            .fontColor(MUTED)
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ minHeight: MobileDesignGeometry.settingsDetailRowHeight })
      .padding({ left: MobileDesignGeometry.settingsRowPadding, right: MobileDesignGeometry.settingsRowPadding, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.hasControlTarget()) {
        Divider().strokeWidth(0.5).color(LINE).margin({ left: MobileDesignGeometry.settingsRowPadding, right: MobileDesignGeometry.settingsRowPadding })

        Row({ space: 8 }) {
          Text(this.connectionSourceLabel())
            .fontSize(MobileDesignTypography.bodySmall.size)
            .fontColor(MUTED)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(SOFT)
            .borderRadius(12)
          Blank()
          // Same rule as Android and iOS: one action. A link that is up or coming
          // up can be left; once it is down, re-binding the selection is the offer.
          // A legacy room can only be cleared, whatever its link state.
          if (this.controlTargetType === 'account_device' && !this.isConnectedOrConnecting()) {
            Text(RemoteI18n.t('remote.settings.reconnect'))
              .fontSize(MobileDesignTypography.bodyMedium.size)
              .fontWeight(FontWeight.Medium)
              .fontColor(INK)
              .constraintSize({ minHeight: MobileDesignGeometry.controlTouchSize })
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .onClick(() => this.onReconnect())
          } else {
            Text(this.controlTargetType === 'room' ?
              RemoteI18n.t('remote.settings.disconnectTemporary') :
              RemoteI18n.t('remote.settings.disconnect'))
              .fontSize(MobileDesignTypography.bodyMedium.size)
              .fontWeight(FontWeight.Medium)
              .fontColor(STATUS_DANGER)
              .constraintSize({ minHeight: MobileDesignGeometry.controlTouchSize })
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .onClick(() => {
                if (this.controlTargetType === 'room') {
                  this.onClearPairing();
                } else {
                  this.onDisconnect();
                }
              })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: MobileDesignGeometry.settingsRowHeight })
        .padding({ left: 18, right: 10 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .backgroundColor(CARD)
    .borderRadius(MobileDesignGeometry.settingsGroupRadius)
    .border({ width: 0.5, color: LINE })
    .margin({ bottom: MobileDesignGeometry.settingsSectionGap })
  }

  private hasControlTarget(): boolean {
    return this.controlTargetType === 'room' || this.controlTargetType === 'account_device';
  }

  private isConnectedOrConnecting(): boolean {
    return this.connectionState === 'connected' || this.connectionState === 'reconnecting' ||
      this.connectionState === 'pairing' || this.connectionState === 'parsing';
  }

  private connectionTitle(): string {
    return this.desktopName || this.desktopId || RemoteI18n.t('remote.settings.noDesktop');
  }

  private connectionDetail(): string {
    if (this.connectionState === 'connected') {
      return RemoteI18n.t('connection.connected');
    }
    if (this.connectionState === 'reconnecting') {
      return RemoteI18n.t('connection.reconnecting');
    }
    return this.statusText || RemoteI18n.t('connection.disconnected');
  }

  private connectionSourceLabel(): string {
    return this.controlTargetType === 'room' ? RemoteI18n.t('remote.settings.qrPairing') :
      RemoteI18n.t('remote.settings.accountDevice');
  }
}
