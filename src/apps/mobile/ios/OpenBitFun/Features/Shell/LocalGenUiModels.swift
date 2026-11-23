import OpenBitFunMobileCore
import SwiftUI

final class GenUiModelPanel: ObservableObject, Identifiable {
    let setup: Bool
    @Published var editor: GenUiModelDraft?
    @Published var confirmDelete = false
    var awaitingSerial: Int32?

    init(setup: Bool, hasModels: Bool) {
        self.setup = setup
        editor = setup && !hasModels ? GenUiModelDraft(profile: nil) : nil
    }

    func showEditor(_ draft: GenUiModelDraft?, dispatch: (LocalGenUiIntent) -> Void) {
        dispatch(LocalGenUiIntentResetModelEditor.shared)
        editor = draft
    }
}

// The open panel holds the draft in memory while its native presentation changes.
final class GenUiModelDraft: ObservableObject {
    let modelID: String?
    @Published var name: String
    @Published var endpoint: String
    @Published var modelName: String
    @Published var secret = ""
    @Published var showTypedKey = false
    @Published var requested = false

    init(profile: LocalGenUiModelUi?) {
        modelID = profile?.id
        name = profile?.name ?? ""
        endpoint = profile?.endpoint ?? ""
        modelName = profile?.model ?? ""
    }
}

struct LocalGenUiModelSheet: View {
    @ObservedObject var model: MobileAppModel
    @ObservedObject var local: LocalGenUiModel
    @ObservedObject var panel: GenUiModelPanel
    let centered: Bool
    let onClose: () -> Void

    var body: some View {
        if let state = local.state {
            let profile = state.models.first { $0.id == panel.editor?.modelID }
            let surface = VStack(spacing: 0) {
                header(state)
                ScrollView {
                    if let editor = panel.editor {
                        LocalGenUiModelFields(model: model, local: local, draft: editor, state: state, profile: profile,
                                              setup: panel.setup, write: { begin($0, state) }, delete: { panel.confirmDelete = true })
                            .id(ObjectIdentifier(editor))
                    } else {
                        profiles(state)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: MobileDesignGeometry.sheetContentMaxWidth)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("local-genui-model-scroll")
                .id(panel.editor.map(ObjectIdentifier.init))
            }
            .background(OpenBitFunTheme.page)
            .foregroundStyle(OpenBitFunTheme.ink)
            .interactiveDismissDisabled(state.writingModel)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .alert(model.localized("删除模型"), isPresented: $panel.confirmDelete) {
                Button(model.localized("删除"), role: .destructive) {
                    if let profile { begin(LocalGenUiIntentDeleteModel(id: profile.id), state) }
                }
                Button(model.localized("取消"), role: .cancel) {}
            }
            if #available(iOS 16.4, *) {
                surface.presentationCornerRadius(MobileDesignGeometry.sheetTopRadius)
                    .presentationBackground(OpenBitFunTheme.page)
            } else {
                surface
            }
        }
    }

    private func begin(_ intent: LocalGenUiIntent, _ state: LocalGenUiState) {
        guard panel.awaitingSerial == nil else { return }
        panel.awaitingSerial = state.modelWriteSerial
        local.dispatch(intent)
    }

    private func header(_ state: LocalGenUiState) -> some View {
        let title = panel.setup ? "配置模型" : panel.editor == nil ? "管理模型" : panel.editor?.modelID == nil ? "添加模型" : "编辑模型"
        return HStack {
            Text(model.localized(title))
                .font(MobileDesignTypography.conversationHeaderTitle.font)
                .lineLimit(1)
                .accessibilityIdentifier(centered ? "local-genui-model-centered" : "local-genui-model-bottom-sheet")
            Spacer()
            Button {
                if panel.editor == nil || (panel.setup && state.models.isEmpty) { onClose() }
                else { panel.showEditor(nil, dispatch: local.dispatch) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .medium))
                    .frame(width: MobileDesignGeometry.controlTouchSize, height: MobileDesignGeometry.controlTouchSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.localized("关闭"))
            .disabled(state.writingModel)
        }
        .padding(.leading, 16).padding(.trailing, 8)
        .frame(height: MobileDesignGeometry.sheetHeaderHeight)
        .overlay(alignment: .bottom) { OpenBitFunTheme.line.frame(height: 0.5) }
    }

    private func profiles(_ state: LocalGenUiState) -> some View {
        VStack(alignment: .leading, spacing: MobileDesignGeometry.genuiModelListSpacing) {
            if state.models.isEmpty {
                Text(model.localized("还没有模型，先添加一个。"))
                    .font(MobileDesignTypography.bodyMedium.font).foregroundStyle(OpenBitFunTheme.muted)
                    .padding(.vertical, 8)
            }
            ForEach(state.models, id: \.id) { item in
                Button {
                    if panel.setup && item.hasStoredKey { begin(LocalGenUiIntentUseModelForSetup(id: item.id), state) }
                    else { panel.showEditor(GenUiModelDraft(profile: item), dispatch: local.dispatch) }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(MobileDesignTypography.bodyMedium.font.weight(.medium)).lineLimit(1)
                            Text("\(item.model) · \(genUiModelHost(item.endpoint))")
                                .font(MobileDesignTypography.labelSmall.font)
                                .foregroundStyle(OpenBitFunTheme.muted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if item.id == state.selectedModelId {
                            Text(model.localized("当前使用")).font(MobileDesignTypography.labelSmall.font)
                                .foregroundStyle(OpenBitFunTheme.muted)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(OpenBitFunTheme.muted)
                    }
                    .padding(MobileDesignGeometry.genuiModelFieldPadding)
                    .background(OpenBitFunTheme.card, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.settingsCardRadius))
                    .overlay(RoundedRectangle(cornerRadius: MobileDesignGeometry.settingsCardRadius)
                        .strokeBorder(OpenBitFunTheme.line))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.id == state.selectedModelId ? "local-genui-active-profile" : "local-genui-profile")
                .disabled(state.writingModel)
            }
            GenUiModelAction(label: model.localized("添加模型"), enabled: !state.writingModel) {
                panel.showEditor(GenUiModelDraft(profile: nil), dispatch: local.dispatch)
            }
            .accessibilityIdentifier("local-genui-model-add")
            if let failure = state.modelWriteFailure { GenUiErrorText(model: model, failureCode: failure.name) }
        }
        .padding(.horizontal, MobileDesignGeometry.contentGutter).padding(.bottom, 24)
    }
}

private struct LocalGenUiModelFields: View {
    let model: MobileAppModel
    let local: LocalGenUiModel
    @ObservedObject var draft: GenUiModelDraft
    let state: LocalGenUiState
    let profile: LocalGenUiModelUi?
    let setup: Bool
    let write: (LocalGenUiIntent) -> Void
    let delete: () -> Void
    @FocusState private var keyFocused: Bool

    private var retainedKey: Bool {
        guard let profile, profile.hasStoredKey else { return false }
        let trimmed = draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == profile.endpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MobileDesignGeometry.genuiModelEditorSpacing) {
            let display = model.localized("显示名称")
            fieldLabel(display)
            field(name: display, placeholder: model.localized("可选，默认使用模型名称"), value: $draft.name, id: "genui-model-display")

            fieldLabel("API URL")
            field(name: "API URL", placeholder: "https://api.example.com/v1", value: $draft.endpoint, id: "genui-model-url")
                .keyboardType(.URL)

            let keyLabel = model.localized("API 密钥")
            fieldLabel(keyLabel)
            let prompt = Text(retainedKey ? model.localized("留空则保留已保存的密钥") : keyLabel)
                .foregroundColor(MobileDesignColors.subtle)
            HStack {
                Group {
                    if draft.showTypedKey {
                        TextField("", text: $draft.secret, prompt: prompt)
                    } else {
                        SecureField("", text: $draft.secret, prompt: prompt)
                    }
                }
                .focused($keyFocused)
                .accessibilityLabel(keyLabel)
                .accessibilityIdentifier("genui-model-key")
                Button {
                    let wasFocused = keyFocused
                    draft.showTypedKey.toggle()
                    if wasFocused { Task { @MainActor in keyFocused = true } }
                } label: {
                    Image(systemName: draft.showTypedKey ? "eye" : "eye.slash")
                        .font(.system(size: 18)).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.localized(draft.showTypedKey ? "隐藏密钥" : "显示密钥"))
            }
            .modifier(GenUiModelFieldStyle())

            let modelLabel = model.localized("模型名称")
            HStack {
                fieldLabel(modelLabel)
                Spacer()
                if state.discoveringModels { ProgressView().controlSize(.small) }
                chip(model.localized("获取模型列表"), selected: false) {
                    draft.requested = true
                    local.dispatch(LocalGenUiIntentDiscoverModels(id: profile?.id, endpoint: draft.endpoint, apiKey: draft.secret))
                }
                .disabled(draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.discoveringModels)
                .opacity(draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.discoveringModels ? 0.45 : 1)
            }
            field(name: modelLabel, placeholder: modelLabel, value: $draft.modelName, id: "genui-model-name")
            if !state.discoveredModels.isEmpty {
                ModelOptionFlow {
                    ForEach(state.discoveredModels, id: \.self) { id in
                        chip(id, selected: id == draft.modelName) { draft.modelName = id }
                    }
                }
            } else if draft.requested && !state.discoveringModels && state.modelDiscoveryFailure == nil {
                Text(model.localized("服务未返回可选模型，可手动填写。"))
                    .font(MobileDesignTypography.bodySmall.font).foregroundStyle(OpenBitFunTheme.muted)
            }
            if let failure = state.modelDiscoveryFailure ?? state.modelWriteFailure {
                GenUiErrorText(model: model, failureCode: failure.name)
            }
            GenUiModelAction(label: model.localized(setup ? "保存并使用" : "保存"), enabled: !state.writingModel) {
                write(LocalGenUiIntentSaveModel(id: profile?.id, name: draft.name, endpoint: draft.endpoint,
                                               model: draft.modelName, apiKey: draft.secret, useForSession: setup))
            }
            if !setup && profile != nil {
                GenUiModelAction(label: model.localized("删除模型"), enabled: !state.writingModel, destructive: true, action: delete)
            }
        }
        .padding(.horizontal, MobileDesignGeometry.contentGutter).padding(.bottom, 24)
        .disabled(state.writingModel)
        .onChange(of: draft.endpoint) { _ in clearDiscovery() }
        .onChange(of: draft.secret) { _ in clearDiscovery() }
    }

    private func clearDiscovery() {
        if draft.requested {
            draft.requested = false
            local.dispatch(LocalGenUiIntentCancelModelDiscovery.shared)
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label).font(MobileDesignTypography.bodyMedium.font.weight(.medium))
    }

    private func field(name: String, placeholder: String, value: Binding<String>, id: String) -> some View {
        TextField("", text: value, prompt: Text(placeholder).foregroundColor(MobileDesignColors.subtle))
            .accessibilityLabel(name)
            .accessibilityIdentifier(id)
            .modifier(GenUiModelFieldStyle())
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(MobileDesignTypography.labelSmall.font)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(selected ? OpenBitFunTheme.contentOnAction : OpenBitFunTheme.ink)
                .background(selected ? MobileDesignColors.primaryAction : OpenBitFunTheme.soft,
                    in: RoundedRectangle(cornerRadius: MobileDesignGeometry.genuiModelChipRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct GenUiModelFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: MobileDesignGeometry.settingsCompactCardRadius)
        content
            .font(MobileDesignTypography.titleSmall.font)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, MobileDesignGeometry.genuiModelFieldPadding)
            .frame(minHeight: MobileDesignGeometry.genuiModelFieldHeight)
            .background(OpenBitFunTheme.card, in: shape)
            .overlay(shape.strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
            .shadow(color: MobileDesignColors.shadowFaint, radius: 12, y: 4)
    }
}

private struct GenUiModelAction: View {
    let label: String
    let enabled: Bool
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(MobileDesignTypography.labelLarge.font.weight(.medium))
                .foregroundStyle(OpenBitFunTheme.contentOnAction)
                .frame(maxWidth: .infinity, minHeight: MobileDesignGeometry.genuiModelActionHeight)
                .background(destructive ? OpenBitFunTheme.statusDanger : MobileDesignColors.primaryAction, in: Capsule())
                .contentShape(Capsule())
                .shadow(color: MobileDesignColors.shadowSubtle, radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.32)
    }
}

private struct ModelOptionFlow: Layout {
    private let gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + gap }
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        return subviews.map { subview in
            let natural = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(natural.width, width), height: natural.height)
            if x > 0 && x + size.width > width {
                y += rowHeight + gap
                x = 0
                rowHeight = 0
            }
            let rect = CGRect(origin: CGPoint(x: x, y: y), size: size)
            x += size.width + gap
            rowHeight = max(rowHeight, size.height)
            return rect
        }
    }
}

func genUiModelHost(_ endpoint: String) -> String {
    let rest = endpoint.range(of: "://").map { endpoint[$0.upperBound...] } ?? endpoint[...]
    return String(rest.prefix(while: { $0 != "/" }))
}
