import EventKit
import OpenBitFunMobileCore
import SwiftUI
import UIKit
import WebKit

@MainActor
final class LocalGenUiModel: ObservableObject {
    @Published private(set) var state: LocalGenUiState?
    @Published private(set) var missingAssets = false
    let media = LocalGenUiMedia(
        directory: URL.cachesDirectory.appendingPathComponent("local-genui-media").path,
        userImageDirectory: URL.applicationSupportDirectory.appendingPathComponent("local-genui-images").path
    )
    private var store: LocalGenUiStore?
    private var observation: Task<Void, Never>?

    func start() {
        guard store == nil else { return }
        guard let prompt = Self.read("harmony-prompt", extension: "txt"),
              let schema = Self.read("local-tool-schema", extension: "json") else {
            missingAssets = true
            return
        }
        let local = LocalGenUiStore.companion.create(scope: MainScope(), prompt: prompt, schema: schema)
        store = local
        observation = Task { [weak self] in
            for await state in local.state {
                guard let self, !Task.isCancelled else { return }
                self.state = state
            }
        }
    }

    func dispatch(_ intent: LocalGenUiIntent) { store?.dispatch(intent: intent) }

    nonisolated static func read(_ name: String, extension ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "genui") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    deinit {
        observation?.cancel()
        media.close()
    }
}

struct LocalGenUiButton: View {
    @ObservedObject var model: MobileAppModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(model.localized("创建小应用"))
                    .font(MobileDesignTypography.bodyMedium.font)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(OpenBitFunTheme.sidebarMuted)
        .accessibilityIdentifier("sidebar-local-bot")
    }
}

struct LocalGenUiView: View {
    @ObservedObject var model: MobileAppModel
    @ObservedObject var local: LocalGenUiModel
    var initialAppId: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var modelViewportWidth: CGFloat = 0
    @State private var modelSheet: GenUiModelPanel?

    private var centersModelSheet: Bool {
        modelViewportWidth >= MobileDesignBreakpoints.wide
    }

    private var compactModelSheet: Binding<GenUiModelPanel?> {
        Binding(
            get: { centersModelSheet ? nil : modelSheet },
            set: { value in
                if value == nil && !centersModelSheet { dismissModels() }
            }
        )
    }

    private func back() {
        guard let state = local.state else { dismiss(); return }
        if initialAppId != nil && (state.selectedSession == nil || state.failure?.name == "APP_MISSING") { dismiss() }
        else if state.openApp != nil || state.selectedSession != nil { local.dispatch(LocalGenUiIntentBack.shared) }
        else { dismiss() }
    }

    var body: some View {
        ZStack {
            if let state = local.state, let checking = state.checkingApp,
               state.openApp?.id != checking.id || state.openApp?.sourceRevision != checking.sourceRevision || state.openApp?.checking != true {
                LocalGenUiAppView(model: model, state: state, app: checking,
                                  dispatch: local.dispatch, back: {}, controls: false)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            content
                .background(OpenBitFunTheme.page)
                .accessibilityHidden(modelSheet != nil && centersModelSheet)
                .allowsHitTesting(modelSheet == nil || !centersModelSheet)
        }
        .foregroundStyle(OpenBitFunTheme.ink)
        .background(OpenBitFunTheme.page.ignoresSafeArea())
        .task { local.start() }
        .task(id: local.state?.loading) {
            if let initialAppId, local.state?.loading == false {
                local.dispatch(LocalGenUiIntentOpenApp(id: initialAppId))
            }
        }
        .onDisappear {
            clearModels()
            local.dispatch(LocalGenUiIntentClose.shared)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { modelViewportWidth = $0 }
        .onReceive(local.$state) { next in
            guard let next, let modelSheet, let pending = modelSheet.awaitingSerial else { return }
            if pending != next.modelWriteSerial {
                modelSheet.awaitingSerial = nil
                if modelSheet.setup { clearModels() }
                else { modelSheet.showEditor(nil, dispatch: local.dispatch) }
            } else if next.modelWriteFailure != nil {
                modelSheet.awaitingSerial = nil
            }
        }
        .overlay {
            if let sheet = modelSheet, centersModelSheet {
                GeometryReader { geometry in
                    ZStack {
                        MobileDesignColors.genuiModelScrim.ignoresSafeArea()
                            .onTapGesture(perform: dismissModels)
                            .accessibilityHidden(true)
                        modelManager(sheet, centered: true)
                            .frame(width: min(MobileDesignGeometry.genuiModelPanelWidth, max(0, geometry.size.width - 32)),
                                   height: min(MobileDesignGeometry.genuiModelPanelHeight, max(0, geometry.size.height - 32)))
                            .clipShape(RoundedRectangle(cornerRadius: MobileDesignGeometry.sheetTopRadius))
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape, dismissModels)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(item: compactModelSheet) { modelManager($0, centered: false) }
    }

    private func modelManager(_ sheet: GenUiModelPanel, centered: Bool) -> some View {
        LocalGenUiModelSheet(model: model, local: local, panel: sheet, centered: centered, onClose: dismissModels)
    }

    private func dismissModels() {
        if local.state?.writingModel != true { clearModels() }
    }

    private func clearModels() {
        guard modelSheet != nil else { return }
        modelSheet = nil
        local.dispatch(LocalGenUiIntentResetModelEditor.shared)
    }

    private var content: some View {
        Group {
            if let state = local.state, !state.loading {
                if state.openApp != nil || (initialAppId != nil && state.failure?.name == "APP_MISSING") {
                    LocalGenUiAppView(model: model, state: state, app: state.openApp, dispatch: local.dispatch, back: back)
                } else if let session = state.selectedSession {
                    LocalGenUiConversation(model: model, local: local, state: state, session: session,
                                           back: back, manage: {
                        let hasActiveModel = state.models.contains {
                            $0.id == state.selectedModelId && $0.hasStoredKey
                        }
                        local.dispatch(LocalGenUiIntentResetModelEditor.shared)
                        modelSheet = GenUiModelPanel(setup: !hasActiveModel, hasModels: !state.models.isEmpty)
                    })
                        .id(session.id)
                } else {
                    LocalGenUiSessionsView(model: model, local: local, state: state, back: back)
                }
            } else {
                VStack {
                    LocalGenUiHeader(title: model.localized("创建小应用"), backLabel: model.localized("返回"), back: back)
                    if local.missingAssets {
                        GenUiErrorText(model: model, failureCode: "STORAGE")
                    } else { ProgressView().padding(24) }
                    Spacer()
                }
            }
        }

    }
}

private struct LocalGenUiHeader<Trailing: View>: View {
    let title: String
    let backLabel: String
    let back: () -> Void
    var renameLabel: String?
    var rename: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 23))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backLabel)
            if let rename {
                Button(action: rename) { headerTitle }
                    .buttonStyle(.plain)
                    .accessibilityLabel(renameLabel ?? title)
                    .accessibilityValue(title)
                    .accessibilityIdentifier("local-genui-rename-session")
            } else {
                headerTitle
            }
            trailing().frame(width: 48, height: 48)
        }
        .frame(height: 56)
        .padding(.horizontal, 8)
    }

    private var headerTitle: some View {
        Text(title)
            .font(MobileDesignTypography.conversationHeaderTitle.font.weight(.medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }
}

private extension LocalGenUiHeader where Trailing == Color {
    init(title: String, backLabel: String, back: @escaping () -> Void) {
        self.init(title: title, backLabel: backLabel, back: back) { OpenBitFunTheme.transparent }
    }
}

private struct LocalGenUiSessionsView: View {
    @ObservedObject var model: MobileAppModel
    let local: LocalGenUiModel
    let state: LocalGenUiState
    let back: () -> Void
    @State private var actionSessionID: String?
    @State private var sendImage = false

    var body: some View {
        let formatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: model.appLanguage.rawValue)
            formatter.setLocalizedDateFormatFromTemplate("yyyyMMddjjmm")
            return formatter
        }()
        VStack(spacing: 0) {
            LocalGenUiHeader(title: model.localized("创建小应用"), backLabel: model.localized("返回"), back: back) {
                Menu {
                    Button(model.localized("发送图片到另一台设备")) { sendImage = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 19)).frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.localized("更多"))
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if state.sessions.isEmpty {
                        Text(model.localized("还没有创作记录"))
                            .font(MobileDesignTypography.bodyMedium.font)
                            .foregroundStyle(OpenBitFunTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(state.sessions, id: \.id) { session in
                        if session.id != state.sessions.first?.id {
                            OpenBitFunTheme.line.frame(height: 0.5)
                                .padding(.horizontal, MobileDesignGeometry.genuiHistoryHorizontalInset)
                        }
                        sessionRow(session, formatter: formatter)
                            .anchorPreference(key: LocalGenUiHistoryAnchor.self, value: .bounds) {
                                session.id == actionSessionID ? $0 : nil
                            }
                    }
                }
                .padding(.horizontal, MobileDesignGeometry.genuiHistoryHorizontalInset)
                .padding(.top, MobileDesignGeometry.genuiHistoryVerticalInset)
                .frame(maxWidth: MobileDesignGeometry.sheetContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("local-genui-history")
            if let failure = state.failure {
                GenUiErrorText(model: model, failureCode: failure.name)
                Button(model.localized("重试")) { local.dispatch(LocalGenUiIntentReload.shared) }
            }
            Button { local.dispatch(LocalGenUiIntentNewSession.shared) } label: {
                Text(model.localized("开始创作"))
                    .font(MobileDesignTypography.labelLarge.font.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: MobileDesignGeometry.sheetActionHeight)
                    .foregroundStyle(OpenBitFunTheme.contentOnAction)
                    .background(MobileDesignColors.primaryAction, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("local-genui-new-session")
            .padding(.horizontal, MobileDesignGeometry.genuiHistoryActionInset).padding(.vertical, 16)
            .frame(maxWidth: MobileDesignGeometry.sheetContentMaxWidth)
            .disabled(state.failure != nil || state.busy)
        }
        .overlayPreferenceValue(LocalGenUiHistoryAnchor.self) { anchor in
            if let anchor, let id = actionSessionID, !state.busy {
                GeometryReader { proxy in
                    let row = proxy[anchor]
                    let height = MobileDesignGeometry.genuiHistoryMenuHeight
                    let gap = MobileDesignGeometry.genuiHistoryMenuGap
                    let y = row.maxY + gap + height <= proxy.size.height ? row.maxY + gap + height / 2 : row.minY - gap - height / 2
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { actionSessionID = nil }.accessibilityHidden(true)
                        Button {
                            actionSessionID = nil
                            local.dispatch(LocalGenUiIntentDeleteSession(id: id))
                        } label: {
                            Text(model.localized("删除")).font(MobileDesignTypography.bodyMedium.font)
                                .padding(.horizontal, MobileDesignGeometry.genuiHistoryActionInset)
                                .frame(minHeight: height)
                                .background(OpenBitFunTheme.card, in: Capsule())
                                .shadow(color: OpenBitFunTheme.shadowMedium, radius: 10, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("local-genui-delete-session")
                        .accessibilityAction(.escape) { actionSessionID = nil }
                        .position(x: row.midX, y: y)
                    }
                }
            }
        }
        .sheet(isPresented: $sendImage) { LocalGenUiSendImage(model: model) }
    }

    private func sessionRow(_ session: LocalGenUiSession, formatter: DateFormatter) -> some View {
        let active = state.activeSessionId == session.id
        return Button {
            if actionSessionID == nil { local.dispatch(LocalGenUiIntentOpenSession(id: session.id)) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: MobileDesignGeometry.genuiHistoryLabelSpacing) {
                    Text(session.title.isEmpty ? model.localized("未命名会话") : session.title)
                        .font(MobileDesignTypography.bodyMedium.font.weight(active ? .medium : .regular)).lineLimit(1)
                    if let time = session.updatedAtMillis ?? session.createdAtMillis {
                        Text(formatter.string(from: Date(timeIntervalSince1970: time.doubleValue / 1000)))
                            .font(MobileDesignTypography.labelSmall.font).foregroundStyle(OpenBitFunTheme.muted).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if active && state.busy {
                    ProgressView().controlSize(.mini).frame(width: 16, height: 16)
                } else {
                    Image(systemName: active ? "checkmark" : "chevron.right")
                        .font(.system(size: active ? 16 : 12)).foregroundStyle(active ? OpenBitFunTheme.ink : OpenBitFunTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, MobileDesignGeometry.genuiHistoryHorizontalInset)
            .padding(.vertical, MobileDesignGeometry.genuiHistoryVerticalInset)
            .frame(minHeight: MobileDesignGeometry.genuiHistoryRowHeight)
            .background(active ? OpenBitFunTheme.sidebarSelection : OpenBitFunTheme.transparent,
                        in: RoundedRectangle(cornerRadius: MobileDesignGeometry.genuiHistoryRowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.busy && !active)
        .accessibilityIdentifier("local-genui-session")
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityAction(named: Text(model.localized("删除"))) {
            if !state.busy { actionSessionID = session.id }
        }
        .simultaneousGesture(LongPressGesture().onEnded { _ in
            if !state.busy { actionSessionID = session.id }
        })
    }
}

private struct LocalGenUiHistoryAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct LocalGenUiConversation: View {
    @ObservedObject var model: MobileAppModel
    let local: LocalGenUiModel
    let state: LocalGenUiState
    let session: LocalGenUiSession
    let back: () -> Void
    let manage: () -> Void
    @State private var draft = ""
    @State private var submittedDraft: String?
    @State private var focused = false
    @State private var pickerOpen = false
    @State private var actionsOpen = false
    @State private var editingTitle = false
    @State private var renameDraft = ""
    @State private var copyMenu: Int?
    @State private var fullText: String?
    @State private var viewport = CGSize.zero
    @StateObject private var scrollController = TimelineScrollController()
    @Environment(\.layoutDirection) private var layoutDirection

    private var selected: LocalGenUiModelUi? { state.models.first { $0.id == state.selectedModelId && $0.hasStoredKey } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Stable row heights keep content-size observations from feeding back
            // into SwiftUI's estimated layout as a streamed reply grows.
            VStack(spacing: MobileDesignGeometry.messageSpacing) {
                if session.messages.isEmpty {
                    Text(model.localized("描述你想创建的小应用。"))
                        .foregroundStyle(OpenBitFunTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                }
                ForEach(Array(session.messages.enumerated()), id: \.offset) { index, row in
                    GenUiTranscriptMessage(
                        model: model, message: row, app: state.apps.first { $0.id == row.appId },
                        copyMenuOpen: copyMenu == index, onCopyMenu: {
                            focused = false
                            copyMenu = copyMenu == index ? nil : index
                        }, onOpenFullText: {
                            focused = false
                            fullText = row.text
                        }, onOpenApp: {
                            if let appId = row.appId { local.dispatch(LocalGenUiIntentOpenApp(id: appId)) }
                        }
                    )
                }
                if state.recovering {
                    Text(model.localized("正在恢复上次的校验…")).foregroundStyle(OpenBitFunTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !state.streamingText.isEmpty {
                    MarkdownMessageView(text: state.streamingText, model: model, openExternalLinksOnly: true)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .background(TimelineScrollProbe(controller: scrollController))
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("local-genui-transcript")
        .onAppear { scrollController.open(session: session.id) }
        .onChange(of: state.draftAcceptedSerial) { _ in
            scrollController.followBottom()
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { viewport = geometry.size }
                    .onChange(of: geometry.size) { viewport = $0 }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { floatingHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { floatingComposer }
        .openBitFunAdaptiveModal(
            isPresented: Binding(get: { fullText != nil }, set: { if !$0 { fullText = nil } }),
            placement: fullTextPlacement
        ) {
            GenUiFullTextSheet(text: fullText ?? "") { fullText = nil }
        }
        .overlayPreferenceValue(GenUiCopyAnchor.self) { anchor in
            GeometryReader { geometry in
                if let copyMenu, session.messages.indices.contains(copyMenu), let anchor {
                    let frame = geometry[anchor]
                    let menuHeight = MobileDesignGeometry.compactPopoverActionHeight * 3 + 8
                    let below = frame.maxY + 4
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { self.copyMenu = nil }.accessibilityHidden(true)
                        GenUiCopyMenu(model: model, source: session.messages[copyMenu].text) { self.copyMenu = nil }
                            .offset(
                                x: max(8, min(frame.minX, geometry.size.width - MobileDesignGeometry.compactPopoverWidth - 8)),
                                y: below + menuHeight < geometry.size.height ? below : max(8, frame.minY - menuHeight - 4)
                            )
                    }
                }
            }
        }
        .overlayPreferenceValue(SessionActionsAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if actionsOpen, let anchor {
                    let button = geometry[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { actionsOpen = false }.accessibilityHidden(true)
                        ConversationActionsPopover(
                            model: model, onDismiss: { actionsOpen = false }, creationHistory: back,
                            deleteSession: session.messages.isEmpty || state.busy ? nil : {
                                local.dispatch(LocalGenUiIntentDeleteSession(id: session.id))
                            }
                        )
                        .offset(x: max(8, button.maxX - MobileDesignGeometry.popoverWidth), y: button.maxY + 8)
                        .transition(.offset(x: 8, y: -8).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: actionsOpen)
        .overlayPreferenceValue(GenUiModelControlAnchor.self) { anchor in
            GeometryReader { geometry in
                if pickerOpen, let anchor {
                    let frame = geometry[anchor]
                    let width = min(MobileDesignGeometry.composerModelSelectorWidth, geometry.size.width - 24)
                    ZStack(alignment: .bottomLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { pickerOpen = false }
                            .accessibilityHidden(true)
                        modelPicker(spaceAbove: frame.minY)
                            .frame(width: width)
                            .padding(.leading, max(8, min(frame.midX - width / 2, geometry.size.width - width - 8)))
                            .padding(.bottom, max(8, geometry.size.height - frame.minY + 8))
                    }
                }
            }
        }
        .onAppear { draft = state.draft }
        .onChange(of: state.draftAcceptedSerial) { serial in
            if let submitted = submittedDraft {
                if draft == submitted {
                    draft = ""
                } else {
                    local.dispatch(LocalGenUiIntentEditDraft(sessionId: session.id, draftAcceptedSerial: serial, text: draft))
                }
            }
            submittedDraft = nil
        }
    }

    private var floatingHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                LocalGenUiHeader(title: session.title.isEmpty ? model.localized("创建小应用") : session.title,
                                 backLabel: model.localized("返回"), back: back, renameLabel: model.localized("重命名"),
                                 rename: session.messages.isEmpty ? nil : {
                    focused = false
                    actionsOpen = false
                    renameDraft = session.title
                    editingTitle = true
                }) {
                    Button {
                        focused = false
                        editingTitle = false
                        actionsOpen.toggle()
                    } label: {
                        ReferenceGlyph(assetName: "MoreGlyph", width: 23, height: 7)
                            .foregroundStyle(OpenBitFunTheme.muted)
                            .frame(width: MobileDesignGeometry.controlTouchSize, height: MobileDesignGeometry.controlTouchSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.localized("会话操作"))
                    .accessibilityIdentifier("local-genui-session-actions")
                    .anchorPreference(key: SessionActionsAnchorKey.self, value: .bounds) { $0 }
                }
                if editingTitle {
                    ConversationTitleEditor(model: model, draft: $renameDraft, onSave: {
                        local.dispatch(LocalGenUiIntentRenameSession(id: session.id, title: renameDraft))
                        editingTitle = false
                    }, onCancel: { editingTitle = false })
                }
            }
            .background(MobileDesignColors.pageBgOverlay)
            .background(.ultraThinMaterial)
            LinearGradient(colors: [OpenBitFunTheme.page, OpenBitFunTheme.page.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: MobileDesignGeometry.conversationEdgeFadeHeight)
                .allowsHitTesting(false)
        }
    }

    private var floatingComposer: some View {
        VStack(spacing: 0) {
            if let failure = state.failure { GenUiErrorText(model: model, failureCode: failure.name) }
            composer.frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(stops: [
                .init(color: MobileDesignColors.pageBgFade, location: 0),
                .init(color: MobileDesignColors.pageBgOverlay, location: 0.45),
                .init(color: MobileDesignColors.pageBgOverlay, location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    private var fullTextPlacement: SettingsPlacement {
        let width = Int32(viewport.width)
        return SettingsPlacementPolicy.shared.resolve(
            input: AdaptiveLayoutInput(
                viewportWidth: width, viewportHeight: Int32(viewport.height), isFolded: false,
                isExpandedFoldable: false, isHoverOperate: false,
                wideLayoutMatched: width >= ConversationLayoutPolicy.shared.MD_MIN_WIDTH,
                verticalCreases: [], horizontalCreases: [], isRtl: layoutDirection == .rightToLeft
            ),
            kind: .userMessageFullText
        )
    }

    private func modelPicker(spaceAbove: CGFloat) -> some View {
        let profiles = state.models.filter { $0.hasStoredKey && $0.id != state.selectedModelId }
        let options = selected.map { [$0] + profiles } ?? profiles
        let rowHeight = MobileDesignGeometry.composerModelSelectorRowHeight
        let rowGap = MobileDesignGeometry.composerModelSelectorRowGap
        let count = min(5, options.count)
        let listHeight = rowHeight * CGFloat(count) + rowGap * CGFloat(max(0, count - 1))
        return VStack(spacing: rowGap) {
            ScrollView {
                VStack(spacing: MobileDesignGeometry.composerModelSelectorRowGap) {
                    ForEach(options, id: \.id) { option in
                        let current = option.id == state.selectedModelId
                        Button {
                            pickerOpen = false
                            local.dispatch(LocalGenUiIntentSelectModel(id: option.id))
                        } label: {
                            HStack(spacing: 10) {
                                Group {
                                    if current { Image(systemName: "checkmark.circle").font(.system(size: 16)) }
                                    else { Color.clear }
                                }
                                .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.composerLabel).font(MobileDesignTypography.bodySmall.font.weight(.medium)).lineLimit(1)
                                    Text(option.composerDetails).font(MobileDesignTypography.labelSmall.font)
                                        .foregroundStyle(OpenBitFunTheme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: rowHeight)
                            .background(current ? OpenBitFunTheme.soft : Color.clear,
                                in: RoundedRectangle(cornerRadius: MobileDesignGeometry.composerModelSelectorRowRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("local-genui-model-option")
                        .accessibilityLabel(option.composerLabel)
                        .accessibilityValue(option.composerDetails)
                        .accessibilityAddTraits(current ? .isSelected : [])
                    }
                }
            }
            .frame(height: min(listHeight, max(0, spaceAbove - rowHeight - 48)))
            Divider().overlay(OpenBitFunTheme.line)
            Button {
                pickerOpen = false
                focused = false
                manage()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").font(.system(size: 16)).frame(width: 20)
                    Text(model.localized("管理模型")).font(MobileDesignTypography.bodySmall.font.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(minHeight: MobileDesignGeometry.composerModelSelectorRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(OpenBitFunTheme.card, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.composerModelSelectorRadius))
        .overlay(RoundedRectangle(cornerRadius: MobileDesignGeometry.composerModelSelectorRadius)
            .strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
        .shadow(color: OpenBitFunTheme.shadowSubtle, radius: 18, y: 7)
        .foregroundStyle(OpenBitFunTheme.ink)
        .accessibilityIdentifier("local-genui-model-menu")
        .accessibilityAction(.escape) { pickerOpen = false }
    }

    private func composerInput(expanded: Bool) -> some View {
        GenUiComposerTextView(
            text: draft, acceptedSerial: state.draftAcceptedSerial, expanded: expanded,
            focused: $focused, placeholder: model.localized("向 OpenBitFun 提问")
        ) { text in
            guard local.state?.draftAcceptedSerial == state.draftAcceptedSerial,
                  local.state?.selectedSession?.id == session.id else { return }
            draft = text
            local.dispatch(LocalGenUiIntentEditDraft(sessionId: session.id, draftAcceptedSerial: state.draftAcceptedSerial, text: text))
        }
        .padding(.horizontal, 4)
    }

    private var composer: some View {
        let allowed = state.busy || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let expanded = ChatComposerPolicy.shared.isExpanded(
            text: draft, inputFocused: focused, quickActionsOpen: false, modelSelectorOpen: false
        )
        let shape = RoundedRectangle(cornerRadius: MobileDesignGeometry.composerExpandedRadius)
        return VStack(spacing: 2) {
            composerInput(expanded: expanded)
            HStack {
                let modelLabel = selected?.composerLabel ?? model.localized("配置模型")
                Button {
                    if selected == nil {
                        focused = false
                        manage()
                    } else {
                        pickerOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        IntrinsicWidthCapLayout(maxWidth: 192) {
                            Text(modelLabel).font(MobileDesignTypography.bodySmall.font.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(selected == nil ? OpenBitFunTheme.ink : OpenBitFunTheme.muted)
                        }
                        Image(systemName: selected == nil ? "plus" : pickerOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(minHeight: MobileDesignGeometry.composerActionSize)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .disabled(state.busy)
                .accessibilityLabel(modelLabel)
                .accessibilityIdentifier("local-genui-model-control")
                .anchorPreference(key: GenUiModelControlAnchor.self, value: .bounds) { $0 }
                Spacer()
                Button {
                    if state.busy { local.dispatch(LocalGenUiIntentCancel.shared) }
                    else if selected == nil { focused = false; manage() }
                    else {
                        submittedDraft = draft
                        local.dispatch(LocalGenUiIntentSend(sessionId: session.id, draftAcceptedSerial: state.draftAcceptedSerial, text: draft))
                    }
                } label: {
                    Group {
                        if state.busy {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(OpenBitFunTheme.contentOnAction).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(allowed ? OpenBitFunTheme.contentOnAction : OpenBitFunTheme.muted.opacity(0.38))
                        }
                    }
                        .frame(width: MobileDesignGeometry.composerPrimarySurfaceSize, height: MobileDesignGeometry.composerPrimarySurfaceSize)
                        .background(allowed ? OpenBitFunTheme.ink : Color.clear, in: Circle())
                        .frame(width: MobileDesignGeometry.composerActionSize, height: MobileDesignGeometry.composerActionSize)
                        .background(allowed ? Color.clear : OpenBitFunTheme.soft, in: Circle())
                        .contentShape(Circle())
                }
                .disabled(!allowed)
                .accessibilityLabel(model.localized(state.busy ? "停止" : "发送"))
            }
            .frame(height: MobileDesignGeometry.composerExpandedActionRowHeight)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.top, expanded ? 4 : 2).padding(.bottom, 2)
        .frame(minHeight: expanded ? MobileDesignGeometry.composerExpandedHeight : 0)
        .background(MobileDesignColors.cardOverlay, in: shape)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
        .shadow(color: OpenBitFunTheme.shadowSubtle, radius: 2, y: 2)
        .padding(.horizontal, MobileDesignGeometry.conversationOverlaySideInset)
        .padding(.top, 8).padding(.bottom, 14)
    }
}

/// Keep the editing view and first responder stable when an accepted send clears
/// the draft. UIKit's paragraph style also applies the shared line height to
/// editable text, including wraps and newlines.
private struct GenUiComposerTextView: UIViewRepresentable {
    let text: String
    let acceptedSerial: Int32
    let expanded: Bool
    @Binding var focused: Bool
    let placeholder: String
    let onEdit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EditorView {
        let view = EditorView()
        let input = view.input
        input.backgroundColor = UIColor(OpenBitFunTheme.transparent)
        input.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 8, right: 0)
        input.textContainer.lineFragmentPadding = 0
        input.contentInsetAdjustmentBehavior = .never
        input.showsVerticalScrollIndicator = false
        input.accessibilityIdentifier = "local-genui-composer"
        input.delegate = context.coordinator
        view.hint.textColor = UIColor(OpenBitFunTheme.muted)
        view.hint.isAccessibilityElement = false
        view.addSubview(input)
        view.addSubview(view.hint)
        return view
    }

    func updateUIView(_ view: EditorView, context: Context) {
        let previousSerial = context.coordinator.editor.acceptedSerial
        context.coordinator.editor = self
        let input = view.input
        input.accessibilityLabel = placeholder
        input.textContainer.maximumNumberOfLines = expanded ? 0 : 1
        input.textContainer.lineBreakMode = expanded ? .byWordWrapping : .byTruncatingTail
        if input.isScrollEnabled != expanded { input.isScrollEnabled = expanded }

        let (font, lineHeight) = typography(for: input)
        view.hint.text = placeholder
        view.hint.font = font
        view.hintHeight = lineHeight
        let newFont = input.font != font
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: UIColor(OpenBitFunTheme.ink)
        ]
        if (input.text != text || newFont) && (input.markedTextRange == nil || previousSerial != acceptedSerial) {
            let selection = input.selectedRange
            input.font = font
            input.attributedText = NSAttributedString(string: text, attributes: attributes)
            let length = (text as NSString).length
            let start = min(selection.location, length)
            input.selectedRange = NSRange(location: start, length: min(selection.length, length - start))
            input.typingAttributes = attributes
        }
        view.setNeedsLayout()
        if !focused && input.isFirstResponder { input.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EditorView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let input = uiView.input
        let (_, lineHeight) = typography(for: input)
        let insets = input.textContainerInset
        let verticalPadding = insets.top + insets.bottom
        if !expanded {
            return CGSize(width: width, height: max(MobileDesignGeometry.composerInputHeight, lineHeight + verticalPadding))
        }
        let measured = input.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let capped = min(ceil(measured), 4 * lineHeight + verticalPadding)
        return CGSize(width: width, height: max(MobileDesignGeometry.composerExpandedInputRowHeight, capped))
    }

    final class EditorView: UIView {
        let input = UITextView(usingTextLayoutManager: false)
        let hint = UILabel()
        var hintHeight: CGFloat = 0

        override func layoutSubviews() {
            super.layoutSubviews()
            input.frame = bounds
            hint.isHidden = !input.text.isEmpty
            hint.frame = CGRect(x: 0, y: input.textContainerInset.top, width: bounds.width, height: hintHeight)
        }
    }

    private func typography(for view: UITextView) -> (UIFont, CGFloat) {
        let token = MobileDesignTypography.bodyLarge
        let metrics = UIFontMetrics(forTextStyle: token.textStyle)
        let font = metrics.scaledFont(for: .systemFont(ofSize: token.size, weight: token.weight),
                                     compatibleWith: view.traitCollection)
        let lineHeight = metrics.scaledValue(for: token.lineHeight, compatibleWith: view.traitCollection)
        return (font, lineHeight)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var editor: GenUiComposerTextView

        init(_ editor: GenUiComposerTextView) { self.editor = editor }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !editor.focused { editor.focused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if editor.focused { editor.focused = false }
        }

        func textViewDidChange(_ textView: UITextView) {
            // The OS owns composing text until the input method commits it.
            textView.superview?.setNeedsLayout()
            guard textView.markedTextRange == nil else { return }
            editor.onEdit(textView.text)
        }
    }
}

private struct GenUiModelControlAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct GenUiErrorText: View {
    @ObservedObject var model: MobileAppModel
    let failureCode: String

    private var message: String {
        switch failureCode {
        case "STORAGE": return "无法读取或保存本机数据。"
        case "INVALID_MODEL": return "请检查 API 地址、模型名称和 API 密钥。"
        case "MISSING_MODEL": return "请配置模型后继续。"
        case "AUTHENTICATION": return "模型服务拒绝了 API 密钥。"
        case "RATE_LIMIT": return "模型服务请求过于频繁，请稍后重试。"
        case "NETWORK": return "无法连接模型服务。"
        case "INVALID_RESPONSE": return "模型没有返回可用的小应用。"
        case "APP_MISSING": return "找不到这个应用了。"
        case "STATE_MIGRATION_REQUIRED": return "新版本和已有数据不兼容，已保留原来的版本"
        default: return "无法读取或保存本机数据。"
        }
    }

    var body: some View {
        Text(model.localized(message))
            .font(MobileDesignTypography.bodySmall.font)
            .foregroundStyle(OpenBitFunTheme.statusDanger)
            .padding(8)
    }
}

enum LocalGenUiLook: String, CaseIterable, Identifiable {
    case classic, aurora, blueprint, celadon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "原生"
        case .aurora: return "极光"
        case .blueprint: return "蓝图"
        case .celadon: return "青瓷"
        }
    }
}

@MainActor
final class LocalGenUiThumbnails: ObservableObject {
    static let shared = LocalGenUiThumbnails()
    nonisolated static let maximumPixels = 480

    @Published private var versions: [String: UInt64] = [:]
    private let writer = Writer()
    private var captureOrder: UInt64 = 0

    struct Capture: Sendable {
        let id: String
        let sourceRevision: Int32
        let order: UInt64
    }

    func version(for id: String) -> UInt64 { versions[id, default: 0] }

    func read(_ id: String) async -> UIImage? {
        guard let url = Self.url(id) else { return nil }
        return await Task.detached(priority: .utility) {
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return Self.squarePreview(image)
        }.value
    }

    private nonisolated static func squarePreview(_ image: UIImage) -> UIImage {
        guard let pixels = image.cgImage else { return image }
        let side = min(pixels.width, pixels.height)
        // Earlier builds stored the whole WebView instead of its top square.
        let square = pixels.width == pixels.height ? pixels : pixels.cropping(to: CGRect(x: 0, y: 0, width: side, height: side))
        guard let square else { return image }
        if side <= maximumPixels { return UIImage(cgImage: square, scale: image.scale, orientation: image.imageOrientation) }
        guard let context = CGContext(data: nil, width: maximumPixels, height: maximumPixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: maximumPixels, height: maximumPixels))
        return UIImage(cgImage: context.makeImage() ?? square, scale: image.scale, orientation: image.imageOrientation)
    }

    func beginCapture(id: String, sourceRevision: Int32) -> Capture {
        captureOrder += 1
        return Capture(id: id, sourceRevision: sourceRevision, order: captureOrder)
    }

    func save(_ data: Data, capture: Capture) async {
        guard let url = Self.url(capture.id), await writer.save(data, to: url, capture: capture) else { return }
        versions[capture.id, default: 0] += 1
    }

    private static func url(_ id: String) -> URL? {
        guard id.hasPrefix("local-genui:"),
              let uuid = UUID(uuidString: String(id.dropFirst("local-genui:".count))),
              let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory.appendingPathComponent("GenUIThumbnails", isDirectory: true)
            .appendingPathComponent(uuid.uuidString.lowercased() + ".png")
    }

    private actor Writer {
        private var lastWrite: [URL: Capture] = [:]

        func save(_ data: Data, to url: URL, capture: Capture) -> Bool {
            if let previous = lastWrite[url] {
                if previous.sourceRevision > capture.sourceRevision { return false }
                if previous.sourceRevision == capture.sourceRevision && previous.order > capture.order { return false }
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                lastWrite[url] = capture
                return true
            } catch {
                // The gallery can still open the app without a thumbnail.
                return false
            }
        }
    }
}

struct LocalGenUiPreview<Content: View>: View {
    private struct Request: Equatable {
        let id: String
        let version: UInt64
    }

    let id: String
    @ViewBuilder let content: (UIImage?) -> Content
    @ObservedObject private var thumbnails = LocalGenUiThumbnails.shared
    @State private var loaded: (id: String, image: UIImage?)?

    var body: some View {
        let request = Request(id: id, version: thumbnails.version(for: id))
        content(loaded?.id == id ? loaded?.image : nil)
            .task(id: request) {
                let image = await thumbnails.read(request.id)
                guard !Task.isCancelled else { return }
                loaded = (request.id, image)
            }
    }
}

private struct LocalGenUiAppView: View {
    private struct CalendarNotice {
        let id = UUID()
        let message: String
    }

    @ObservedObject var model: MobileAppModel
    let state: LocalGenUiState
    let app: LocalGenUiApp?
    let dispatch: (LocalGenUiIntent) -> Void
    let back: () -> Void
    var controls = true
    @State private var capture = 0
    @State private var calendarNotice: CalendarNotice?
    @State private var imageTransfer: LocalGenUiImageRequest?
    @StateObject private var camera = LocalGenUiCamera()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("local_genui_look") private var look = LocalGenUiLook.aurora

    private var showsProgress: Bool {
        guard let app else { return false }
        return state.recovering || state.repairing || app.streaming || app.checking
    }

    private var status: String? {
        guard let app else { return model.localized("找不到这个应用了。") }
        if state.recovering { return model.localized("正在恢复上次的校验…") }
        if state.repairing { return model.localized("正在自动修正…") }
        if showsProgress { return model.localized("正在生成…") }
        if app.failedValidation { return model.localized("没有生成成功") }
        if state.failure?.name == "STATE_MIGRATION_REQUIRED" {
            return model.localized("新版本和已有数据不兼容，已保留原来的版本")
        }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            let safe = geometry.safeAreaInsets
            let chrome = controls ? MobileDesignGeometry.genuiAppControlTopInset + MobileDesignGeometry.genuiAppControlSize : 0
            let left = layoutDirection == .leftToRight ? safe.leading : safe.trailing
            let right = layoutDirection == .leftToRight ? safe.trailing : safe.leading
            if let app, !app.failedValidation {
                LocalGenUiWebView(
                    app: app, media: model.localGenUi.media, stateSerial: Int(state.stateWriteSerial), conflict: state.stateWriteConflict,
                    scheme: scheme == .dark ? "dark" : "light",
                    locale: model.appLanguage == .english ? "en-US" : "zh-CN",
                    look: look.rawValue,
                    insets: LocalGenUiDocument.shared.insets(
                        top: Int32((safe.top + chrome).rounded()),
                        left: Int32(left.rounded()),
                        right: Int32(right.rounded()),
                        bottom: Int32(safe.bottom.rounded())
                    ),
                    dispatch: dispatch,
                    capture: capture,
                    storeThumbnail: { dispatch(LocalGenUiIntentSetGallery(id: app.id, added: true)) },
                    onCalendarResult: reportCalendarResult,
                    camera: controls ? camera : nil,
                    cameraVisible: controls && scenePhase == .active,
                    presentCollaboration: controls ? { imageTransfer = $0 } : nil
                )
                .ignoresSafeArea()
            } else {
                OpenBitFunTheme.page.ignoresSafeArea()
            }
            if controls {
                HStack {
                    Button(action: back) { control("chevron.left") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.localized("返回"))
                    Spacer()
                    if let status {
                        IntrinsicWidthCapLayout(maxWidth: MobileDesignGeometry.genuiAppStatusMaxWidth) {
                            HStack(spacing: 6) {
                                if showsProgress { ProgressView().scaleEffect(0.7) }
                                Text(status)
                                    .font(MobileDesignTypography.labelSmall.font)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, MobileDesignGeometry.genuiAppStatusHorizontalPadding)
                            .frame(height: MobileDesignGeometry.genuiAppStatusHeight)
                        }
                        .background(MobileDesignColors.floatingPanelBg, in: Capsule())
                        .accessibilityIdentifier(app?.reopening == true ? "local-genui-review-checkpoint" :
                            showsProgress ? "local-genui-progress" : "local-genui-app-status")
                        Spacer()
                    }
                    if let app, !showsProgress, !app.failedValidation {
                        Menu {
                            if state.selectedSession == nil && state.sessions.contains(where: { $0.id == app.sessionId }) {
                                Button(model.localized("GenUI.Conversation")) {
                                    dispatch(LocalGenUiIntentOpenSession(id: app.sessionId))
                                }
                            }
                            Button(model.localized(app.inGallery ? "从小应用移除" : "添加到小应用")) {
                                if app.inGallery {
                                    dispatch(LocalGenUiIntentSetGallery(id: app.id, added: false))
                                } else { capture += 1 }
                            }
                        } label: { control("ellipsis") }
                        .accessibilityLabel(model.localized("小应用操作"))
                    } else {
                        Color.clear.frame(width: MobileDesignGeometry.genuiAppControlSize, height: MobileDesignGeometry.genuiAppControlSize)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, max(0, MobileDesignGeometry.genuiAppControlSideInset - safe.leading))
                .padding(.trailing, max(0, MobileDesignGeometry.genuiAppControlSideInset - safe.trailing))
                .padding(.top, MobileDesignGeometry.genuiAppControlTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            if controls && app?.failedValidation == false && camera.presenting {
                let width = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
                let height = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
                LocalGenUiCameraPreview(
                    camera: camera, landscape: width > height,
                    compact: height < MobileDesignGeometry.genuiCameraCompactHeightThreshold,
                    label: model.localized("摄像头已开")
                )
                .padding(.trailing, MobileDesignGeometry.genuiCameraSideInset)
                .padding(.bottom, MobileDesignGeometry.genuiCameraBottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if let notice = calendarNotice?.message {
                Text(notice)
                    .font(MobileDesignTypography.bodySmall.font)
                    .foregroundStyle(OpenBitFunTheme.contentOnAction)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(OpenBitFunTheme.toastBackground, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 72).padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $imageTransfer) { transfer in
            LocalGenUiReceiveImage(model: model, media: model.localGenUi.media, transfer: transfer)
        }
        .onChange(of: scenePhase) { next in
            if next == .background { imageTransfer = nil }
        }
        .onChange(of: app?.id) { _ in calendarNotice = nil }
        .onChange(of: app?.sourceRevision) { _ in calendarNotice = nil }
        .task(id: calendarNotice?.id) {
            guard calendarNotice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { calendarNotice = nil }
        }
    }

    private func reportCalendarResult(_ action: LocalGenUiCalendarAction, _ value: Int64?) {
        guard let value else {
            calendarNotice = CalendarNotice(message: model.localized("无法访问 OpenBitFun 日历。"))
            return
        }
        let format: String
        switch action {
        case .create: format = "已添加日程（编号 %lld）"
        case .update: format = "已更新日程（编号 %lld）"
        case .delete: format = "已删除日程（编号 %lld）"
        default: format = "找到 %lld 个日程"
        }
        calendarNotice = CalendarNotice(message: String(format: model.localized(format), value))
    }

    private func control(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .frame(width: MobileDesignGeometry.genuiAppControlSize, height: MobileDesignGeometry.genuiAppControlSize)
            .foregroundStyle(OpenBitFunTheme.ink)
            .background(.thinMaterial, in: Circle())
            .shadow(color: OpenBitFunTheme.shadowSubtle, radius: 12, y: 2)
    }
}

private struct LocalGenUiWebView: UIViewRepresentable {
    let app: LocalGenUiApp
    let media: LocalGenUiMedia
    let stateSerial: Int
    let conflict: Bool
    let scheme: String
    let locale: String
    let look: String
    let insets: String
    let dispatch: (LocalGenUiIntent) -> Void
    let capture: Int
    let storeThumbnail: () -> Void
    let onCalendarResult: (LocalGenUiCalendarAction, Int64?) -> Void
    let camera: LocalGenUiCamera?
    let cameraVisible: Bool
    let presentCollaboration: ((LocalGenUiImageRequest?) -> Void)?
    private static let origin = URL(string: "openbitfun-genui://runtime/index.html")!

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "openbitfun-genui")
        let controller = configuration.userContentController
        controller.add(context.coordinator, name: "genuiNative")
        controller.addUserScript(WKUserScript(
            source: "window.genuiNative = { post: message => window.webkit.messageHandlers.genuiNative.postMessage(message) };",
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        // The iOS 26 simulator's WebKit system-ui fallback can resolve Chinese
        // to LastResort. Use explicit native families, as the offline tools do.
        controller.addUserScript(WKUserScript(
            source: """
            const genUiFontStyle = document.createElement('style');
            genUiFontStyle.textContent = `
              :root, :root .gen-ui-application.gen-ui-application--harmony-genui {
                --openbitfun-font-sans: 'Helvetica Neue', 'PingFang SC', 'Apple Symbols', 'Apple Color Emoji', sans-serif;
                --openbitfun-font-mono: Menlo, 'PingFang SC', 'Apple Symbols', monospace;
                --font-sans: var(--openbitfun-font-sans);
                --font-mono: var(--openbitfun-font-mono);
                --hm-body-font: var(--font-sans);
              }
              :root .gen-ui-application.gen-ui-application--harmony-genui:is([data-hm-font="default"], [data-hm-font="sans"]) {
                --hm-heading-font: var(--hm-body-font);
              }
            `;
            document.head.append(genUiFontStyle);
            """,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        context.coordinator.web = view
        view.load(URLRequest(url: Self.origin))
        return view
    }

    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.apply(self) }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "genuiNative")
        web.navigationDelegate = nil
        coordinator.restoreOrientation()
        coordinator.cancelImageLoads()
        coordinator.collaboration = nil
        coordinator.current?.camera?.stop()
        coordinator.web = nil
        coordinator.current = nil
    }

    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var current: LocalGenUiWebView?
        private var booted = false
        private var actionTime = 0.0
        private var hapticTime = 0.0
        private var orientationRequested = false
        private let calendarWriter = LocalGenUiCalendarWriter.shared
        private var calendarPending: Set<String> = []
        private var calendarCompleted: Set<String> = []
        private var calendarCalls: [TimeInterval] = []
        private var imageCalls: [TimeInterval] = []
        var collaboration: LocalGenUiCollaborationRequest?
        private let gestures = LocalGenUiGestures()
        private var imageLoads: [ObjectIdentifier: Task<Void, Never>] = [:]
        private let manifest = LocalGenUiModel.read("runtime-manifest", extension: "json")
        private let catalog = LocalGenUiModel.read("catalog", extension: "json") ?? ""

        func apply(_ next: LocalGenUiWebView) {
            let previous = current
            current = next
            if previous?.app.id != next.app.id { restoreOrientation() }
            if previous?.cameraVisible != next.cameraVisible {
                updateCamera(replies: gestures.setVisible(value: next.cameraVisible))
            }
            guard booted else { return }
            let changed = next.app.id != previous?.app.id || next.app.sourceRevision != previous?.app.sourceRevision ||
                next.app.streaming != previous?.app.streaming || next.app.checking != previous?.app.checking ||
                next.app.reopening != previous?.app.reopening || next.locale != previous?.locale
            if changed { mount() }
            else if next.app.source != previous?.app.source { send(LocalGenUiDocument.shared.updateSource(app: next.app)) }
            else if next.stateSerial != previous?.stateSerial { send(LocalGenUiDocument.shared.state(app: next.app, conflict: next.conflict)) }
            if !changed && (next.scheme != previous?.scheme || next.look != previous?.look) {
                send(LocalGenUiDocument.shared.theme(scheme: next.scheme, look: next.look))
            }
            if next.insets != previous?.insets { send(next.insets) }
            if next.capture > 0 && next.capture != previous?.capture { takeSnapshot(next, addToGallery: true) }
        }

        private func takeSnapshot(_ view: LocalGenUiWebView, addToGallery: Bool) {
            guard let web, !web.bounds.isEmpty else {
                if addToGallery { view.storeThumbnail() }
                return
            }
            let side = min(web.bounds.width, web.bounds.height)
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(origin: web.bounds.origin, size: CGSize(width: side, height: side))
            let scale = max(1, web.traitCollection.displayScale)
            config.snapshotWidth = NSNumber(value: Double(min(side, CGFloat(LocalGenUiThumbnails.maximumPixels) / scale)))
            let thumbnails = LocalGenUiThumbnails.shared
            let capture = thumbnails.beginCapture(id: view.app.id, sourceRevision: view.app.sourceRevision)
            web.takeSnapshot(with: config) { [weak self] image, _ in
                let id = view.app.id
                guard self?.current?.app.id == id, self?.current?.app.sourceRevision == view.app.sourceRevision else { return }
                guard let image, let data = image.pngData() else {
                    if addToGallery { view.storeThumbnail() }
                    return
                }
                Task { @MainActor [weak self] in
                    await thumbnails.save(data, capture: capture)
                    if addToGallery && self?.current?.app.id == id && self?.current?.app.sourceRevision == view.app.sourceRevision {
                        view.storeThumbnail()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.targetFrame?.isMainFrame == true && navigationAction.request.url == LocalGenUiWebView.origin ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
            guard let url = task.request.url, url.scheme == "openbitfun-genui", url.host == "runtime",
                  url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil else {
                task.didFailWithError(URLError(.resourceUnavailable))
                return
            }
            if let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
               path.hasPrefix("/host-image/"), task.request.httpMethod == "GET", let media = current?.media {
                let id = ObjectIdentifier(task)
                let relative = String(path.dropFirst("/host-image".count))
                imageLoads[id] = Task { @MainActor [weak self] in
                    let scoped = relative.hasPrefix("/collaboration/")
                    let appID = self?.current?.app.id
                    let image: LocalGenUiImage?
                    if scoped, let appID {
                        image = try? await media.readCollaboration(path: relative, appId: appID)
                    } else {
                        image = try? await media.read(path: relative)
                    }
                    guard !Task.isCancelled, self?.imageLoads.removeValue(forKey: id) != nil else { return }
                    guard let image, !scoped || self?.current?.app.id == appID else {
                        task.didFailWithError(URLError(.resourceUnavailable))
                        return
                    }
                    let data = image.toNSData() as Data
                    let headers = ["Content-Type": image.mimeType, "Cache-Control": "no-store"]
                    if scoped, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) {
                        task.didReceive(response)
                    } else {
                        task.didReceive(URLResponse(url: url, mimeType: image.mimeType, expectedContentLength: data.count, textEncodingName: nil))
                    }
                    task.didReceive(data)
                    task.didFinish()
                }
                return
            }
            let files = ["/index.html": "text/html", "/runtime.js": "text/javascript",
                         "/runtime.css": "text/css", "/fonts/hm-symbol/HMSymbolVF.ttf": "font/ttf"]
            guard let mime = files[url.path],
                  let folder = Bundle.main.resourceURL,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("genui/runtime" + url.path)) else {
                task.didFailWithError(URLError(.resourceUnavailable))
                return
            }
            task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "UTF-8"))
            task.didReceive(data)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
            imageLoads.removeValue(forKey: ObjectIdentifier(task))?.cancel()
        }

        func cancelImageLoads() {
            for load in imageLoads.values { load.cancel() }
            imageLoads.removeAll()
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url == LocalGenUiWebView.origin,
                  let raw = message.body as? String, raw.utf8.count <= 512 * 1024, let current,
                  let event = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else { return }
            let type = event["type"] as? String
            if type == "boot" {
                booted = true
                send(current.insets)
                mount()
                return
            }
            let app = current.app
            if type == "image_search" {
                guard let search = LocalGenUiMedia.companion.request(raw: raw, app: app) else { return }
                let now = ProcessInfo.processInfo.systemUptime
                imageCalls.removeAll { now - $0 >= 60 }
                guard imageCalls.count < 60 else { send(LocalGenUiMedia.companion.refused(request: search)); return }
                imageCalls.append(now)
                let media = current.media
                Task { @MainActor [weak self] in
                    let reply = (try? await media.search(request: search)) ?? LocalGenUiMedia.companion.refused(request: search)
                    guard let self, let mounted = self.current?.app,
                          mounted.id == app.id, mounted.sourceRevision == app.sourceRevision, !mounted.checking else { return }
                    send(reply)
                }
                return
            }
            if app.checking {
                if type == "ready" {
                    #if DEBUG
                    if app.reopening && ProcessInfo.processInfo.arguments.contains("--hold-genui-reopen-for-testing") {
                        return
                    }
                    #endif
                    if let message = LocalGenUiDocument.shared.merge(app: app) { send(message) }
                    send(LocalGenUiDocument.shared.probe(app: app))
                } else if let intent = LocalGenUiDocument.shared.readIntent(raw: raw, mounted: app, catalog: catalog) {
                    current.dispatch(intent)
                }
                return
            }
            guard (event["appId"] as? String) == app.id, !app.streaming else { return }
            if type == "preview_ready" {
                if current.cameraVisible && (event["sourceRevision"] as? NSNumber)?.int32Value == app.sourceRevision {
                    takeSnapshot(current, addToGallery: false)
                }
                return
            }
            if let intent = LocalGenUiDocument.shared.readIntent(raw: raw, mounted: app, catalog: catalog) {
                if intent is LocalGenUiIntentContinueConversation {
                    let now = ProcessInfo.processInfo.systemUptime
                    guard now - actionTime >= 1 else { return }
                    actionTime = now
                }
                current.dispatch(intent)
                return
            }
            let request = event["requestId"] as? String
            switch type {
            case "collaboration":
                handleCollaboration(raw, current)
            case "capability":
                updateCamera(replies: gestures.receive(raw: raw))
            case "orientation":
                guard (event["sourceRevision"] as? NSNumber)?.int32Value == app.sourceRevision else { return }
                let mask: UIInterfaceOrientationMask
                switch event["orientation"] as? String {
                case "portrait": mask = .portrait
                case "landscape": mask = .landscape
                case "auto": restoreOrientation(); return
                default: return
                }
                guard let scene = web?.window?.windowScene else { return }
                orientationRequested = true
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            case "action":
                if let action = event["action"] as? String, LocalGenUiCalendar.shared.isCalendarAction(name: action),
                   (event["sourceRevision"] as? NSNumber)?.int32Value == app.sourceRevision {
                    runCalendar(raw, app: app, requestID: request.flatMap { $0.isEmpty || $0.count > 64 ? nil : $0 })
                }
            case "haptic":
                let now = ProcessInfo.processInfo.systemUptime
                guard now - hapticTime >= 0.12 else { return }
                hapticTime = now
                UIImpactFeedbackGenerator(style: (event["kind"] as? String) == "heavy" ? .heavy : .light).impactOccurred()
            default: break
            }
        }

        private func runCalendar(_ raw: String, app: LocalGenUiApp, requestID: String?) {
            func reply(_ ok: Bool) {
                if let requestID {
                    send(LocalGenUiCalendar.shared.result(app: app, requestId: requestID, succeeded: ok))
                }
            }
            guard let request = LocalGenUiCalendar.shared.read(raw: raw, app: app) else {
                reply(false)
                return
            }
            let receipt = request.receipt.map { app.id + "|" + $0 }
            if let payload = request.receipt, let receipt {
                if app.calendarReceipts.contains(payload) || calendarCompleted.contains(receipt) {
                    reply(true)
                    return
                }
                if calendarPending.contains(receipt) { return }
            }
            let now = ProcessInfo.processInfo.systemUptime
            calendarCalls.removeAll { now - $0 >= 60 }
            guard calendarCalls.count < 30 else {
                reply(false)
                current?.onCalendarResult(request.action, nil)
                return
            }
            calendarCalls.append(now)
            if let receipt { calendarPending.insert(receipt) }
            let dispatch = current?.dispatch
            func isCurrent() -> Bool {
                guard let mounted = current?.app else { return false }
                return mounted.id == app.id && mounted.sourceRevision == app.sourceRevision && !mounted.streaming && !mounted.checking
            }
            Task { @MainActor in
                let result = await calendarWriter.run(request, stillVisible: isCurrent)
                if let receipt, let payload = request.receipt {
                    calendarPending.remove(receipt)
                    if result != nil {
                        calendarCompleted.insert(receipt)
                        dispatch?(LocalGenUiIntentRecordCalendarReceipt(id: app.id, receipt: payload))
                    }
                }
                if isCurrent() {
                    reply(result != nil)
                    current?.onCalendarResult(request.action, result)
                }
            }
        }

        func restoreOrientation() {
            guard orientationRequested else { return }
            orientationRequested = false
            web?.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .allButUpsideDown))
        }

        private func updateCamera(replies: [String] = []) {
            replies.forEach(send)
            current?.camera?.setWanted(gestures.cameraWanted, report: { [weak self] status in
                guard let self else { return }
                gestures.cameraStatus(value: status).forEach(send)
            }, pose: { [weak self] points in
                guard let self else { return }
                gestures.frame(points: points).forEach(send)
            })
        }

        private func handleCollaboration(_ raw: String, _ view: LocalGenUiWebView) {
            let bridge = LocalGenUiCollaboration.shared
            guard let request = bridge.request(raw: raw, app: view.app) else { return }
            if request.kind == nil {
                guard collaboration?.id == request.id else { return }
                collaboration = nil
                view.presentCollaboration?(nil)
                return
            }
            guard let present = view.presentCollaboration else {
                send(bridge.reply(request: request, status: .unavailable, reason: "missingSyscap", asset: ""))
                return
            }
            if let pending = collaboration {
                if pending.id != request.id {
                    send(bridge.reply(request: request, status: .failed, reason: "busy", asset: ""))
                }
                return
            }
            collaboration = request
            send(bridge.reply(request: request, status: .pending, reason: "", asset: ""))
            let media = view.media
            present(LocalGenUiImageRequest(request: request) { [weak self] status, reason, asset in
                guard let self, collaboration === request else {
                    if !asset.isEmpty {
                        Task { try? await bridge.discard(media: media, request: request, asset: asset) }
                    }
                    return
                }
                collaboration = nil
                current?.presentCollaboration?(nil)
                send(bridge.reply(request: request, status: status, reason: reason, asset: asset))
            })
        }

        private func mount() {
            guard let current, let manifest else { return }
            if collaboration != nil {
                collaboration = nil
                Task { @MainActor [weak self] in
                    guard let self, collaboration == nil else { return }
                    self.current?.presentCollaboration?(nil)
                }
            }
            gestures.mount(app: current.camera == nil ? nil : current.app)
            updateCamera()
            send(LocalGenUiDocument.shared.mount(manifestJson: manifest, app: current.app, scheme: current.scheme,
                                                 locale: current.locale, look: current.look, imageSearchAvailable: true))
            if !current.app.streaming && !current.app.checking {
                send(LocalGenUiCalendar.shared.receipts(app: current.app))
                send(LocalGenUiCollaboration.shared.availability(app: current.app, enabled: current.presentCollaboration != nil))
            }
        }

        private func sendJSON(_ value: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
            send(String(decoding: data, as: UTF8.self))
        }

        private func send(_ message: String) {
            guard let literal = try? JSONEncoder().encode(message) else { return }
            web?.evaluateJavaScript("window.__genuiHost?.receive(\(String(decoding: literal, as: UTF8.self)))")
        }
    }
}


@MainActor
private final class LocalGenUiCalendarWriter {
    static let shared = LocalGenUiCalendarWriter()

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard
    private let calendarKey = "openbitfun.local_genui.calendar"
    private let eventsKey = "openbitfun.local_genui.calendar.events"
    private let sequenceKey = "openbitfun.local_genui.calendar.sequence"

    func run(_ request: LocalGenUiCalendarRequest, stillVisible: () -> Bool) async -> Int64? {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) { granted = try await store.requestFullAccessToEvents() }
            else { granted = try await store.requestAccess(to: .event) }
            guard granted, stillVisible(), let calendar = try localCalendar() else { return nil }
            switch request.action {
            case .create:
                guard let details = request.event else { return nil }
                let id = defaults.integer(forKey: sequenceKey) + 1
                defaults.set(id, forKey: sequenceKey)
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.url = marker(for: Int64(id))
                apply(details, to: event)
                try store.save(event, span: .thisEvent)
                guard let identifier = event.eventIdentifier else { return nil }
                saveIdentifier(identifier, for: Int64(id))
                return Int64(id)
            case .update:
                guard let id = request.eventId?.int64Value, let details = request.event,
                      let event = existingEvent(id: id, in: calendar) else { return nil }
                let wasRecurring = event.hasRecurrenceRules
                apply(details, to: event)
                try store.save(event, span: wasRecurring ? .futureEvents : .thisEvent)
                if let identifier = event.eventIdentifier { saveIdentifier(identifier, for: id) }
                return id
            case .delete:
                guard let id = request.eventId?.int64Value,
                      let event = existingEvent(id: id, in: calendar) else { return nil }
                try store.remove(event, span: event.hasRecurrenceRules ? .futureEvents : .thisEvent)
                saveIdentifier(nil, for: id)
                return id
            case .list:
                return count(calendar, from: request.filterStart?.int64Value, to: request.filterEnd?.int64Value)
            default:
                return nil
            }
        } catch { return nil }
    }

    private func apply(_ details: LocalGenUiCalendarEvent, to event: EKEvent) {
        event.title = details.title
        event.startDate = date(details.startMillis)
        event.endDate = date(details.endMillis)
        event.notes = details.eventDescription.isEmpty ? nil : details.eventDescription
        event.location = details.location.isEmpty ? nil : details.location
        event.alarms = details.reminders.map { EKAlarm(relativeOffset: -60 * Double($0.intValue)) }
        let frequencies: [String: EKRecurrenceFrequency] = [
            "daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly
        ]
        guard let frequency = details.repeatFrequency.flatMap({ frequencies[$0] }) else {
            event.recurrenceRules = nil
            return
        }
        let end: EKRecurrenceEnd?
        if let count = details.repeatCount {
            end = EKRecurrenceEnd(occurrenceCount: Int(count.intValue))
        } else if let until = details.repeatUntil {
            end = EKRecurrenceEnd(end: date(until.int64Value))
        } else { end = nil }
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: frequency, interval: Int(details.repeatInterval), end: end)]
    }

    private func count(_ calendar: EKCalendar, from: Int64?, to: Int64?) -> Int64 {
        let owned = eventIdentifiers().keys.compactMap { Int64($0) }.compactMap { existingEvent(id: $0, in: calendar) }
        guard let from, let to else { return Int64(owned.count) }
        guard !owned.isEmpty else { return 0 }
        let first = owned.map(\.startDate).compactMap { $0 }.min() ?? date(from)
        var start = max(date(from), first)
        let end = date(to)
        let urls = Set(owned.compactMap(\.url))
        var matches = Set<URL>()
        while start < end, matches.count < urls.count {
            // EventKit caps a predicate at four years. Deduplicate occurrences
            // across windows so a recurring series counts as one event.
            let next = min(end, start.addingTimeInterval(3 * 365 * 24 * 60 * 60))
            let predicate = store.predicateForEvents(withStart: start, end: next, calendars: [calendar])
            for event in store.events(matching: predicate) {
                if let url = event.url, urls.contains(url), event.startDate < end, event.endDate > date(from) {
                    matches.insert(url)
                }
            }
            start = next
        }
        return Int64(matches.count)
    }

    private func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private func marker(for id: Int64) -> URL? { URL(string: "openbitfun-calendar://event/\(id)") }

    private func eventIdentifiers() -> [String: String] {
        defaults.dictionary(forKey: eventsKey) as? [String: String] ?? [:]
    }

    private func saveIdentifier(_ identifier: String?, for id: Int64) {
        var identifiers = eventIdentifiers()
        identifiers[String(id)] = identifier
        defaults.set(identifiers, forKey: eventsKey)
    }

    private func existingEvent(id: Int64, in calendar: EKCalendar) -> EKEvent? {
        guard let identifier = eventIdentifiers()[String(id)], let event = store.event(withIdentifier: identifier),
              event.calendar.calendarIdentifier == calendar.calendarIdentifier,
              event.url == marker(for: id) else { return nil }
        return event
    }

    private func localCalendar() throws -> EKCalendar? {
        if let id = defaults.string(forKey: calendarKey),
           let calendar = store.calendar(withIdentifier: id),
           calendar.source.sourceType == .local, calendar.allowsContentModifications {
            return calendar
        }
        guard let source = store.sources.first(where: { $0.sourceType == .local }) else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.source = source
        calendar.title = "OpenBitFun"
        try store.saveCalendar(calendar, commit: true)
        defaults.set(calendar.calendarIdentifier, forKey: calendarKey)
        return calendar
    }
}
