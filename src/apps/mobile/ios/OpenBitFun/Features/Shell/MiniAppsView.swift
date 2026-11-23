import OpenBitFunMobileCore
import SwiftUI
import WebKit

struct MiniAppsButton: View {
    @ObservedObject var model: MobileAppModel
    let onOpen: () -> Void
    var sidebar = false
    var explore = false
    var body: some View {
        Group {
            if sidebar {
                Button(action: onOpen) {
                    HStack(spacing: 14) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 24))
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        Text(model.localized("小应用"))
                            .font(MobileDesignTypography.bodyLarge.font.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4).padding(.trailing, 8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenBitFunTheme.ink)
                .accessibilityLabel(model.localized("小应用"))
                .padding(.top, 4)
                .padding(.bottom, 8)
            } else {
                Button(action: onOpen) {
                    HStack(spacing: 5) {
                        Text(model.localized(explore ? "探索小应用" : "小应用"))
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .font(MobileDesignTypography.labelSmall.font)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct BuiltinMiniApp: Identifiable, Decodable {
    struct Copy: Decodable { let name: String; let description: String }
    let id: String
    let locales: [String: Copy]
}

struct MiniAppLaunch: Identifiable {
    let id: String
    var isGenerated: Bool { id.hasPrefix("local-genui:") }

    init?(url: URL) {
        guard url.scheme == "openbitfun", url.host == "miniapp",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        let id = url.lastPathComponent
        let builtin = ["builtin-gomoku", "builtin-regex-playground", "builtin-daily-divination"].contains(id)
        let generated = id.hasPrefix("local-genui:") && UUID(uuidString: String(id.dropFirst("local-genui:".count))) != nil
        guard builtin || generated else { return nil }
        self.id = id
    }

    static func link(_ id: String) -> URL {
        var components = URLComponents()
        components.scheme = "openbitfun"
        components.host = "miniapp"
        components.path = "/" + id
        return components.url!
    }
}

private struct MiniAppGalleryEntry: Identifiable {
    let id: String
    let name: String
    let description: String
    let generated: Bool
}

struct MiniAppsView: View {
    @ObservedObject var model: MobileAppModel
    @ObservedObject var local: LocalGenUiModel
    var initialAppID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var builtins: [BuiltinMiniApp] = []
    @State private var generated: MiniAppGalleryEntry?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: MiniAppGalleryEntry?
    @State private var failure: String?
    @State private var desktopApp: MiniAppGalleryEntry?
    @State private var shortcutsUnavailable = false
    private var locale: String { model.appLanguage == .english ? "en-US" : "zh-CN" }
    private var showList: Bool { model.miniAppsShowList }

    private var apps: [MiniAppGalleryEntry] {
        builtins.compactMap { app in
            guard let copy = app.locales[locale] ?? app.locales["en-US"] else { return nil }
            return MiniAppGalleryEntry(id: app.id, name: copy.name, description: copy.description, generated: false)
        } + (local.state?.galleryApps.map { app in
            MiniAppGalleryEntry(id: app.id, name: app.title, description: model.localized("AI 生成的小应用"), generated: true)
        } ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if initialAppID != nil || selected == nil { dismiss() }
                    else { selected = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 23, weight: .regular))
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.localized("返回"))
                Text(selected?.name ?? model.localized("小应用"))
                    .font(MobileDesignTypography.bodyLarge.font.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                if selected == nil {
                    Button {
                        model.miniAppsShowList.toggle()
                    } label: {
                        Image(showList ? "MiniAppView-cards" : "MiniAppView-list")
                            .renderingMode(.template)
                            .resizable().scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(OpenBitFunTheme.muted)
                            .frame(width: MobileDesignGeometry.miniappViewToggleSurfaceSize, height: MobileDesignGeometry.miniappViewToggleSurfaceSize)
                            .background(OpenBitFunTheme.soft, in: RoundedRectangle(cornerRadius: 10))
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.localized(showList ? "切换为卡片" : "切换为列表"))
                    .accessibilityIdentifier("miniapp-view-toggle")
                } else {
                    Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            if let selected {
                MiniAppWebView(appID: selected.id, locale: locale)
                    .id("\(selected.id)|\(locale)")
            } else if let failure {
                Text(failure)
                    .font(MobileDesignTypography.bodyMedium.font)
                    .foregroundStyle(OpenBitFunTheme.muted)
                    .padding(.vertical, 16)
                Button(model.localized("重试")) { Task { await loadApps() } }
                Spacer()
            } else {
                GeometryReader { geometry in
                    let width = min(geometry.size.width, 1000)
                    Group {
                        if showList { appList(width: width) }
                        else { appDeck(width: width) }
                    }
                    .frame(width: width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(OpenBitFunTheme.ink)
        .background(OpenBitFunTheme.page.ignoresSafeArea())
        .task {
            local.start()
            await loadApps()
        }
        .accessibilityHidden(generated != nil)
        .fullScreenCover(item: $generated) { app in
            LocalGenUiView(model: model, local: local, initialAppId: app.id)
        }
        .confirmationDialog(model.localized("添加桌面图标"), isPresented: desktopSetupPresented,
                            titleVisibility: .visible, presenting: desktopApp) { app in
            Button(model.localized("拷贝链接并打开快捷指令")) { openShortcutEditor(for: app) }
        } message: { _ in
            Text(model.localized("在快捷指令中添加「打开 URL」操作，粘贴启动链接，再选择「添加到主屏幕」。"))
        }
        .alert(model.localized("无法打开快捷指令"), isPresented: $shortcutsUnavailable) {
            Button(model.localized("关闭"), role: .cancel) {}
        } message: {
            Text(model.localized("启动链接已拷贝。可以在安装快捷指令后继续添加。"))
        }
    }

    private var desktopSetupPresented: Binding<Bool> {
        Binding(get: { desktopApp != nil }, set: { if !$0 { desktopApp = nil } })
    }

    private func openShortcutEditor(for app: MiniAppGalleryEntry) {
        UIPasteboard.general.url = MiniAppLaunch.link(app.id)
        // Use UIKit for a consistent foreground handoff to the system editor.
        UIApplication.shared.open(URL(string: "shortcuts://create-shortcut")!, options: [:]) { accepted in
            if !accepted { shortcutsUnavailable = true }
        }
    }

    private func openInitialApp() {
        guard let id = initialAppID, selected == nil, generated == nil else { return }
        if let entry = apps.first(where: { $0.id == id }) { open(entry) }
    }

    private var focusedIndex: Int { apps.firstIndex { $0.id == model.miniAppsFocusedID } ?? 0 }

    private func open(_ app: MiniAppGalleryEntry) {
        if initialAppID == nil { model.miniAppsFocusedID = app.id }
        if app.generated { generated = app }
        else { selected = app }
    }

    private func focus(_ index: Int) {
        guard apps.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            model.miniAppsFocusedID = apps[index].id
        }
    }

    private func appList(width: CGFloat) -> some View {
        let gap = MobileDesignGeometry.miniappListGap
        let coverSize = MobileDesignGeometry.miniappListCoverSize
        let shape = RoundedRectangle(cornerRadius: MobileDesignGeometry.miniappListRadius)
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: width >= 840 ? 2 : 1),
                      alignment: .leading, spacing: gap) {
                ForEach(apps) { app in
                    Button { open(app) } label: {
                        HStack(spacing: 0) {
                            cover(app, width: min(coverSize, width * 0.36), height: coverSize)
                            appCopy(app, titleLines: 2)
                                .padding(16)
                        }
                        .background(OpenBitFunTheme.card)
                        .clipShape(shape)
                        .overlay { shape.strokeBorder(OpenBitFunTheme.line, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("miniapp:\(app.id)")
                    .contextMenu { appActions(app) }
                    .accessibilityAction(named: Text(model.localized("添加桌面图标"))) { desktopApp = app }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func appDeck(width: CGFloat) -> some View {
        let cardWidth = min(width * 0.82, width >= 840 ? MobileDesignGeometry.miniappWideCardWidth
                            : width >= 600 ? MobileDesignGeometry.miniappFoldCardWidth : MobileDesignGeometry.miniappCardWidth)
        let maxHeight = width >= 840 ? MobileDesignGeometry.miniappWideCardHeight
            : width >= 600 ? MobileDesignGeometry.miniappFoldCardHeight : MobileDesignGeometry.miniappCardHeight
        return VStack(spacing: 0) {
            GeometryReader { geometry in
                let height = min(maxHeight, max(0, geometry.size.height - 40))
                ZStack {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        let distance = index - focusedIndex
                        let active = distance == 0
                        Button { open(app) } label: {
                            VStack(spacing: 0) {
                                cover(app, width: cardWidth, height: height * 0.65)
                                appCopy(app, titleLines: 1)
                                    .padding(.horizontal, 20)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(width: cardWidth, height: height)
                            .background(OpenBitFunTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: MobileDesignGeometry.miniappCardRadius))
                            .shadow(color: OpenBitFunTheme.shadowSubtle, radius: 16, y: 6)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(active ? 1 : 0.85)
                        .rotationEffect(.degrees(active ? 0 : distance < 0 ? -5 : 5))
                        .offset(x: CGFloat(distance) * (width >= 600 ? 60 : 70))
                        .opacity(active ? 1 : abs(distance) == 1 ? 0.6 : 0)
                        .zIndex(active ? 3 : 1)
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                        .accessibilityIdentifier("miniapp:\(app.id)")
                        .contextMenu { if active { appActions(app) } }
                        .accessibilityAction(named: Text(model.localized("添加桌面图标"))) { desktopApp = app }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .clipped()
                .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > 48, abs(dx) > abs(value.translation.height) else { return }
                    focus(focusedIndex + (dx < 0 ? 1 : -1))
                })
                .accessibilityScrollAction { edge in
                    if edge == .trailing { focus(focusedIndex + 1) }
                    if edge == .leading { focus(focusedIndex - 1) }
                }
            }
            HStack(spacing: 8) {
                ForEach(apps.indices, id: \.self) { index in
                    Capsule()
                        .fill(OpenBitFunTheme.ink.opacity(index == focusedIndex ? 1 : 0.4))
                        .frame(width: index == focusedIndex ? 24 : 8, height: 8)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
            Text(model.localized("左右滑动浏览"))
                .font(MobileDesignTypography.labelSmall.font)
                .foregroundStyle(OpenBitFunTheme.muted)
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func appActions(_ app: MiniAppGalleryEntry) -> some View {
        Button {
            desktopApp = app
        } label: {
            Label(model.localized("添加桌面图标"), systemImage: "plus.app")
        }
        Button {
            UIPasteboard.general.url = MiniAppLaunch.link(app.id)
        } label: {
            Label(model.localized("拷贝启动链接"), systemImage: "link")
        }
        if app.generated {
            Button(model.localized("从小应用移除"), role: .destructive) {
                local.dispatch(LocalGenUiIntentSetGallery(id: app.id, added: false))
            }
        }
    }

    private func cover(_ app: MiniAppGalleryEntry, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if app.generated {
                LocalGenUiPreview(id: app.id) { thumbnail in
                    ZStack {
                        MobileDesignColors.connectHeroSurface
                        if let thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFit()
                        } else {
                            Image("MiniAppView-list")
                                .renderingMode(.template)
                                .resizable().scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundStyle(MobileDesignColors.connectHeroAccent)
                        }
                    }
                }
            } else {
                Image("miniapp-\(app.id)")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    private func appCopy(_ app: MiniAppGalleryEntry, titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.name)
                .font(MobileDesignTypography.titleSmall.font.bold())
                .lineLimit(titleLines)
            Text(app.description)
                .font(MobileDesignTypography.bodyMedium.font)
                .foregroundStyle(OpenBitFunTheme.muted)
                .lineLimit(3)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadApps() async {
        failure = nil
        do {
            guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "MiniApps") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let loaded = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode([BuiltinMiniApp].self, from: Data(contentsOf: url))
            }.value
            guard !Task.isCancelled else { return }
            builtins = loaded
            openInitialApp()
        } catch { failure = model.localized("无法加载小应用，请重试") }
    }
}

private struct MiniAppWebView: UIViewRepresentable {
    let appID: String
    let locale: String
    func makeCoordinator() -> Coordinator { Coordinator(appID: appID) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "miniappNative")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        if let url = Bundle.main.url(forResource: "\(appID).\(locale)", withExtension: "html", subdirectory: "MiniApps") {
            context.coordinator.loadTask = Task { @MainActor [weak web] in
                let html = await Task.detached(priority: .userInitiated) {
                    try? String(contentsOf: url, encoding: .utf8)
                }.value
                guard !Task.isCancelled, let html else { return }
                web?.loadHTMLString(html, baseURL: URL(string: "https://miniapp.local/"))
            }
        }
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "miniappNative")
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let appID: String
        weak var web: WKWebView?
        var loadTask: Task<Void, Never>?
        private static let storageQueue = DispatchQueue(label: "com.openbitfun.miniapps.storage")
        init(appID: String) { self.appID = appID }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            // Only our initial document and its isolated blob frame may navigate.
            decisionHandler(url?.scheme == "blob" || url?.absoluteString == "about:blank" ||
                (url?.absoluteString == "https://miniapp.local/" && navigationAction.navigationType == .other) ? .allow : .cancel)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let raw = message.body as? String, let data = raw.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = request["id"] as? String,
                  let method = request["method"] as? String,
                  let params = request["params"] as? [String: Any] else { return }
            if method == "clipboard.writeText", let text = params["text"] as? String {
                UIPasteboard.general.string = text
                respond(id: id, result: NSNull(), error: nil)
                return
            }
            Self.storageQueue.async { [self] in
                do {
                    let key = params["key"] as? String
                    let allowed = ["builtin-gomoku": "stats", "builtin-regex-playground": "regex-state", "builtin-daily-divination": "lastReading"]
                    guard let key, key == allowed[self.appID], ["storage.get", "storage.set"].contains(method) else {
                        throw CocoaError(.featureUnsupported)
                    }
                    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("miniapps", isDirectory: true)
                    let file = directory.appendingPathComponent("\(self.appID)-\(key).json")
                    var result: Any = NSNull()
                    if method == "storage.get" {
                        if FileManager.default.fileExists(atPath: file.path) {
                            result = try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: [.fragmentsAllowed])
                        }
                    } else {
                        let bytes = try JSONSerialization.data(withJSONObject: params["value"] ?? NSNull(), options: [.fragmentsAllowed])
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try bytes.write(to: file, options: .atomic)
                    }
                    DispatchQueue.main.async { self.respond(id: id, result: result, error: nil) }
                } catch {
                    DispatchQueue.main.async { self.respond(id: id, result: NSNull(), error: error.localizedDescription) }
                }
            }
        }
        private func respond(id: String, result: Any, error: String?) {
            var response: [String: Any] = ["id": id, "result": result]
            if let error { response["error"] = ["message": error] }
            guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.fragmentsAllowed]),
                  let json = String(data: data, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.__miniappReply(\(json))", completionHandler: nil)
        }
    }
}
