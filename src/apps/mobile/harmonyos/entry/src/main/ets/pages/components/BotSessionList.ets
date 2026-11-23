import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { LocalGenUISession } from '../../services/local-genui/LocalGenUIModels';
import { INK, LINE, MUTED, SIDEBAR_SELECTION, TRANSPARENT } from './Theme';

/**
 * The saved conversations on the Bot sessions page.
 */
@ComponentV2
export struct BotSessionList {
  @Param sessions: LocalGenUISession[] = [];
  @Param selectedSessionId: string = '';
  @Param busy: boolean = false;
  @Event onOpenSession: (sessionId: string) => void = (_sessionId: string) => {};
  @Event onDeleteSession: (sessionId: string) => void = (_sessionId: string) => {};
  @Local actionSessionId: string = '';

  build() {
    Column() {
      if (this.sessions.length === 0) {
        Text(RemoteI18n.t('localGenui.noHistory'))
          .fontSize(MobileDesignTypography.bodyMedium.size)
          .fontColor(MUTED)
          .textAlign(TextAlign.Center)
          .width('100%').padding({ top: 24, bottom: 24 })
      }
      ForEach(this.sessions, (session: LocalGenUISession, index: number) => {
        if (index > 0) {
          Divider().strokeWidth(0.5).color(LINE).margin({ left: MobileDesignGeometry.genuiHistoryHorizontalInset,
            right: MobileDesignGeometry.genuiHistoryHorizontalInset })
        }
        this.SessionRow(session)
      }, (session: LocalGenUISession): string => `${session.id}:${session.title}:${session.updatedAt}`)
    }.width('100%')
  }

  @Builder
  private SessionRow(session: LocalGenUISession) {
    Row({ space: 10 }) {
      Column({ space: MobileDesignGeometry.genuiHistoryLabelSpacing }) {
        Text(session.title || RemoteI18n.t('sidebar.untitled'))
          .fontSize(MobileDesignTypography.bodyMedium.size)
          .fontWeight(session.id === this.selectedSessionId ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(INK).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.updatedTime(session).length > 0) {
          Text(this.updatedTime(session)).fontSize(MobileDesignTypography.labelSmall.size).fontColor(MUTED)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.busy && session.id === this.selectedSessionId) {
        LoadingProgress().width(16).height(16)
      } else if (session.id === this.selectedSessionId) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([INK])
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([MUTED])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: MobileDesignGeometry.genuiHistoryRowHeight })
    .padding({ left: MobileDesignGeometry.genuiHistoryHorizontalInset, right: MobileDesignGeometry.genuiHistoryHorizontalInset,
      top: MobileDesignGeometry.genuiHistoryVerticalInset, bottom: MobileDesignGeometry.genuiHistoryVerticalInset })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(session.id === this.selectedSessionId ? SIDEBAR_SELECTION : TRANSPARENT)
    .borderRadius(MobileDesignGeometry.genuiHistoryRowRadius)
    .accessibilityText(session.title)
    .accessibilitySelected(session.id === this.selectedSessionId)
    .onClick(() => {
      if (!this.busy || session.id === this.selectedSessionId) this.onOpenSession(session.id);
    })
    .bindPopup(this.actionSessionId === session.id, {
      builder: (): void => this.SessionActions(session),
      placement: Placement.Bottom,
      enableArrow: false,
      targetSpace: MobileDesignGeometry.genuiHistoryMenuGap,
      onStateChange: (event) => {
        if (!event.isVisible && this.actionSessionId === session.id) this.actionSessionId = '';
      }
    })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.actionSessionId = session.id;
    }))
  }

  private updatedTime(session: LocalGenUISession): string {
    const timestamp = Date.parse(session.updatedAt || session.createdAt);
    return Number.isFinite(timestamp) ? RemoteI18n.formatMessageTime(timestamp) : '';
  }

  @Builder
  private SessionActions(session: LocalGenUISession) {
    Column() {
      Text(RemoteI18n.t('common.delete'))
        .fontSize(MobileDesignTypography.bodyMedium.size)
        .fontColor(INK)
        .constraintSize({ minHeight: MobileDesignGeometry.genuiHistoryMenuHeight })
        .padding({ left: MobileDesignGeometry.genuiHistoryActionInset, right: MobileDesignGeometry.genuiHistoryActionInset })
        .onClick(() => {
          this.actionSessionId = '';
          this.onDeleteSession(session.id);
        })
    }
  }
}
