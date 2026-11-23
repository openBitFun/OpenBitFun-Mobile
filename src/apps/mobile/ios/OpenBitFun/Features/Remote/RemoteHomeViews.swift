import OpenBitFunMobileCore
import SwiftUI

struct RemoteConnectedHomeView: View {
    @ObservedObject var model: MobileAppModel
    var onBrowse: (() -> Void)?

    private var recent: [ChatSession] {
        let candidates = model.remoteSessions.map {
            RecentSessionUiState(id: $0.id, status: $0.status,
                                 updatedAt: $0.updatedLabel, createdAt: $0.createdAt)
        }
        return RecentSessionsPresentation.shared.sessionIds(sessions: candidates).compactMap { id in
            model.remoteSessions.first { $0.id == id }
        }
    }
    private func context(_ session: ChatSession) -> String {
        session.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? session.workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? model.accountDeviceName
            ?? ""
    }
    private func browse() {
        if let onBrowse { onBrowse() }
        else { model.drawerOpen = true }
    }
    private var presentation: RemoteHomePresentation {
        RemoteHomePresentation.resolve(
            signedIn: model.accountUser != nil,
            hasTarget: model.remoteExpectedDeviceKey != nil,
            connected: model.remoteConnected && model.connectionPhase == .connected,
            reconnecting: model.connectionPhase == .reconnecting,
            sessionsLoaded: model.remoteInitialSessionReady
        )
    }

    @ViewBuilder
    private var homeStatus: some View {
        switch presentation {
        case .chooseDevice:
            Text(model.localized("选择设备和工作区，继续你的对话。"))
                .font(.system(size: 13)).foregroundStyle(OpenBitFunTheme.muted)
            homeButton("查看设备", action: browse)
        case .pairDevice:
            Text(model.localized("连接电脑后，继续你的对话。"))
                .font(.system(size: 13)).foregroundStyle(OpenBitFunTheme.muted)
            homeButton("连接电脑", action: model.connectRemote)
        case .connecting, .loadingSessions:
            homeButton("查看设备", action: browse)
        case .unavailable:
            // The device row exposes connection state and retry without a separate banner.
            homeButton("查看设备", action: browse)
        case .ready:
            EmptyView()
        }
    }

    private func homeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(model.localized(title))
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(OpenBitFunTheme.soft, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).padding(.vertical, 16)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WelcomeBrandFlowView(sweep: true)
                        .frame(width: MobileDesignGeometry.recentHomeMarkSize, height: MobileDesignGeometry.recentHomeMarkSize)
                        .anchorPreference(key: ColdStartHomeMarkPreference.self, value: .bounds) { $0 }
                        .frame(maxWidth: .infinity)
                    WelcomePhraseView(model: model, wordSize: MobileDesignGeometry.recentHomeTitleSize,
                                      longWordSize: MobileDesignGeometry.recentHomeTitleSize,
                                      stageHeight: MobileDesignGeometry.recentHomePhraseStageHeight)
                        .frame(maxWidth: .infinity)
                        .padding(.top, MobileDesignGeometry.recentHomeHeroGap)
                        .padding(.bottom, MobileDesignGeometry.recentHomeHeroBottom)
                    homeStatus
                    if !recent.isEmpty || presentation == .ready {
                        HStack {
                            Text(model.localized("最近会话"))
                            Spacer()
                            Button(model.localized("全部会话"), action: browse)
                                .foregroundStyle(OpenBitFunTheme.ink)
                        }.font(.system(size: 12)).foregroundStyle(OpenBitFunTheme.muted)
                    }
                    ForEach(recent) { session in
                        Button {
                            if session.deviceKey != nil { model.selectDirectorySession(session) }
                            else { model.select(session) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).font(MobileDesignTypography.titleSmall.font.weight(.medium)).lineLimit(2)
                                    Text(context(session)).font(MobileDesignTypography.bodySmall.font)
                                        .foregroundStyle(OpenBitFunTheme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, MobileDesignGeometry.recentHomeRowPadding)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Rectangle().fill(OpenBitFunTheme.line).frame(height: 0.5)
                    }
                    if recent.isEmpty && presentation == .ready {
                        Text(model.localized("还没有可继续的对话"))
                            .font(.system(size: 13)).foregroundStyle(OpenBitFunTheme.muted).padding(.vertical, 18)
                    }

                }
                .padding(.horizontal, MobileDesignGeometry.recentHomeGutter)
                .padding(.top, MobileDesignGeometry.recentHomeTopPadding)
                .padding(.bottom, 28)
                .frame(maxWidth: MobileDesignGeometry.recentHomeMaxWidth)
                .frame(minHeight: proxy.size.height, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .foregroundStyle(OpenBitFunTheme.ink)
        .background(OpenBitFunTheme.page)
        .overlay(alignment: .topLeading) {
            if let onBrowse {
                Button(action: onBrowse) {
                    ReferenceGlyph(assetName: "MenuGlyph", width: 23, height: 18)
                        .frame(width: MobileDesignGeometry.controlTouchSize,
                               height: MobileDesignGeometry.controlTouchSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.localized("打开侧栏"))
                .padding(.leading, 8)
                .padding(.top, 8)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Signed-out home with a fixed contour mark and looping desktop phrases.
struct WelcomeHomeView: View {
    @ObservedObject var model: MobileAppModel
    let openSidebar: () -> Void
    let openMiniApps: () -> Void
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let wide = width >= 600
            let landscape = width >= 840 && width >= geometry.size.height * 1.2
            let height = geometry.size.height - MobileDesignGeometry.welcomeHeaderHeight
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array("OpenBitFun".enumerated()), id: \.offset) { _, letter in
                            welcomeGlyph(letter, size: MobileDesignGeometry.welcomeHeaderWordSize)
                        }
                        Spacer()
                        Button(action: openSidebar) {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 20))
                                .foregroundStyle(OpenBitFunTheme.muted)
                                .frame(width: MobileDesignGeometry.controlTouchSize, height: MobileDesignGeometry.controlTouchSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.localized("展开侧边栏"))
                    }
                    .padding(.leading, wide ? 40 : MobileDesignGeometry.welcomeGutter)
                    .padding(.trailing, MobileDesignGeometry.welcomeGutter)
                    .frame(height: MobileDesignGeometry.welcomeHeaderHeight)
                    if landscape {
                        HStack(spacing: 48) {
                            hero(markSize: MobileDesignGeometry.welcomeLandscapeMarkSize, wide: true)
                            actions(wide: true).frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 48)
                        .frame(maxWidth: MobileDesignGeometry.welcomeLandscapeWidth)
                        .frame(minHeight: max(400, height))
                    } else if wide {
                        VStack(spacing: 0) {
                            hero(markSize: MobileDesignGeometry.welcomeWideMarkSize, wide: true)
                            actions(wide: true)
                        }
                        .padding(.bottom, 64)
                        .frame(minHeight: max(540, height))
                    } else {
                        VStack(spacing: 0) {
                            hero(markSize: MobileDesignGeometry.welcomeMarkSize, wide: false)
                                .frame(maxHeight: .infinity)
                                .padding(.bottom, 24)
                            actions(wide: false, bottomInset: geometry.safeAreaInsets.bottom)
                        }
                        .frame(height: max(430, height))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(OpenBitFunTheme.ink)
        .background(MobileDesignColors.welcomePageBg.ignoresSafeArea())
    }

    private func hero(markSize: CGFloat, wide: Bool) -> some View {
        VStack(spacing: wide ? 16 : 20) {
            WelcomeBrandFlowView(sweep: true)
                .frame(width: markSize, height: markSize)
            WelcomePhraseView(model: model)
        }
        .padding(.bottom, wide ? 32 : 0)
        .frame(maxWidth: .infinity)
    }

    private func actions(wide: Bool, bottomInset: CGFloat = 0) -> some View {
        VStack(spacing: MobileDesignGeometry.welcomeButtonGap) {
            Button(action: model.connectRemote) {
                Text(model.localized(model.accountUser == nil ? "登录账号" : "连接电脑"))
                    .font(MobileDesignTypography.labelMedium.font.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: MobileDesignGeometry.welcomeButtonHeight)
                    .foregroundStyle(wide ? OpenBitFunTheme.page : MobileDesignColors.welcomeButtonLabel)
                    .background(wide ? OpenBitFunTheme.ink : MobileDesignColors.welcomeButton, in: Capsule())
            }
            .buttonStyle(.plain)
            MiniAppsButton(model: model, onOpen: openMiniApps, explore: true)
                .foregroundStyle(wide ? OpenBitFunTheme.muted : MobileDesignColors.welcomeSecondary)
        }
        .padding(.horizontal, MobileDesignGeometry.welcomeGutter)
        .padding(.top, wide ? 0 : MobileDesignGeometry.welcomeGutter)
        .padding(.bottom, wide ? 0 : max(0, MobileDesignGeometry.welcomeDockBottom - bottomInset))
        .frame(maxWidth: wide ? MobileDesignGeometry.welcomeWideActionWidth : MobileDesignGeometry.welcomeMaxWidth)
        .background(alignment: .top) {
            if !wide {
                UnevenRoundedRectangle(
                    topLeadingRadius: MobileDesignGeometry.welcomeDockRadius,
                    topTrailingRadius: MobileDesignGeometry.welcomeDockRadius
                )
                .fill(MobileDesignColors.welcomeDock)
                .padding(.bottom, -bottomInset)
            }
        }
    }

}

private struct WelcomePhraseView: View {
    @ObservedObject var model: MobileAppModel
    var wordSize = MobileDesignGeometry.welcomeWordSize
    var longWordSize = MobileDesignGeometry.welcomeLongWordSize
    var stageHeight = MobileDesignGeometry.welcomeStageHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()
    private var phrases: [String] { ["OpenBitFun", model.localized("干点活儿"), model.localized("玩点花样"), model.localized("随你发挥")] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || scenePhase != .active)) { timeline in
            let pose = phrase(at: timeline.date)
            HStack(spacing: 0) {
                ForEach(Array(pose.word.enumerated()), id: \.offset) { index, letter in
                    let progress = min(1, max(0, (pose.time - 180 - Double(index) * 55) / 800))
                    let ease = 1 - pow(1 - progress, 3)
                    let bump = sin(progress * .pi) * (1 - progress)
                    let exit = min(1, max(0, (pose.time - duration(pose.word) + 650) / 650))
                    welcomeGlyph(letter, size: pose.word.count > 12 ? longWordSize : wordSize)
                        .opacity(min(1, progress * 3) * (1 - exit))
                        .scaleEffect(1 + bump * 0.045)
                        .offset(x: (1 - ease) * 38 - bump * 5 - exit * exit * 30)
                }
            }
            .frame(height: stageHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pose.word)
        }
        .onChange(of: scenePhase) { if $0 == .active { started = Date() } }
    }

    private func duration(_ word: String) -> Double { 250+Double(word.count)*185+(word == "OpenBitFun" ? 600 : 0)+1800+650 }
    private func phrase(at date: Date) -> (word: String,time: Double) {
        if reduceMotion { return ("OpenBitFun",2700) }
        var time = max(0,date.timeIntervalSince(started)*1000).truncatingRemainder(dividingBy: phrases.reduce(0) { $0+duration($1) })
        for word in phrases { if time < duration(word) { return (word,time) };time -= duration(word) }
        return (phrases[0],0)
    }
}

private func welcomeGlyph(_ letter: Character, size: CGFloat) -> some View {
    Text(letter == "i" ? "ı" : String(letter)).font(.system(size: size, weight: .medium))
        .overlay(alignment: .top) {
            if letter == "i" { Circle().fill(MobileDesignColors.brandDot).frame(width: size*0.14, height: size*0.14).offset(y: size*0.25) }
        }
}
