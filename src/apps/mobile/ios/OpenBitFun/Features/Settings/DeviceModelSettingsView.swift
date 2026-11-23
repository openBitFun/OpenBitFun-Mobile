import OpenBitFunMobileCore
import SwiftUI

struct DeviceModelSettingsEntry: View {
    @ObservedObject var model: MobileAppModel
    let onTap: () -> Void

    private var availability: DeviceModelAvailability { model.deviceModelDefaults.availability }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "gearshape").font(.system(size: 16))
                    .foregroundStyle(OpenBitFunTheme.muted)
                Text(model.localized("模型设置"))
                    .font(MobileDesignTypography.bodyMedium.font.weight(.medium))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: MobileDesignGeometry.controlTouchSize)
            .background(OpenBitFunTheme.soft, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.settingsGroupRadius))
            .opacity(availability == .available ? 1 : 0.38)
            .overlay(alignment: .topTrailing) {
                if availability == .unsupported {
                    Text(model.localized("升级"))
                        .font(MobileDesignTypography.labelSmall.font.weight(.bold))
                        .foregroundStyle(OpenBitFunTheme.contentOnAction)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 15)
                        .background(MobileDesignColors.primaryAction, in: RoundedRectangle(cornerRadius: 4))
                        .offset(y: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(availability != .available && availability != .unsupported)
        .accessibilityIdentifier("device-model-settings")
    }
}

struct DeviceModelSettingsView: View {
    @ObservedObject var model: MobileAppModel
    let deviceName: String
    @Binding var role: DeviceModelRole?
    let dispatch: (RemoteSessionIntent) -> Void
    let onBack: () -> Void
    let onClose: () -> Void

    private var state: DeviceModelDefaultsUiState { model.deviceModelDefaults }
    private var selectedRole: DeviceModelRoleUi? { state.roles.first { $0.role == role } }
    private var saving: Bool { state.operation == .saving }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MobileDesignGeometry.settingsSectionGap) {
                    if role == nil {
                        desktopCard
                        if !state.roles.isEmpty { roleCard }
                    }
                    if let status = statusTitle { statusCard(status) }
                    if let role {
                        if let selectedRole { picker(role, selectedRole) }
                    } else {
                        if !state.roles.isEmpty && !state.hasModels { emptyCatalogCard }
                        scopeCard
                    }
                }
                .padding(.horizontal, MobileDesignGeometry.sheetHorizontalPadding)
                .padding(.top, role == nil ? 16 : 12)
                .padding(.bottom, 34)
                .frame(maxWidth: MobileDesignGeometry.settingsContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .id(role?.name)
        }
        .background(OpenBitFunTheme.page)
        .foregroundStyle(OpenBitFunTheme.ink)
        .accessibilityAction(.escape) { if !saving { back() } }
        .interactiveDismissDisabled(saving)
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerButton("chevron.left", label: "返回", action: back)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.localized("模型设置"))
                    .font(MobileDesignTypography.bodySmall.font.weight(.medium))
                    .foregroundStyle(OpenBitFunTheme.muted)
                Text(role.map { model.localized($0.labelKey) } ?? deviceName)
                    .font(MobileDesignTypography.conversationHeaderTitle.font.weight(.medium))
                    .lineLimit(1)
                    .accessibilityIdentifier("device-model-page")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            headerButton("xmark", label: "关闭", action: onClose)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: MobileDesignGeometry.sheetHeaderHeight)
        .overlay(alignment: .bottom) { OpenBitFunTheme.line.frame(height: 0.5) }
    }

    private func headerButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 18, weight: .medium))
                .frame(width: MobileDesignGeometry.controlTouchSize, height: MobileDesignGeometry.controlTouchSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityLabel(model.localized(label))
    }

    private var desktopCard: some View {
        card {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: MobileDesignGeometry.settingsIconSize))
                    .foregroundStyle(OpenBitFunTheme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName).font(MobileDesignTypography.bodyMedium.font.weight(.medium))
                    let connected = state.availability != .disconnected
                    let link = model.localized(connected ? "已连接" : "未连接")
                    Text("\(link) · \(model.localized("云端账号"))")
                        .font(MobileDesignTypography.bodySmall.font)
                        .foregroundStyle(connected ? OpenBitFunTheme.statusSuccess : OpenBitFunTheme.muted)
                }
            }
            .padding(.horizontal, MobileDesignGeometry.settingsRowPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: MobileDesignGeometry.modelSourceRowHeight, alignment: .leading)
        }
    }

    private var roleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.localized("模型")).font(MobileDesignTypography.bodySmall.font)
                .foregroundStyle(OpenBitFunTheme.muted).padding(.leading, 8)
            card {
                VStack(spacing: 0) {
                    ForEach(state.roles, id: \.role) { row in
                        modelRow(model.localized(row.role.labelKey), detail: valueText(row), marked: row.resolved, navigation: true,
                                 saving: saving && state.activeRole == row.role,
                                 updated: state.operation == .saved && state.activeRole == row.role) { role = row.role }
                            .accessibilityIdentifier("device-model-role-\(row.role.name.lowercased())")
                    }
                }
            }
        }
    }

    private func picker(_ role: DeviceModelRole, _ row: DeviceModelRoleUi) -> some View {
        let filter = role == .imageUnderstanding
            ? "仅显示支持图片理解（image_understanding）的模型 · 作用于 %@ 上的新会话"
            : "仅显示已启用且支持文本对话（text_chat）的模型 · 作用于 %@ 上的新会话"
        return VStack(alignment: .leading, spacing: 0) {
            Text(String(format: model.localized(filter), deviceName))
                .font(MobileDesignTypography.labelSmall.font).foregroundStyle(OpenBitFunTheme.muted)
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
            if role.allowsUnset {
                modelRow(model.localized(role.unsetKey), detail: model.localized(role.hintKey), marked: row.selected == nil) { select(role, nil) }
                    .accessibilityIdentifier("device-model-option-unset")
                if !row.choices.isEmpty { OpenBitFunTheme.line.frame(height: 0.5).padding(.vertical, 6) }
            }
            if row.choices.isEmpty {
                Text(model.localized("该设备暂无可用于该角色的模型"))
                    .font(MobileDesignTypography.labelSmall.font).foregroundStyle(OpenBitFunTheme.muted).padding(10)
            }
            ForEach(row.choices, id: \.id) { choice in
                modelRow(choice.title, detail: choice.subtitle, marked: row.selected?.id == choice.id,
                         imageBadge: role == .imageUnderstanding) { select(role, choice.id) }
                    .accessibilityIdentifier("device-model-option-\(choice.id)")
            }
        }
    }

    private func modelRow(_ title: String, detail: String, marked: Bool, navigation: Bool = false,
                          saving: Bool = false, updated: Bool = false, imageBadge: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if saving { ProgressView().controlSize(.small) }
                    else if marked {
                        Image(systemName: navigation ? "checkmark" : "checkmark.circle")
                            .font(.system(size: navigation ? 18 : 16))
                    }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font((navigation ? MobileDesignTypography.bodyMedium.font : MobileDesignTypography.titleSmall.font).weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if imageBadge {
                            Text(model.localized("图片理解"))
                                .font(MobileDesignTypography.labelSmall.font).foregroundStyle(OpenBitFunTheme.muted)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(OpenBitFunTheme.soft, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if !detail.isEmpty {
                        Text(detail).font(MobileDesignTypography.labelSmall.font).foregroundStyle(OpenBitFunTheme.muted).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if updated {
                    Text(model.localized("已更新")).font(MobileDesignTypography.bodyMedium.font).foregroundStyle(OpenBitFunTheme.statusSuccess)
                }
                if navigation { Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(OpenBitFunTheme.muted) }
            }
            .padding(.horizontal, navigation ? MobileDesignGeometry.settingsRowPadding : 10)
            .padding(.vertical, 8)
            .frame(minHeight: navigation ? MobileDesignGeometry.settingsDetailRowHeight : MobileDesignGeometry.modelAccountRowHeight)
            .background(saving || !navigation && marked ? OpenBitFunTheme.soft : Color.clear,
                        in: RoundedRectangle(cornerRadius: MobileDesignGeometry.composerModelSelectorRowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.canEdit)
        .accessibilityAddTraits(!navigation && marked ? .isSelected : [])
    }

    private var scopeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 4) {
                ForEach([
                    "这些默认值作用于该设备上的新会话，进行中的会话不受影响。",
                    "快速模型未配置时，跟随主力模型。",
                    "多模态模型只用于图片理解，不替换主力模型。",
                ], id: \.self) { Text(model.localized($0)) }
            }
            .font(MobileDesignTypography.bodySmall.font)
            .foregroundStyle(OpenBitFunTheme.muted)
            .padding(.horizontal, MobileDesignGeometry.settingsRowPadding)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyCatalogCard: some View {
        card {
            VStack(spacing: 6) {
                Image(systemName: "desktopcomputer").font(.system(size: 26)).foregroundStyle(OpenBitFunTheme.muted)
                Text(model.localized("该设备尚未配置任何模型")).font(MobileDesignTypography.bodyMedium.font)
                Text(model.localized("请先在该设备的 OpenBitFun 里添加模型，再回到这里设置角色默认值。"))
                    .font(MobileDesignTypography.bodySmall.font).foregroundStyle(OpenBitFunTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, MobileDesignGeometry.settingsRowPadding)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func statusCard(_ title: String) -> some View {
        card {
            HStack(spacing: 10) {
                if state.busy { ProgressView().controlSize(.small) }
                let value = state.roles.first { $0.role == state.activeRole }
                let message = state.operation == .saved && value != nil
                    ? String(format: model.localized("已更新为 %@ · 已重新读取该设备上的当前值"), value.map(valueText) ?? "")
                    : model.localized(title)
                Text(message).font(MobileDesignTypography.bodySmall.font)
                    .foregroundStyle(state.operation == .saved ? OpenBitFunTheme.statusSuccess : OpenBitFunTheme.ink)
                Spacer(minLength: 0)
                if state.operation == .loadFailed || state.operation == .writeFailed {
                    Button(model.localized("重试")) { dispatch(RemoteSessionIntentRefreshDeviceModelDefaults.shared) }
                        .buttonStyle(.plain)
                }
            }
            .padding(MobileDesignGeometry.settingsRowPadding)
        }
    }

    private var statusTitle: String? {
        switch state.availability {
        case .disconnected: return "未连接"
        case .unsupported: return "该设备上的 OpenBitFun 版本过旧，不支持配置模型默认值。请升级该设备上的 OpenBitFun 后继续。"
        case .checking: return "正在读取模型默认值"
        default: break
        }
        switch state.operation {
        case .idle, .loading: return "正在读取模型默认值"
        case .saving: return "正在保存模型默认值"
        case .saved: return "已更新"
        case .loadFailed: return "读取模型默认值失败，请重试。"
        case .writeFailed: return "保存模型默认值失败，请重试。"
        default: return nil
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(OpenBitFunTheme.card, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.settingsGroupRadius))
            .overlay(RoundedRectangle(cornerRadius: MobileDesignGeometry.settingsGroupRadius).strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
    }

    private func back() {
        if role != nil { role = nil } else { onBack() }
    }

    private func select(_ selectedRole: DeviceModelRole, _ id: String?) {
        role = nil
        dispatch(RemoteSessionIntentSelectDeviceModelDefault(role: selectedRole, modelId: id))
    }

    private func valueText(_ row: DeviceModelRoleUi) -> String {
        if let choice = row.selected {
            return [choice.title, choice.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let unset = model.localized(row.role.unsetKey)
        return row.role.allowsUnset ? "\(unset) · \(model.localized(row.role.hintKey))" : unset
    }
}

private extension DeviceModelRole {
    var labelKey: String {
        if self == .primary { return "主力模型" }
        if self == .fast { return "快速模型" }
        return "多模态模型"
    }

    var unsetKey: String { self == .fast ? "跟随主力" : "未配置" }

    var hintKey: String {
        self == .fast ? "未配置时使用主力模型" : "未指定多模态模型时，图片理解相关能力不可用"
    }
}
