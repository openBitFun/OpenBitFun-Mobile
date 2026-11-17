import { SessionActivityState } from '../state/SessionActivityState';
import { RecentSessionPolicy } from '../policy/RecentSessionPolicy';
import { AdaptiveSheetContent } from './AdaptiveSheetContent';
import { WorkspaceToolsPanel } from './WorkspaceToolsPanel';
import { WorkspaceToolsState, WorkspaceToolsIntent } from '../state/WorkspaceToolsState';
import { MobileDesignGeometry, MobileDesignTypography } from '../../generated/MobileDesignTokens';
import { SavedRuntimeConnection, RecentWorkspaceEntry, RemoteSession } from '../../model/RemoteModels';
import { RemoteI18n } from '../../i18n/RemoteI18n';
import {
  DeviceDirectoryEntry,
  DeviceDirectoryState,
  emptyDeviceDirectoryEntry
} from '../state/DeviceDirectoryState';
import { SidebarDirectoryPreviewPolicy } from '../policy/SidebarDirectoryPreviewPolicy';
import { SidebarDeviceProjectionPolicy } from '../policy/SidebarDeviceProjectionPolicy';
import { SidebarLayoutPolicy } from '../policy/SidebarLayoutPolicy';
import {
  SettingsPlacement,
  SettingsPlacementPolicy,
  SettingsSheetKind
} from '../policy/SettingsPlacementPolicy';
import { AdaptiveSheetOptions } from './AdaptiveSheetOptions';
import {
  CARD,
  INK,
  LINE,
  SHADOW_SUBTLE,
  SIDEBAR_INK,
  SIDEBAR_MUTED,
  SIDEBAR_SELECTION,
  SIDEBAR_SUBTLE,
  STATUS_DANGER,
  STATUS_SUCCESS,
  TRANSPARENT,
} from './Theme';
import { SidebarDeviceGroup } from './SidebarDeviceGroup';
import { SidebarGlyph } from './SidebarGlyphs';
import { TemplateIcon } from './TemplateIcon';
import { SidebarDeviceIcon } from './SidebarNavigationIcons';
import { SidebarWorkspacePicker } from './SidebarWorkspacePicker';
import { ConnectionStatusPresenter } from '../../services/ConnectionStatusPresenter';

/**
 * Flat device selector followed by the selected device's workspace tree.
 *
 * Device rows choose the remote context; they no longer each own a nested
 * directory. This keeps one visible workspace hierarchy and makes its owner
 * explicit without repeating the same tree under every account desktop.
 */
@ComponentV2
export struct SidebarWorkspaceSection {
  @Param workspaceTools: WorkspaceToolsState = new WorkspaceToolsState();
  @Event onWorkspaceTools: (intent: WorkspaceToolsIntent) => void = (_intent: WorkspaceToolsIntent) => {};
  @Param directoryState: DeviceDirectoryState = new DeviceDirectoryState();
  @Param sessions: RemoteSession[] = [];
  @Param recentSessions: RemoteSession[] | undefined = undefined;
  @Param savedConnections: SavedRuntimeConnection[] = [];
  @Param savedConnectionsTargetId: string = '';
  @Param recentWorkspaces: RecentWorkspaceEntry[] = [];
  @Param workspaceName: string = '';
  @Param workspacePath: string = '';
  @Param workspaceConnectionId: string = '';
  @Param workspaceSshHost: string = '';
  /** Stable record ID of the active workspace; empty for pre-ID hosts. */
  @Param workspaceId: string = '';
  @Param workspaceKind: string = 'normal';
  @Param connectionState: string = 'idle';
  @Param controlTargetType: string = 'none';
  @Param controlTargetDeviceId: string = '';
  @Param controlTargetDeviceName: string = '';
  @Param selectedSessionId: string = '';
  @Param runningSessionId: string = '';
  @Param sessionActivity: SessionActivityState = new SessionActivityState();
  @Param query: string = '';
  @Param supportsHarnessProfiles: boolean = false;
  @Param workspacePickerPlacement: SettingsPlacement =
    SettingsPlacementPolicy.compactBottom(SettingsSheetKind.SessionDetails);
  @Event onOpenSession: (session: RemoteSession) => void = (_session: RemoteSession) => {};
  @Event onSessionActions: (session: RemoteSession) => void = (_session: RemoteSession) => {};
  @Event onCreateInWorkspace: (deviceId: string, path: string, agentType: string, connectionId?: string, sshHost?: string,
    workspaceId?: string) => void = (_deviceId: string, _path: string, _agentType: string) => {};
  @Event onOpenWorkspace: (deviceId: string, path: string, connectionId?: string, sshHost?: string, workspaceId?: string) => void =
    (_deviceId: string, _path: string) => {};
  @Event onExpandWorkspace: (deviceId: string, path: string, remoteConnectionId?: string, remoteSshHost?: string,
    workspaceId?: string) => Promise<void> = async (_deviceId: string, _path: string) => {};
  @Event onSelectDevice: (deviceId: string) => void = (_deviceId: string) => {};
  @Event onReconnect: () => void = () => {};
  @Event onRetryDevice: (deviceId: string) => void = (_deviceId: string) => {};
  @Event onAddWorkspace: (deviceId: string) => void = (_deviceId: string) => {};
  @Event onRefreshDevices: () => Promise<void> = async () => {};
  @Event onAddDevice: () => void = () => {};
  @Local visibleDeviceCount: number = SidebarDirectoryPreviewPolicy.PREVIEW_COUNT;
  @Local showWorkspacePicker: boolean = false;
  @Local inspectedDeviceId: string = '';
  @Local workspacePickerDeviceId: string = '';
  private readonly transientEntry: DeviceDirectoryEntry = emptyDeviceDirectoryEntry('', '', false);

  build() {
    Column() {
      this.DeviceSectionHeader()
      if (this.directoryState.refreshError.length > 0) {
        Text(this.directoryState.refreshError)
          .fontSize(MobileDesignTypography.bodySmall.size)
          .fontColor(STATUS_DANGER)
          .width('100%')
          .padding({ top: 4, bottom: 8 })
          .onClick(() => { void this.onRefreshDevices(); })
      }
      Row() {}.height(0)
        .bindSheet($$this.workspaceTools.visible, this.WorkspaceTools(), { height: SheetSize.LARGE, showClose: false, onWillDismiss: (action: DismissSheetAction): void => {
          if (this.workspaceTools.dirty) this.onWorkspaceTools({ type: 'close' });
          else { this.onWorkspaceTools({ type: 'close' }); action.dismiss(); }
        }, onDisappear: () => this.onWorkspaceTools({ type: 'close' }) })
      if (this.deviceEntries().length > 0) {
        ForEach(this.visibleDeviceEntries(), (entry: DeviceDirectoryEntry) => {
          this.DeviceRow(entry)
        }, (entry: DeviceDirectoryEntry): string => this.deviceKey(entry))
        if (this.visibleDeviceCount < this.deviceEntries().length) {
          this.MoreDevicesRow()
        }
        // The workspace tree owns projection caches and local disclosure state.
        // Include the projection source: a transient control target and its
        // account directory entry are different observed objects, even when
        // they identify the same device.
        ForEach(this.selectedEntries(), (entry: DeviceDirectoryEntry) => {
          this.WorkspaceSection(entry)
        }, (entry: DeviceDirectoryEntry): string => this.deviceKey(entry))
        if (this.recentSessionRows().length > 0) {
          this.RecentSection()
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 8 })
    .bindSheet($$this.showWorkspacePicker, this.WorkspacePicker(), this.workspacePickerSheetOptions())
  }

  @Builder
  private WorkspaceTools() {
    WorkspaceToolsPanel({ state: this.workspaceTools, onIntent: this.onWorkspaceTools })
  }

  @Builder
  private DeviceSectionHeader() {
    Row() {
      Text(RemoteI18n.t('sidebar.devices'))
        .id('sidebar-workspace-section')
        .fontSize(MobileDesignTypography.labelSmall.size)
        .fontWeight(FontWeight.Medium)
        .fontColor(SIDEBAR_MUTED)
      Blank()
      Stack({ alignContent: Alignment.Center }) {
        if (this.directoryState.refreshing) {
          LoadingProgress()
            .width(MobileDesignGeometry.sidebarRefreshIconSize)
            .height(MobileDesignGeometry.sidebarRefreshIconSize)
            .color(SIDEBAR_MUTED)
        } else {
          TemplateIcon({ src: $r('app.media.ic_sidebar_refresh'),
            iconWidth: MobileDesignGeometry.sidebarRefreshIconSize,
            iconHeight: MobileDesignGeometry.sidebarRefreshIconSize, tint: SIDEBAR_MUTED })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(SidebarLayoutPolicy.INSET_TRAILING_SLOT_SIZE)
      .height(SidebarLayoutPolicy.SECTION_LABEL_HEIGHT)
      .enabled(!this.directoryState.refreshing)
      .id('sidebar-refresh-action')
      .accessibilityText(RemoteI18n.t('common.refresh'))
      .onClick(() => {
        void this.onRefreshDevices();
      })

    }
    .width('100%')
    .height(SidebarLayoutPolicy.DEVICE_SECTION_HEADER_HEIGHT)
    .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private DeviceRow(entry: DeviceDirectoryEntry) {
    Row({ space: 8 }) {
      SidebarDeviceIcon({
        deviceName: entry.deviceName,
        iconSize: SidebarLayoutPolicy.PROMINENT_ICON_SLOT_SIZE,
        tint: SIDEBAR_INK
      })
        .hitTestBehavior(HitTestMode.None)
      Text(entry.displayName)
        .fontSize(MobileDesignTypography.bodyMedium.size)
        .fontWeight(this.isSelected(entry) ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(SIDEBAR_INK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .wordBreak(WordBreak.BREAK_ALL)
        .hitTestBehavior(HitTestMode.None)
      Stack({ alignContent: Alignment.Center }) {
        if (entry.status === 'loading') {
          LoadingProgress()
            .width(13)
            .height(13)
            .color(SIDEBAR_MUTED)
            .hitTestBehavior(HitTestMode.None)
        } else {
          Text('')
            .width(SidebarLayoutPolicy.STATUS_DOT_SIZE)
            .height(SidebarLayoutPolicy.STATUS_DOT_SIZE)
            .backgroundColor(this.deviceHealthColor(entry))
            .borderRadius(SidebarLayoutPolicy.STATUS_DOT_SIZE / 2)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .id(`sidebar-device-status:${entry.deviceId}`)
      .width(SidebarLayoutPolicy.INSET_TRAILING_SLOT_SIZE)
      .height(SidebarLayoutPolicy.DEVICE_ROW_HEIGHT)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(SidebarLayoutPolicy.DEVICE_ROW_HEIGHT)
    .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isSelected(entry) ? SIDEBAR_SELECTION : TRANSPARENT)
    .borderRadius(10)
    .accessibilityText(`${entry.displayName}, ${this.isActiveDevice(entry.deviceId) ? ConnectionStatusPresenter.label(this.connectionState) :
      RemoteI18n.t(entry.online ? 'sidebar.deviceOnline' : 'sidebar.deviceOffline')}`)
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.inspectedDeviceId = entry.deviceId;
    }))
    .bindPopup(this.inspectedDeviceId === entry.deviceId, {
      builder: () => { this.DeviceNamePopover(entry.deviceId) },
      placement: Placement.BottomLeft,
      popupColor: TRANSPARENT,
      backgroundBlurStyle: BlurStyle.NONE,
      shadow: { radius: 0, color: TRANSPARENT },
      radius: 14,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: 4,
      onStateChange: (event: PopupStateChangeParam) => {
        if (!event.isVisible && this.inspectedDeviceId === entry.deviceId) this.inspectedDeviceId = '';
      }
    })
    .onClick(() => {
      if (this.canRetryDevice(entry)) {
        this.onReconnect();
      } else if (this.canUseDevice(entry)) {
        this.onSelectDevice(entry.deviceId);
      }
    })
  }

  @Builder
  private DeviceNamePopover(deviceId: string) {
    Text(this.deviceEntries().find((entry: DeviceDirectoryEntry) => entry.deviceId === deviceId)?.displayName || '')
      .id('sidebar-device-full-name')
      .fontSize(MobileDesignTypography.bodyMedium.size)
      .lineHeight(MobileDesignTypography.bodyMedium.lineHeight)
      .fontColor(INK)
      .wordBreak(WordBreak.BREAK_ALL)
      .width(240)
      .padding(12)
      .backgroundColor(CARD)
      .borderRadius(14)
      .border({ width: 0.5, color: LINE })
      .shadow({ radius: 10, color: SHADOW_SUBTLE, offsetY: 3 })
  }

  private canRetryDevice(entry: DeviceDirectoryEntry): boolean {
    return this.isActiveDevice(entry.deviceId) &&
      (this.connectionState === 'failed' || this.connectionState === 'disconnected');
  }

  private deviceHealthColor(entry: DeviceDirectoryEntry): ResourceColor {
    if (!this.isActiveDevice(entry.deviceId)) return entry.online ? STATUS_SUCCESS : SIDEBAR_SUBTLE;
    if (this.connectionState === 'connected') return STATUS_SUCCESS;
    if (this.connectionState === 'failed' || this.connectionState === 'disconnected') return STATUS_DANGER;
    return SIDEBAR_MUTED;
  }

  @Builder
  private WorkspaceSection(entry: DeviceDirectoryEntry) {
    Column() {
      Row() {
        Text(RemoteI18n.t('sidebar.workspaces'))
          .fontSize(MobileDesignTypography.labelSmall.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(SIDEBAR_MUTED)
        Blank()
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(SidebarLayoutPolicy.ICON_SLOT_SIZE)
            .fontColor([this.canUseDevice(entry) ? SIDEBAR_INK : SIDEBAR_SUBTLE])
        }
        .width(SidebarLayoutPolicy.INSET_TRAILING_SLOT_SIZE)
        .height(SidebarLayoutPolicy.SECTION_LABEL_HEIGHT)
        .opacity(this.canUseDevice(entry) ? 1 : 0.38)
        .id(`sidebar-add-workspace:${entry.deviceId}`)
        .accessibilityText(RemoteI18n.t('sidebar.addWorkspace'))
        .onClick(() => {
          if (this.canUseDevice(entry)) {
            this.openWorkspacePicker(entry);
          }
        })
      }
      .width('100%')
      .height(SidebarLayoutPolicy.WORKSPACE_SECTION_HEADER_HEIGHT)
      .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
      .margin({ top: 12 })
      .alignItems(VerticalAlign.Center)

      if (entry.catalogSource === 'recent') {
        Text(RemoteI18n.t('sidebar.legacyWorkspaceCatalog'))
          .fontSize(MobileDesignTypography.bodySmall.size)
          .fontColor(SIDEBAR_MUTED)
          .padding({ left: 10, right: 10, bottom: 4 })
      }
      SidebarDeviceGroup({
        onWorkspaceTools: this.onWorkspaceTools,
        device: entry,
        directoryState: this.directoryState,
        sessions: this.usesLiveDirectory(entry) ? this.sessions : [],
        workspaceName: this.liveWorkspaceName(entry),
        workspacePath: this.liveWorkspacePath(entry),
        workspaceConnectionId: this.isActiveDevice(entry.deviceId) ? this.workspaceConnectionId : '',
        workspaceSshHost: this.isActiveDevice(entry.deviceId) ? this.workspaceSshHost : '',
        workspaceId: this.isActiveDevice(entry.deviceId) ? this.workspaceId : '',
        workspaceKind: this.liveWorkspaceKind(entry),
        selectedSessionId: this.selectedSessionIdFor(entry),
        runningSessionId: this.isActiveDevice(entry.deviceId) ? this.runningSessionId : '',
        sessionActivity: this.sessionActivity,
        query: this.query,
        isActive: this.isActiveDevice(entry.deviceId),
        supportsHarnessProfiles: this.supportsHarnessProfiles,
        onRetry: () => {
          if (!entry.online || this.directoryState.refreshError.length > 0) {
            void this.onRefreshDevices();
          } else if (this.isDirectoryEntry(entry)) {
            this.onRetryDevice(entry.deviceId);
          } else {
            this.onReconnect();
          }
        },
        onOpenSession: this.onOpenSession,
        onSessionActions: this.onSessionActions,
        onCreateInWorkspace: (path: string, agentType: string, connectionId?: string, sshHost?: string, workspaceId?: string) => {
          this.onCreateInWorkspace(entry.deviceId, path, agentType, connectionId, sshHost, workspaceId);
        },
        onOpenWorkspace: (path: string, connectionId?: string, sshHost?: string, workspaceId?: string) => {
          this.onOpenWorkspace(entry.deviceId, path, connectionId, sshHost, workspaceId);
        },
        onExpandWorkspace: async (path: string, remoteConnectionId?: string, remoteSshHost?: string, workspaceId?: string): Promise<void> => {
          await this.onExpandWorkspace(entry.deviceId, path, remoteConnectionId, remoteSshHost, workspaceId);
        },
        onWorkspaceExpandedChange: (path: string, expanded: boolean, remoteConnectionId?: string, remoteSshHost?: string,
          workspaceId?: string): void => {
          this.directoryState.setWorkspaceExpanded(entry.deviceId, path, expanded, remoteConnectionId, remoteSshHost, workspaceId);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private MoreDevicesRow() {
    Row({ space: 8 }) {
      SidebarGlyph({ kind: 'session_more', tint: SIDEBAR_MUTED })
      Text(RemoteI18n.f('sidebar.moreDevices',
        String(this.deviceEntries().length - this.visibleDeviceCount)))
        .fontSize(MobileDesignTypography.bodySmall.size)
        .fontColor(SIDEBAR_MUTED)
    }
    .width('100%')
    .height(SidebarLayoutPolicy.AUXILIARY_ROW_HEIGHT)
    .padding({ left: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.visibleDeviceCount += SidebarDirectoryPreviewPolicy.PREVIEW_COUNT;
    })
  }

  @Builder
  private RecentSection() {
    Column() {
      Row() {
        Text(RemoteI18n.t('home.recent'))
          .fontSize(MobileDesignTypography.labelSmall.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(SIDEBAR_MUTED)
        Blank()
      }
      .width('100%')
      .height(SidebarLayoutPolicy.SECTION_LABEL_HEIGHT)
      .margin({ top: 16 })
      .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
      .alignItems(VerticalAlign.Center)

      ForEach(this.recentSessionRows(), (row: RemoteSession) => {
        this.RecentSessionRow(row)
      }, (row: RemoteSession): string => `recent:${row.deviceId || ''}:${row.id}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RecentSessionRow(row: RemoteSession) {
    Row({ space: SidebarLayoutPolicy.ROW_GAP }) {
      Text(this.currentRecentSession(row).title || RemoteI18n.t('sidebar.untitled'))
        .fontSize(MobileDesignTypography.labelLarge.size)
        .fontWeight(row.id === this.selectedSessionId ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(SIDEBAR_INK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .wordBreak(WordBreak.BREAK_ALL)
      if (this.isRecentRunning(this.currentRecentSession(row)) || this.isRecentError(this.currentRecentSession(row))) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.isRecentRunning(this.currentRecentSession(row))) {
            Text('')
              .width(SidebarLayoutPolicy.STATUS_DOT_SIZE)
              .height(SidebarLayoutPolicy.STATUS_DOT_SIZE)
              .backgroundColor(STATUS_SUCCESS)
              .borderRadius(SidebarLayoutPolicy.STATUS_DOT_SIZE / 2)
          } else if (this.isRecentError(this.currentRecentSession(row))) {
            Text('')
              .width(SidebarLayoutPolicy.STATUS_DOT_SIZE)
              .height(SidebarLayoutPolicy.STATUS_DOT_SIZE)
              .backgroundColor(STATUS_DANGER)
              .borderRadius(SidebarLayoutPolicy.STATUS_DOT_SIZE / 2)
          }
        }
        .width(SidebarLayoutPolicy.INSET_TRAILING_SLOT_SIZE)
        .height(SidebarLayoutPolicy.SESSION_ROW_HEIGHT)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(SidebarLayoutPolicy.SESSION_ROW_HEIGHT)
    .padding({ left: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING, right: SidebarLayoutPolicy.ROW_HORIZONTAL_PADDING })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(row.id === this.selectedSessionId ? SIDEBAR_SELECTION : TRANSPARENT)
    .borderRadius(6)
    .onClick(() => this.onOpenSession(this.currentRecentSession(row)))
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      const current = (this.recentSessions || this.sessions).find((item: RemoteSession): boolean =>
        item.id === row.id && (item.deviceId || '') === (row.deviceId || ''));
      if (current) this.onSessionActions(current);
    }))
  }

  private deviceEntries(): DeviceDirectoryEntry[] {
    const directoryEntries = this.directoryState.devices;
    if (!SidebarDeviceProjectionPolicy.shouldPrependControlTarget(
      directoryEntries.map((entry: DeviceDirectoryEntry): string => entry.deviceId),
      this.controlTargetType,
      this.controlTargetDeviceId,
      this.isConnected(),
      this.recentWorkspaces.length > 0 || this.sessions.length > 0
    )) {
      return directoryEntries;
    }
    this.updateTransientEntry();
    return [this.transientEntry].concat(directoryEntries);
  }

  @Builder
  private WorkspacePicker() {
    AdaptiveSheetContent({ placement: this.workspacePickerPlacement, content: () => { this.WorkspacePickerBody() } })
  }

  @Builder
  private WorkspacePickerBody() {
    SidebarWorkspacePicker({
      tools: this.workspaceTools,
      canBrowse: this.isActiveDevice(this.workspacePickerDevice().deviceId),
      onBrowse: this.onWorkspaceTools,
      deviceName: this.workspacePickerDevice().displayName,
      savedConnections: this.workspacePickerDevice().deviceId === this.savedConnectionsTargetId ? this.savedConnections : [],
      workspaces: this.workspacePickerDevice().catalogSource.length > 0 ?
        this.workspacePickerDevice().recentWorkspaces : this.workspacesForDevice(this.workspacePickerDevice()),
      selectedWorkspacePath: this.isActiveDevice(this.workspacePickerDevice().deviceId) ?
        this.workspacePath : '',
      selectedWorkspaceId: this.isActiveDevice(this.workspacePickerDevice().deviceId) ? this.workspaceId : '',
      selectedWorkspaceConnectionId: this.isActiveDevice(this.workspacePickerDevice().deviceId) ?
        this.workspaceConnectionId : '',
      selectedWorkspaceSshHost: this.isActiveDevice(this.workspacePickerDevice().deviceId) ? this.workspaceSshHost : '',
      loading: this.workspacePickerDevice().status === 'loading',
      onClose: () => {
        this.showWorkspacePicker = false;
      },
      onSelectWorkspace: (path: string, connectionId?: string, sshHost?: string, workspaceId?: string) => {
        const deviceId = this.workspacePickerDeviceId;
        this.showWorkspacePicker = false;
        this.onOpenWorkspace(deviceId, path, connectionId, sshHost, workspaceId);
      }
    })
  }

  private openWorkspacePicker(entry: DeviceDirectoryEntry): void {
    this.workspacePickerDeviceId = entry.deviceId;
    this.showWorkspacePicker = true;
    this.onAddWorkspace(entry.deviceId);
  }

  private workspacePickerDevice(): DeviceDirectoryEntry {
    const entry = this.deviceEntries().find((item: DeviceDirectoryEntry): boolean =>
      item.deviceId === this.workspacePickerDeviceId
    );
    return entry || this.transientEntry;
  }

  private workspacePickerSheetOptions(): SheetOptions {
    return AdaptiveSheetOptions.fromPlacement(this.workspacePickerPlacement, true);
  }

  private visibleDeviceEntries(): DeviceDirectoryEntry[] {
    const entries = this.deviceEntries();
    return entries.length <= this.visibleDeviceCount ? entries : entries.slice(0, this.visibleDeviceCount);
  }

  private selectedEntry(): DeviceDirectoryEntry | undefined {
    const entries = this.deviceEntries();
    const selectedId = this.directoryState.selectedDeviceId.trim();
    if (selectedId.length === 0) {
      return undefined;
    }
    return entries.find((entry: DeviceDirectoryEntry): boolean => entry.deviceId === selectedId);
  }

  private selectedEntries(): DeviceDirectoryEntry[] {
    const selected = this.selectedEntry();
    if (selected) {
      return [selected];
    }

    // The directory is hydrated independently from the control target. During
    // that short window selectedDeviceId can still be empty even though the
    // sidebar already has a real device (or a transient QR device) to render.
    // Do not hide the workspace tree while that selection state catches up.
    const active = this.deviceEntries().find((entry: DeviceDirectoryEntry): boolean =>
      this.isActiveDevice(entry.deviceId)
    );
    if (active) {
      return [active];
    }

    // A single directory entry is unambiguous and is the same device the user
    // sees immediately above the tree. Showing its workspaces keeps the
    // sidebar usable before the first selection callback arrives.
    const entries = this.deviceEntries();
    return entries.length === 1 ? [entries[0]] : [];
  }

  private isSelected(entry: DeviceDirectoryEntry): boolean {
    const selected = this.selectedEntry();
    return !!selected && selected.deviceId === entry.deviceId;
  }

  private deviceKey(entry: DeviceDirectoryEntry): string {
    return this.isDirectoryEntry(entry) ? entry.deviceId : `transient:${entry.deviceId}`;
  }

  private updateTransientEntry(): void {
    const targetId = this.controlTargetDeviceId.trim();
    this.transientEntry.deviceId = targetId;
    this.transientEntry.deviceName = this.controlTargetDeviceName.trim() || targetId;
    this.transientEntry.online = this.isConnected();
    this.transientEntry.status = 'ready';
    this.transientEntry.workspaces = this.recentWorkspaces;
    this.transientEntry.sessions = this.sessions;
  }

  private isDirectoryEntry(entry: DeviceDirectoryEntry): boolean {
    return this.directoryState.find(entry.deviceId) === entry;
  }

  private usesLiveDirectory(entry: DeviceDirectoryEntry): boolean {
    return this.isActiveDevice(entry.deviceId) && this.isConnected();
  }

  private liveWorkspacePath(entry: DeviceDirectoryEntry): string {
    return this.usesLiveDirectory(entry) ? this.workspacePath : '';
  }

  private liveWorkspaceName(entry: DeviceDirectoryEntry): string {
    if (this.liveWorkspacePath(entry).length === 0) return '';
    if (this.workspaceKind === 'remote' && this.workspaceConnectionId.length > 0) {
      const connection = this.savedConnections.find((item: SavedRuntimeConnection): boolean => {
        return item.id === this.workspaceConnectionId && item.name.trim().length > 0;
      });
      if (connection) return connection.name;
    }
    return this.workspaceName;
  }

  private liveWorkspaceKind(entry: DeviceDirectoryEntry): string {
    return this.usesLiveDirectory(entry) ? this.workspaceKind : 'normal';
  }
  private workspacesForDevice(entry: DeviceDirectoryEntry): RecentWorkspaceEntry[] {
    return entry.workspaces;
  }

  private selectedSessionIdFor(entry: DeviceDirectoryEntry): string {
    if (this.selectedSessionId.length === 0) {
      return '';
    }
    if (this.isActiveDevice(entry.deviceId)) {
      return this.selectedSessionId;
    }
    return entry.sessions.some((item: RemoteSession): boolean => item.id === this.selectedSessionId) ?
      this.selectedSessionId : '';
  }

  @Computed
  get recentSessionIndex(): Map<string, RemoteSession> {
    const index: Map<string, RemoteSession> = new Map();
    (this.recentSessions || this.sessions).forEach((row: RemoteSession) => index.set(`${row.deviceId || ''}:${row.id}`, row));
    return index;
  }

  private currentRecentSession(row: RemoteSession): RemoteSession {
    return this.recentSessionIndex.get(`${row.deviceId || ''}:${row.id}`) || row;
  }

  private recentSessionRows(): RemoteSession[] {
    if (this.connectionState !== 'connected') return [];
    return RecentSessionPolicy.rows(this.recentSessions || this.sessions, 5);
  }

  private isRecentRunning(session: RemoteSession): boolean {
    const activity = this.sessionActivity.get(session.deviceId || this.controlTargetDeviceId, session.id);
    if (activity) return activity.status === 'running';
    const status = session.status.toLowerCase();
    return session.id === this.runningSessionId || status === 'running' || status === 'active' || status === 'streaming';
  }

  private isRecentError(session: RemoteSession): boolean {
    const status = this.sessionActivity.get(session.deviceId || this.controlTargetDeviceId, session.id)?.status || session.status.toLowerCase();
    return status.indexOf('error') >= 0 || status === 'failed' || status === 'rejected';
  }

  private isActiveDevice(deviceId: string): boolean {
    const activeId = this.controlTargetDeviceId;
    if (activeId.length === 0) {
      return this.directoryState.devices.length === 0;
    }
    return deviceId === activeId;
  }

  private canUseDevice(entry: DeviceDirectoryEntry): boolean {
    return entry.online || (this.isActiveDevice(entry.deviceId) && this.isConnected());
  }


  private isConnected(): boolean {
    return this.connectionState === 'connected' || this.connectionState === 'reconnecting';
  }
}
