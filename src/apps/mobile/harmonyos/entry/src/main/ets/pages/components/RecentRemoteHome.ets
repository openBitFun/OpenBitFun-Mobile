import { WelcomePhrase } from './WelcomePhrase';
import { WorkspacePathPresentation } from '../policy/WorkspacePathPresentation';
import { ColdStartPresentationState } from '../state/ColdStartPresentationState';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { WelcomeBrandFlow } from './WelcomeBrandFlow';
import { CompactMenuButton } from './CompactMenuButton';
import { RemoteCompactHomePolicy } from '../policy/RemoteCompactHomePolicy';
import { RemoteSession } from '../../model/RemoteModels';
import { INK, MUTED, SOFT, LINE, TRANSPARENT } from './Theme';

/** Current-device landing page. Session activation stays with the remote owner. */
@ComponentV2
export struct RecentRemoteHome {
  @Consumer() coldStartGeometry: ColdStartPresentationState = new ColdStartPresentationState();
  @Local viewportHeight: number = 0;
  @Param connected: boolean = false;
  @Param busy: boolean = false;
  @Param sessions: RemoteSession[] = [];
  @Param desktopName: string = '';
  @Param showSidebarButton: boolean = false;
  @Event onOpen: (session: RemoteSession) => void = () => {};
  @Event onBrowse: () => void = () => {};
  @Event onConnect: () => void = () => {};

  // Keyed rows keep their identity; resolve their content from the latest snapshot.
  @Computed
  get sessionIndex(): Map<string, RemoteSession> {
    const index = new Map<string, RemoteSession>();
    this.sessions.forEach((item: RemoteSession) => { index.set(`${item.deviceId || ''}:${item.id}`, item); });
    return index;
  }

  private currentSession(item: RemoteSession): RemoteSession {
    return this.sessionIndex.get(`${item.deviceId || ''}:${item.id}`) || item;
  }

  private sessionContext(session: RemoteSession): string {
    return WorkspacePathPresentation.label(session.workspacePath || '', session.workspaceIdentity,
      session.workspaceName || '');
  }

  aboutToDisappear(): void { this.coldStartGeometry.targetSize = 0; }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          Column() {
          WelcomeBrandFlow({ markSize: MobileDesignGeometry.recentHomeMarkSize, sweep: true })
            .onAreaChange((_old: Area, area: Area) => {
              this.coldStartGeometry.targetX = Number(area.globalPosition.x) + Number(area.width) / 2;
              this.coldStartGeometry.targetY = Number(area.globalPosition.y) + Number(area.height) / 2;
              this.coldStartGeometry.targetSize = Number(area.width);
            })
            .margin({ top: 0, bottom: MobileDesignGeometry.recentHomeHeroGap })
          WelcomePhrase({ fontSize: MobileDesignGeometry.recentHomeTitleSize,
            longWordFontSize: MobileDesignGeometry.recentHomeTitleSize, stageHeight: MobileDesignGeometry.recentHomePhraseStageHeight })
          }.width('100%').margin({ bottom: MobileDesignGeometry.recentHomeHeroBottom })
        if (this.busy) {
          LoadingProgress().width(24).height(24).color(MUTED).margin({ bottom: 16 })
        }
        if (!RemoteCompactHomePolicy.shouldShowRecentSessions(this.connected)) {
          Text(RemoteI18n.t('home.recent_connect')).fontSize(MobileDesignTypography.bodySmall.size).fontColor(MUTED).margin({ bottom: 16 })
          Button(RemoteI18n.t('home.connectComputer')).onClick(this.onConnect)
            .backgroundColor(SOFT).fontColor(INK).height(48).width('100%').margin({ bottom: 16 })
        }
        if (RemoteCompactHomePolicy.shouldShowRecentSessions(this.connected)) {
          Row() {
            Text(RemoteI18n.t('home.recent_recent')).fontSize(MobileDesignTypography.labelSmall.size)
              .lineHeight(MobileDesignTypography.labelSmall.lineHeight).fontColor(MUTED).layoutWeight(1)
            Button(RemoteI18n.t('home.recent_all')).fontSize(MobileDesignTypography.bodyMedium.size)
              .fontWeight(FontWeight.Medium).fontColor(INK)
              .backgroundColor(TRANSPARENT).height(44).padding({ left: 4, right: 4 }).onClick(this.onBrowse)
          }.width('100%').margin({ bottom: 8 })
          ForEach(this.sessions, (row: RemoteSession) => {
            if (this.sessions[0]?.id !== row.id || this.sessions[0]?.deviceId !== row.deviceId) {
              Divider().color(LINE).margin({ left: 12, right: 12 })
            }
            Column({ space: 4 }) {
              Text(this.currentSession(row).title).fontSize(MobileDesignTypography.titleSmall.size).lineHeight(MobileDesignTypography.titleSmall.lineHeight)
                .fontWeight(FontWeight.Medium).fontColor(INK).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Text(this.sessionContext(this.currentSession(row))).fontSize(MobileDesignTypography.bodySmall.size).lineHeight(MobileDesignTypography.bodySmall.lineHeight).fontColor(MUTED).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
              .padding({ top: MobileDesignGeometry.recentHomeRowPadding, bottom: MobileDesignGeometry.recentHomeRowPadding, left: 12, right: 12 })
              .onClick(() => { if (this.connected) this.onOpen(this.currentSession(row)); })
              .accessibilityGroup(true).accessibilityText(`${this.currentSession(row).title}, ${this.sessionContext(this.currentSession(row))}`)
          }, (session: RemoteSession): string => `${session.deviceId || ''}:${session.id}`)
          if (this.sessions.length === 0 && !this.busy) {
            Text(RemoteI18n.t('home.recent_empty')).fontSize(MobileDesignTypography.bodySmall.size).fontColor(MUTED)
              .padding({ top: 18, bottom: 18 })
          }
        }

        }.alignItems(HorizontalAlign.Start).width('100%')
          .constraintSize({ minHeight: this.viewportHeight, maxWidth: MobileDesignGeometry.recentHomeMaxWidth })
          .justifyContent(FlexAlign.Center)
          .padding({ left: MobileDesignGeometry.recentHomeGutter, right: MobileDesignGeometry.recentHomeGutter,
            top: MobileDesignGeometry.recentHomeTopPadding, bottom: 28 })
      }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
        .onAreaChange((_old: Area, area: Area) => { this.viewportHeight = Number(area.height); })
      if (this.showSidebarButton) {
        CompactMenuButton({
          controlSize: MobileDesignGeometry.controlTouchSize,
          onOpen: this.onBrowse
        })
          .position({ x: 8, y: 8 })
      }
    }.width('100%').height('100%')
  }
}
