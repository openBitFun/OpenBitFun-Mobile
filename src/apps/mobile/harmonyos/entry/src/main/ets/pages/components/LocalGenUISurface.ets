import { KeyboardAvoidMode } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import { LocalGenUIPresentation } from '../../services/local-genui/LocalGenUIModels';
import { LocalGenUIRuntimeBridge } from '../../services/local-genui/LocalGenUIRuntimeBridge';
import { WindowInsetsBinding } from '../../services/WindowSystemBarService';
import { LocalGenUIActions, LocalGenUIState, emptyLocalGenUIActions } from '../state/LocalGenUIState';
import { ConversationIntent, ConversationIntentType } from '../actions/ConversationIntent';
import { ConversationViewState } from '../state/ConversationViewState';
import { ConversationViewHost } from './ConversationViewHost';
import { BotSessionList } from './BotSessionList';
import { AppActionButton, AppActionStyle } from './AppActionButton';
import { LocalGenUICameraPreview } from './LocalGenUICameraPreview';
import { LocalGenUICollaborationSheet } from './LocalGenUICollaborationSheet';
import { LocalCollaborationRequest } from '../../services/local-genui/LocalGenUICollaborationHost';
import { LocalCollaborationSnapshot } from '../../services/local-genui/LocalCollaborationSession';
import { LocalGenUIModelManager } from './LocalGenUIModelManager';
import { LocalGenUIWebSurface } from './LocalGenUIWebSurface';
import { NavigationBackButton } from './NavigationBackButton';
import { TemplateIcon } from './TemplateIcon';
import { CONTENT_ON_ACTION, FLOATING_PANEL_BG, INK, PAGE_BG, SHADOW_SUBTLE, TOAST_BACKGROUND } from './Theme';

/** Component the launcher snapshots for the add-to-desktop animation. */
const APP_BODY_ID: string = 'local-genui-app-body';

const WIDE_BREAKPOINT: number = 600;

/**
 * Local GenUI page. It lives in the moving content pane like a remote
 * conversation: the sidebar opens over it, and remote destinations close it.
 */
@ComponentV2
export struct LocalGenUISurface {
  @Param state: LocalGenUIState = new LocalGenUIState();
  @Param actions: LocalGenUIActions = emptyLocalGenUIActions();
  @Param @Require bridge: LocalGenUIRuntimeBridge;
  @Param locale: string = 'zh-CN';
  @Event onPresentation: (report: LocalGenUIPresentation) => void = () => {};
  @Local insets: WindowInsetsBinding = new WindowInsetsBinding();
  @Local scheme: string = 'light';
  @Local bodyWidth: number = 0;
  @Local rootWidth: number = 0;
  @Local rootHeight: number = 0;
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToAppear(): void {
    // The composer sits at the bottom; resize so the header stays on screen.
    this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.actions.appOnScreen(this.showsApp());
    const context = this.getUIContext().getHostContext();
    if (context) {
      this.insets.bind(this.getUIContext(), context);
      try {
        const colorMode = context.resourceManager.getConfigurationSync().colorMode;
        this.scheme = colorMode === resourceManager.ColorMode.DARK ? 'dark' : 'light';
      } catch (_err) {
        this.scheme = 'light';
      }
    }
  }

  aboutToDisappear(): void {
    this.actions.appOnScreen(false);
    this.insets.unbind();
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
  }

  private report(): void {
    this.onPresentation({
      posture: this.rootWidth >= WIDE_BREAKPOINT ? 'wide' : 'compact',
      deviceWidth: Math.round(this.rootWidth),
      deviceHeight: Math.round(this.rootHeight),
      safeTop: Math.round(this.insets.top),
      safeBottom: Math.round(this.insets.bottom),
      // The runtime page fills the device width; it is never scaled.
      viewportScale: 1
    });
  }

  /** Device capabilities run only while the app pane is the visible one. */
  @Monitor('state.view', 'state.appId')
  onAppVisibilityChanged(): void {
    this.actions.appOnScreen(this.showsApp());
  }

  private statusText(status: string): string {
    return status.length > 0 ? RemoteI18n.t(`localGenui.status.${status}`) : '';
  }

  /** A missing app (e.g. opened from a stale desktop card) says so, not "unsupported". */
  private statusLine(): string {
    if (this.state.appStreaming) return RemoteI18n.t('localGenui.generating');
    if (this.state.appStatus === 'unsupported' && this.state.appTitle.length === 0 && this.state.appDetail.length > 0) {
      return this.state.appDetail;
    }
    return this.statusText(this.state.appStatus);
  }

  private showsApp(): boolean {
    return this.state.view === 'app' && this.state.appId.length > 0;
  }

  private hidesRuntime(): boolean {
    return this.state.appStatus === 'failed' || this.state.appStatus === 'unsupported';
  }

  /** The conversation pane is the shared remote/general ConversationView. */
  private conversationState(): ConversationViewState {
    return ConversationViewState.local(this.state.conversation, '');
  }

  private onConversationIntent(intent: ConversationIntent): void {
    if (intent.type === ConversationIntentType.OpenBotHistory) {
      this.actions.showSessions();
      return;
    }
    this.actions.conversation(intent);
  }

  /** The page runs under the floating controls; tell it how much to keep clear. */
  private syncPageInsets(): void {
    const chrome = this.showsApp() ? MobileDesignGeometry.genuiAppControlTopInset + MobileDesignGeometry.genuiAppControlSize : 0;
    this.bridge.setInsets(this.insets.top + chrome, this.insets.left, this.insets.right, this.insets.bottom);
  }

  @Monitor('insets.top', 'insets.left', 'insets.right', 'insets.bottom', 'state.view', 'state.appId')
  onInsetsChanged(): void {
    this.syncPageInsets();
  }

  private goBack(): void {
    if (this.state.standalone) this.actions.close();
    else this.actions.showChat();
  }

  /** Only states the person must act on or wait for are shown over the app. */
  private floatingStatus(): string {
    if (this.state.appStatus === 'recovering') return RemoteI18n.t('localGenui.recovering');
    if (this.state.appStreaming) return RemoteI18n.t('localGenui.generating');
    if (this.state.appStatus === 'failed' || this.state.appStatus === 'unsupported' || this.state.appStatus === 'state_migration_required') {
      return this.statusLine();
    }
    return '';
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Each sheet has its own binding node.
      Column() {}
        .width(0).height(0)
        .bindSheet($$this.state.showCollaboration, this.CollaborationSheet(), {
          height: SheetSize.LARGE, showClose: true, backgroundColor: PAGE_BG
        })
      // The runtime stays mounted while the page is open so local acceptance
      // can probe it even when the conversation is in front. It runs edge to
      // edge; the page keeps its content clear of the reported insets.
      LocalGenUIWebSurface({ bridge: this.bridge, scheme: this.scheme, locale: this.locale })
        .id(APP_BODY_ID)
        .width('100%')
        .height('100%')
        // A terminal failure uses the native status, even if the last Web
        // frame still contains a checker diagnostic after unmounting.
        .opacity(this.hidesRuntime() ? 0 : 1)
        .hitTestBehavior(this.hidesRuntime() ? HitTestMode.None : HitTestMode.Default)
        .accessibilityLevel(this.hidesRuntime() ? 'no-hide-descendants' : 'auto')
        .onAreaChange((_old: Area, next: Area) => {
          this.bodyWidth = Number(next.width);
          this.report();
          this.syncPageInsets();
        })

      if (this.showsApp()) {
        this.FloatingControls()
      }

      if (this.showsApp() && this.state.cameraWanted) {
        LocalGenUICameraPreview({
          active: this.state.cameraActive,
          compact: this.rootHeight > 0 && this.rootHeight < MobileDesignGeometry.genuiCameraCompactHeightThreshold,
          landscape: this.rootWidth > this.rootHeight && this.rootWidth > 0,
          onSurface: (surfaceId: string) => this.actions.cameraSurface(surfaceId),
          onSurfaceGone: () => this.actions.cameraSurfaceGone()
        })
        .position({
          right: this.insets.rightPadding(MobileDesignGeometry.genuiCameraSideInset),
          bottom: this.insets.bottom + MobileDesignGeometry.genuiCameraBottomInset
        })
      }

      if (this.state.view === 'sessions') {
        this.SessionsPage()
      } else if (!this.showsApp()) {
        ConversationViewHost({
          viewState: this.conversationState(),
          showSidebarButton: false,
          showBackButton: true,
          onIntent: (intent: ConversationIntent) => this.onConversationIntent(intent)
        })
        .width('100%').height('100%')
      }
      if (this.state.notice.length > 0) {
        Text(this.state.notice)
          .fontSize(MobileDesignTypography.bodySmall.size).fontColor(CONTENT_ON_ACTION)
          .backgroundColor(TOAST_BACKGROUND).borderRadius(16).padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ top: 72 + this.insets.top, left: 24, right: 24 })
          .copyOption(CopyOptions.InApp)
      }
    }
    .width('100%').height('100%').backgroundColor(PAGE_BG)
    .bindSheet($$this.state.showModelManager, this.ModelManagerSheet(), {
      height: SheetSize.LARGE, showClose: false, backgroundColor: PAGE_BG,
      onWillDismiss: (action: DismissSheetAction): void => {
        if (!this.state.editorSaving) action.dismiss();
      },
      onDisappear: () => this.actions.closeModelManager()
    })
    .onAreaChange((_old: Area, next: Area) => {
      this.rootWidth = Number(next.width);
      this.rootHeight = Number(next.height);
      this.report();
    })
  }

  @Builder
  private SessionsPage() {
    Column() {
      Row() {
        NavigationBackButton({ onBack: () => { this.actions.back(); } })
        Text(RemoteI18n.t('localGenui.entry'))
          .fontSize(MobileDesignTypography.conversationHeaderTitle.size)
          .fontWeight(FontWeight.Medium).fontColor(INK).textAlign(TextAlign.Center).layoutWeight(1)
        Blank().width(48)
      }.width('100%').height(56)
        .padding({ left: this.insets.leftPadding(8), right: this.insets.rightPadding(8) })
      Scroll() {
        Column() {
          if (this.state.loading) {
            LoadingProgress().width(28).height(28).margin(24)
          } else if (this.state.error.length > 0) {
            Text(this.state.error).fontSize(MobileDesignTypography.bodyMedium.size).fontColor(INK)
              .padding(16)
          } else {
            BotSessionList({
              sessions: this.state.localSessions,
              selectedSessionId: this.state.sessionId,
              busy: this.state.conversation.isBusy,
              onOpenSession: (id: string): void => this.actions.openSession(id),
              onDeleteSession: (id: string): void => this.actions.deleteSession(id)
            })
          }
        }.width('100%').constraintSize({ maxWidth: MobileDesignGeometry.sheetContentMaxWidth })
      }.width('100%').layoutWeight(1).align(Alignment.Top)
        .padding({ left: this.insets.leftPadding(MobileDesignGeometry.genuiHistoryHorizontalInset),
          right: this.insets.rightPadding(MobileDesignGeometry.genuiHistoryHorizontalInset), top: MobileDesignGeometry.genuiHistoryVerticalInset })
        .scrollBar(BarState.Auto)
      Column() {
        AppActionButton({
          label: RemoteI18n.t('localGenui.newSession'),
          style: AppActionStyle.Primary,
          elevated: false,
          isEnabled: !this.state.loading && !this.state.conversation.isBusy,
          onAction: (): void => this.actions.newSession()
        })
      }.width('100%').constraintSize({ maxWidth: MobileDesignGeometry.sheetContentMaxWidth })
        .padding({ left: this.insets.leftPadding(MobileDesignGeometry.genuiHistoryActionInset),
        right: this.insets.rightPadding(MobileDesignGeometry.genuiHistoryActionInset),
        top: 16, bottom: this.insets.bottomPadding(16) })
    }.id('bot-sessions-page').width('100%').height('100%').padding({ top: this.insets.top })
      .backgroundColor(PAGE_BG)
  }

  @Builder
  private CollaborationSheet() {
    ForEach(this.state.collaborationRequest ? [this.state.collaborationRequest] : [], (request: LocalCollaborationRequest) => {
      LocalGenUICollaborationSheet({ request,
        receive: (token: number, data: ArrayBuffer): Promise<void> => this.actions.collaborationReceive(token, data),
        onClose: (token: number): void => this.actions.collaborationClose(token),
        onResult: (token: number, result: LocalCollaborationSnapshot): void => this.actions.collaborationResult(token, result) })
    }, (request: LocalCollaborationRequest): string => String(request.token))
  }

  /**
   * The app owns the whole screen: a floating back control at the leading
   * edge, the app actions behind a floating menu at the trailing edge, and a
   * status pill only while the app is generating or cannot run.
   */
  @Builder
  FloatingControls() {
    Row({ space: 8 }) {
      Stack() {
        NavigationBackButton({ controlSize: MobileDesignGeometry.genuiAppControlSize, onBack: (): void => this.goBack() })
      }
      .width(MobileDesignGeometry.genuiAppControlSize).height(MobileDesignGeometry.genuiAppControlSize)
      .borderRadius(MobileDesignGeometry.genuiAppControlSize / 2).clip(true)
      .backgroundColor(FLOATING_PANEL_BG).backgroundBlurStyle(BlurStyle.Thin)
      .shadow({ radius: 12, color: SHADOW_SUBTLE, offsetY: 2 })

      Blank().layoutWeight(1)
      if (this.floatingStatus().length > 0) {
        Row({ space: 6 }) {
          if (this.state.appStreaming || this.state.appStatus === 'recovering') {
            LoadingProgress().width(14).height(14)
          }
          Text(this.floatingStatus())
            .fontSize(MobileDesignTypography.labelSmall.size).fontColor(INK)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .height(MobileDesignGeometry.genuiAppStatusHeight).padding({
          left: MobileDesignGeometry.genuiAppStatusHorizontalPadding,
          right: MobileDesignGeometry.genuiAppStatusHorizontalPadding
        }).borderRadius(MobileDesignGeometry.genuiAppStatusHeight / 2)
        .backgroundColor(FLOATING_PANEL_BG).backgroundBlurStyle(BlurStyle.Thin)
        .constraintSize({ maxWidth: MobileDesignGeometry.genuiAppStatusMaxWidth })
      }
      Blank().layoutWeight(1)

      if (!this.state.appStreaming && this.state.appStatus !== 'failed' && this.state.appStatus !== 'unsupported' &&
        this.state.appStatus !== 'recovering') {
        Stack({ alignContent: Alignment.Center }) {
          TemplateIcon({ src: $r('app.media.remote_ref_more'), iconWidth: 18, iconHeight: 6 })
        }
        .width(MobileDesignGeometry.genuiAppControlSize).height(MobileDesignGeometry.genuiAppControlSize)
        .borderRadius(MobileDesignGeometry.genuiAppControlSize / 2)
        .backgroundColor(FLOATING_PANEL_BG).backgroundBlurStyle(BlurStyle.Thin)
        .shadow({ radius: 12, color: SHADOW_SUBTLE, offsetY: 2 })
        .accessibilityText(RemoteI18n.t('localGenui.appActions'))
        .bindMenu(this.AppActionsMenu())
      } else {
        Blank().width(MobileDesignGeometry.genuiAppControlSize)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.insets.leftPadding(MobileDesignGeometry.genuiAppControlSideInset),
      right: this.insets.rightPadding(MobileDesignGeometry.genuiAppControlSideInset),
      top: this.insets.top + MobileDesignGeometry.genuiAppControlTopInset
    })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  AppActionsMenu() {
    Menu() {
      if (this.state.standalone) {
        MenuItem({ content: RemoteI18n.t('localGenui.backToChat') })
          .onClick(() => this.actions.showChat())
      }
      if (this.state.inGallery(this.state.appId)) {
        MenuItem({ content: RemoteI18n.t('localGenui.removeFromGallery') })
          .onClick(() => this.actions.removeFromGallery(this.state.appId))
      } else {
        MenuItem({ content: RemoteI18n.t('localGenui.addToGallery') })
          .onClick(() => this.actions.addToGallery(this.state.appId))
      }
    }
  }

  @Builder
  ModelManagerSheet() {
    LocalGenUIModelManager({ state: this.state, actions: this.actions })
  }
}
