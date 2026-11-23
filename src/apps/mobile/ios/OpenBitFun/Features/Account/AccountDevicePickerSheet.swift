import OpenBitFunMobileCore
import SwiftUI

/// Account device picker. Native apps connect a desktop only through the
/// signed-in account's device list; the desktop QR code opens mobile web.
struct AccountDevicePickerSheet: View {
    @ObservedObject var model: MobileAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        accountDevicePage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OpenBitFunTheme.page)
            .onChange(of: model.accountUser) { user in
                if user == nil { dismiss() }
            }

    }

    private var accountDevicePage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image("AccountDeviceBack")
                        .resizable()
                        .foregroundStyle(OpenBitFunTheme.ink)
                        .frame(width: MobileDesignGeometry.navigationBackIconSize * 15 / 23,
                               height: MobileDesignGeometry.navigationBackIconSize)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.localized("返回"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.localized("选择桌面设备"))
                        .font(MobileDesignTypography.conversationHeaderTitle.font)
                        .foregroundStyle(OpenBitFunTheme.ink)
                        .accessibilityIdentifier("connect-account-device-title")
                    Text(model.localized("远程"))
                        .font(MobileDesignTypography.bodySmall.font)
                        .foregroundStyle(OpenBitFunTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 72)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.localized("选择一台在线桌面继续工作。"))
                        .font(MobileDesignTypography.bodyMedium.font)
                        .foregroundStyle(OpenBitFunTheme.muted)
                        .lineSpacing(MobileDesignTypography.bodyMedium.lineSpacing)

                    accountDeviceList
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: MobileDesignGeometry.sheetContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .background(OpenBitFunTheme.page)
    }

    private var accountDeviceList: some View {
        let hasError = model.accountDirectoryError != nil || model.devicePickerConnectionFailed
        return VStack(spacing: 4) {
            HStack {
                Text(model.localized("账号设备"))
                    .font(MobileDesignTypography.bodyMedium.font.weight(.medium))
                    .foregroundStyle(OpenBitFunTheme.ink)
                Spacer(minLength: 0)
                Button {
                    model.devicePickerConnectionFailed = false
                    model.refreshRemoteDevices()
                } label: {
                    Text(model.localized(model.accountRefreshing ? "加载中..." : hasError ? "重试" : "刷新"))
                        .font(MobileDesignTypography.bodyMedium.font)
                        .foregroundStyle(model.accountRefreshing ? OpenBitFunTheme.muted : hasError ? OpenBitFunTheme.statusDanger : OpenBitFunTheme.accent)
                        .padding(.horizontal, 8)
                        .frame(height: MobileDesignGeometry.controlTouchSize)
                }
                .buttonStyle(.plain)
                .disabled(model.accountRefreshing)
                .accessibilityIdentifier("connect-account-device-refresh")
            }
            .frame(height: MobileDesignGeometry.sheetRowHeight)

            if model.accountRefreshing && accountDesktopDevices.isEmpty {
                VStack(spacing: 0) {
                    accountDeviceSkeleton
                    accountDeviceSkeleton
                }
            } else if accountDesktopDevices.isEmpty {
                Text(model.accountDirectoryError ?? model.localized("账号下还没有其他已注册设备。"))
                    .font(MobileDesignTypography.bodyMedium.font)
                    .foregroundStyle(OpenBitFunTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(accountDesktopDevices) { device in
                        accountDeviceRow(device)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OpenBitFunTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: MobileDesignGeometry.sheetGroupRadius))
        .overlay(RoundedRectangle(cornerRadius: MobileDesignGeometry.sheetGroupRadius)
            .strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
    }

    private var accountDesktopDevices: [MobileAccountDevice] {
        model.accountDevices.filter { model.localDeviceID.isEmpty || $0.id != model.localDeviceID }
    }

    private var accountDeviceSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5).fill(OpenBitFunTheme.soft).frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4).fill(OpenBitFunTheme.soft).frame(width: 142, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(OpenBitFunTheme.soft).frame(width: 52, height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 60)
    }

    private func accountDeviceRow(_ device: MobileAccountDevice) -> some View {
        let enabled = device.online && device.controllable && model.devicePickerSwitchingID == nil
        let controlling = device.controllable && device.id == model.accountSelectedDeviceID && model.connectionPhase == .connected
        return Button { model.connectPickerDevice(device) } label: {
            HStack(spacing: 12) {
                Image("AccountDeviceDesktop")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(OpenBitFunTheme.muted)
                    .frame(width: MobileDesignGeometry.sheetIconSize, height: MobileDesignGeometry.sheetIconSize)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name.isEmpty ? device.id : device.name)
                        .font(MobileDesignTypography.bodyMedium.font.weight(.medium))
                        .foregroundStyle(OpenBitFunTheme.ink)
                        .lineLimit(1)
                    Text(accountDeviceStatus(device))
                        .font(MobileDesignTypography.bodySmall.font)
                        .foregroundStyle(device.online && device.controllable ? OpenBitFunTheme.statusSuccess : OpenBitFunTheme.muted)
                }
                Spacer(minLength: 0)
                if enabled && !controlling {
                    Text(model.localized("连接"))
                        .font(MobileDesignTypography.bodyMedium.font)
                        .foregroundStyle(OpenBitFunTheme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(OpenBitFunTheme.soft)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if device.online && device.controllable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OpenBitFunTheme.muted.opacity(0.44))
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 60)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.64)
        }
        .buttonStyle(AccountDeviceRowStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("connect-account-device-row-\(device.id)")
    }

    private func accountDeviceStatus(_ device: MobileAccountDevice) -> String {
        if !device.controllable { return model.localized(device.presenceKey) }
        if model.devicePickerSwitchingID == device.id { return model.localized("正在连接") }
        let presence = model.localized(device.presenceKey)
        if device.id == model.accountSelectedDeviceID && model.connectionPhase == .connected {
            return "\(model.localized("当前控制")) · \(presence)"
        }
        if device.id == model.accountSelectedDeviceID { return "\(model.localized("上次连接")) · \(presence)" }
        return presence
    }
}

private struct AccountDeviceRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}
