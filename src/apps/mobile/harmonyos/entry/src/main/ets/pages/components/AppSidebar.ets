import { SidebarToolsFooter } from './SidebarToolsFooter';
import { SavedRuntimeConnection } from '../../model/RemoteModels';
import { WorkspaceToolsIntent } from '../state/WorkspaceToolsState';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import {
  CARD,
  INK,
  SIDEBAR_BG,
  SIDEBAR_BG_FADE,
  SIDEBAR_HOVER,
  SIDEBAR_INK,
  SIDEBAR_MUTED,
  SIDEBAR_SELECTION,
  SIDEBAR_SUBTLE,
  TRANSPARENT,
} from './Theme';
import { SidebarToggleButton } from './SidebarToggleButton';
import { SidebarGlyph } from './SidebarGlyphs';
import { SidebarConnectionActionPolicy } from '../policy/SidebarConnectionActionPolicy';
import { SidebarLayoutPolicy } from '../policy/SidebarLayoutPolicy';
import { WindowInsetsBinding } from '../../services/WindowSystemBarService';

/** Device and workspace navigation shared by compact and wide controllers. */
@ComponentV2
export struct AppSidebar {
  @Param connectionState: string = 'idle';
  @Param isBusy: boolean = false;
  @Param workspaceKind: string = 'normal';
  @Param workspacePath: string = '';
  @Param controlTargetDeviceId: string = '';
  @Param supportsHarnessProfiles: boolean = false;
  @Param toolLocations: SavedRuntimeConnection[] = [];
  @Event onWorkspaceTools: (intent: WorkspaceToolsIntent) => void = (_intent: WorkspaceToolsIntent) => {};
  @Param accountUserId: string = '';
  @Param controlTargetType: string = 'none';
  @Param showCollapseButton: boolean = false;
  @Param showViewSettingsButton: boolean = false;
  @Param showWorkspaceSection: boolean = false;
  /** Distance already reserved by an inset host between this panel and the window bottom. */
  @Param bottomEdgeSpacing: number = 0;
  @Event onClose: () => void = () => {};
  @Event onOpenBot: () => void = () => {};
  @Event onOpenMiniApps: () => void = () => {};
  @Event onEnterCode: () => void = () => {};
  @Event onCollapse: () => void = () => {};
  @Event onOpenViewSettings: () => void = () => {};
  @Event onSearchQueryChange: (query: string) => void = (_query: string) => {};
  @Event onOpenSettings: () => void = () => {};
  @Event onOpenAccount: () => void = () => {};
  @Local showSearch: boolean = false;
  @Local sessionSearchQuery: string = '';
  /** Window-local safe areas shared by both responsive sidebar hosts. */
  @Local insets: WindowInsetsBinding = new WindowInsetsBinding();
  /**
   * The authenticated device/workspace section.
   *
   * It is a slot rather than a component this file constructs because the
   * sidebar has no business knowing about remote state; the host wires it.
   */
  @BuilderParam contentSlot: () => void = this.EmptySlot;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context) {
      this.insets.bind(this.getUIContext(), context);
    }
  }

  aboutToDisappear(): void {
    this.insets.unbind();
  }

  build() {
    this.SidebarContent()
  }

  @Builder
  private SidebarContent() {
    Column() {
      if (this.shouldShowPrimaryNavigation()) {
        this.PrimaryNavigationHeader()
      } else {
        this.SignedOutHeader()
      }

      if (this.shouldShowPrimaryNavigation()) {
        Column() {
          Column() {
            this.NavigationScroll()
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
          this.PrimaryNavigationFooter()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          this.NavigationScroll()
          Column()
            .width('100%')
            .height(this.usesCompactFooter() ? 92 : 120)
            .hitTestBehavior(HitTestMode.None)
            .linearGradient({
              angle: 180,
              colors: [[SIDEBAR_BG_FADE, 0.0], [SIDEBAR_BG, 0.62]]
            })
            .margin({ bottom: this.footerBottomPadding() })
          this.SignedOutFooter()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    // Paint to the window edge while keeping controls inside its safe areas.
    .padding({ left: this.insets.leftPadding(SidebarLayoutPolicy.HEADER_HORIZONTAL_PADDING),
      right: this.insets.rightPadding(SidebarLayoutPolicy.HEADER_HORIZONTAL_PADDING), top: this.insets.top })
    .backgroundColor(SIDEBAR_BG)
  }

  @Builder
  private EmptySlot() {
  }

  /** Reserved for the future on-device assistant, never a remote-session shortcut. */
  @Builder
  private BotEntryRow() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SidebarLayoutPolicy.ROW_GAP }) {
        SidebarGlyph({ kind: 'assistant', iconSize: SidebarLayoutPolicy.PROMINENT_ICON_SLOT_SIZE,
          tint: SIDEBAR_MUTED })
        Text(RemoteI18n.t('sidebar.bot'))
          .fontSize(MobileDesignTypography.bodyMedium.size)
          .fontWeight(FontWeight.Regular)
          .fontColor(SIDEBAR_MUTED)
        Blank()
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(40)
    .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
    .backgroundColor(TRANSPARENT)
    .borderRadius(6)
    .id('sidebar-local-bot')
    .accessibilityText(RemoteI18n.t('sidebar.bot'))
    .onClick(() => this.onOpenBot())
  }

  @Builder
  private MiniAppsEntryRow() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: SidebarLayoutPolicy.ROW_GAP }) {
        Stack({ alignContent: Alignment.Center }) {
          SidebarGlyph({ kind: 'apps', iconSize: SidebarLayoutPolicy.PROMINENT_ICON_SLOT_SIZE,
            tint: SIDEBAR_MUTED })
        }
        .width(SidebarLayoutPolicy.PROMINENT_ICON_SLOT_SIZE)
        .height(SidebarLayoutPolicy.PROMINENT_ICON_SLOT_SIZE)
        Text(RemoteI18n.t('miniapp.title'))
          .fontSize(MobileDesignTypography.bodyMedium.size)
          .fontWeight(FontWeight.Regular)
          .fontColor(SIDEBAR_MUTED)
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(SidebarLayoutPolicy.ENTRY_ROW_HEIGHT)
    .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
    .backgroundColor(TRANSPARENT)
    .borderRadius(6)
    .margin({ bottom: 4 })
    .stateEffect(true)
    .accessibilityText(RemoteI18n.t('miniapp.title'))
    .onClick(() => this.onOpenMiniApps())
  }

  @Builder
  private PrimaryNavigationHeader() {
    Row() {
      Text(RemoteI18n.t('app.title'))
        .fontSize(MobileDesignTypography.titleMedium.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(SIDEBAR_INK)
      Blank()
      // Right-aligned so the search and collapse controls keep the same
      // position whether or not the source-specific view-settings entry shows.
      Row({ space: 4 }) {
        if (this.showViewSettingsButton) {
          Button() {
            SidebarGlyph({ kind: 'session_more' })
          }
          .width(MobileDesignGeometry.controlTouchSize)
          .height(MobileDesignGeometry.controlTouchSize)
          .padding(0)
          .backgroundColor(TRANSPARENT)
          .borderRadius(12)
          .stateEffect(true)
          .accessibilityText(RemoteI18n.t('remote.actions'))
          .onClick(() => {
            this.onOpenViewSettings();
          })
        }

        Stack({ alignContent: Alignment.Center }) {
          Button() {
            SidebarGlyph({ kind: 'search', iconSize: 18 })
          }
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(TRANSPARENT)
          .border({ width: 0, color: TRANSPARENT })
          .borderRadius(8)
          .stateEffect(true)
          .accessibilityText(RemoteI18n.t('common.search'))
          .onClick(() => {
            this.showSearch = !this.showSearch;
            if (!this.showSearch) {
              this.updateSearchQuery('');
            }
          })
        }
        .id('sidebar-search-slot')
        .width(SidebarLayoutPolicy.TRAILING_SLOT_SIZE)
        .height(40)

        if (this.showCollapseButton) {
          Stack({ alignContent: Alignment.Center }) {
            SidebarToggleButton({
              controlSize: 32,
              onToggle: this.onCollapse
            })
          }
          .id('sidebar-collapse-slot')
          .width(SidebarLayoutPolicy.TRAILING_SLOT_SIZE)
          .height(40)
        }
      }
    }
    .width('100%')
    .height(SidebarLayoutPolicy.HEADER_HEIGHT)
    .alignItems(VerticalAlign.Center)

    if (this.showSearch) {
      TextInput({ placeholder: RemoteI18n.t('sidebar.searchPlaceholder'), text: this.sessionSearchQuery })
        .width('100%')
        .height(SidebarLayoutPolicy.ENTRY_ROW_HEIGHT)
        .fontSize(MobileDesignTypography.bodyMedium.size)
        .fontColor(SIDEBAR_INK)
        .placeholderColor(SIDEBAR_SUBTLE)
        .placeholderFont({ size: MobileDesignTypography.bodyMedium.size, weight: FontWeight.Regular })
        .fontWeight(FontWeight.Regular)
        .id('sidebar-search-input')
        .padding({ left: 12, right: 12 })
        .backgroundColor(SIDEBAR_HOVER)
        .borderRadius(10)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.updateSearchQuery(value);
        })
    }
  }

  private updateSearchQuery(value: string): void {
    this.sessionSearchQuery = value;
    this.onSearchQueryChange(value);
  }

  @Builder
  private SignedOutHeader() {
    Row() {
      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.desktop'))
          .fontSize(23)
          .fontColor([SIDEBAR_INK])
          .width(24)
          .height(24)
        Text(RemoteI18n.t('sidebar.devices'))
          .fontSize(MobileDesignTypography.bodyLarge.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(SIDEBAR_INK)
      }
      .layoutWeight(1)
      .height(50)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onEnterCode();
      })

      if (this.showCollapseButton) {
        SidebarToggleButton({
          controlSize: MobileDesignGeometry.controlTouchSize,
          onToggle: this.onCollapse
        })
      }
    }
    .width('100%')
    .height(50)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private NavigationScroll() {
    Scroll() {
      Column() {
        this.BotEntryRow()
        this.MiniAppsEntryRow()
        if (this.showWorkspaceSection) {
          this.contentSlot()
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: this.scrollTailPadding() })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
  }

  @Builder
  private PrimaryNavigationFooter() {
    SidebarToolsFooter({
      toolsEnabled: this.connectionState === 'connected',
      onOpenTools: () => this.requestDeviceTools(),
      onOpenSettings: () => this.onOpenSettings()
    })
      .margin({ bottom: this.footerBottomPadding() })
  }

  @Builder
  private SignedOutFooter() {
    Column({ space: 8 }) {
      Button() {
        Text(RemoteI18n.t('sidebar.signInOpenBitFunAccount'))
          .fontSize(MobileDesignTypography.bodyMedium.size)
          .fontWeight(FontWeight.Bold)
          .fontColor(CARD)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
      }
        .width('100%')
        .height(48)
        .padding(0)
        .backgroundColor(INK)
        .borderRadius(16)
        .onClick(() => {
          this.onOpenAccount();
        })
    }
      .width('100%')
      .margin({ bottom: this.footerBottomPadding() })
      .zIndex(2)
  }

  private requestDeviceTools(): void {
    if (this.connectionState !== 'connected') return;
    this.onWorkspaceTools({ type: 'open-device', deviceId: this.controlTargetDeviceId, connectionId: '', tab: 0 });
  }

  private shouldShowPrimaryNavigation(): boolean {
    return SidebarConnectionActionPolicy.shouldShowPrimaryNavigation(
      this.accountUserId,
      this.controlTargetType,
      this.connectionState
    );
  }

  private usesCompactFooter(): boolean {
    return this.shouldShowPrimaryNavigation() || this.connectionState === 'connected';
  }

  /** Keep footer controls above this window's navigation indicator. */
  private footerBottomPadding(): number {
    const remainingSafeArea = Math.max(0, this.insets.bottom - this.bottomEdgeSpacing);
    return Math.max(this.shouldShowPrimaryNavigation() ? 0 : 16, remainingSafeArea);
  }

  /** Signed-out actions overlay the list; primary navigation has a reserved footer. */
  private scrollTailPadding(): number {
    if (this.shouldShowPrimaryNavigation()) return 8;
    return (this.usesCompactFooter() ? SidebarLayoutPolicy.FOOTER_HEIGHT + 16 : 120) + this.insets.bottom;
  }
}
