import OpenBitFunMobileCore
import SwiftUI
import UniformTypeIdentifiers

struct GenUiCopyAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct GenUiTranscriptMessage: View {
    @ObservedObject var model: MobileAppModel
    let message: LocalGenUiMessage
    let app: LocalGenUiApp?
    let copyMenuOpen: Bool
    let onCopyMenu: () -> Void
    let onOpenFullText: () -> Void
    let onOpenApp: () -> Void

    private var user: Bool { message.role == "user" }
    private var text: String { message.automaticRepair ? model.localized("刚才的应用有点问题，正在自动修正") : message.text }
    private var cardStatus: String {
        if message.preparingApp { return model.localized("正在准备") }
        if message.appGenerationFailed { return model.localized("没有生成成功") }
        if message.failure?.name == "STATE_MIGRATION_REQUIRED" {
            return model.localized("新版本和已有数据不兼容，已保留原来的版本")
        }
        return model.localized("可以使用")
    }

    var body: some View {
        VStack(alignment: user ? .trailing : .leading, spacing: user ? 6 : 10) {
            if !text.isEmpty {
                if user {
                    IntrinsicWidthCapLayout(maxWidth: MobileDesignGeometry.messageBubbleMaxWidth) {
                        userMessage
                            .padding(.horizontal, MobileDesignGeometry.messageBubbleHorizontalPadding)
                            .padding(.vertical, MobileDesignGeometry.messageBubbleVerticalPadding)
                            .background(OpenBitFunTheme.soft, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.messageBubbleRadius))
                    }
                } else {
                    MarkdownMessageView(text: text, model: model, openExternalLinksOnly: true)
                }
            }
            if let appId = message.appId, let title = message.appTitle ?? app?.title {
                GenUiMessageAppCard(model: model, appId: appId, title: title, status: cardStatus, onOpen: onOpenApp)
            } else if let failure = message.failure {
                GenUiErrorText(model: model, failureCode: failure.name)
            }
            HStack(spacing: 0) {
                if let time = message.createdAtMillis {
                    let date = Date(timeIntervalSince1970: time.doubleValue / 1000)
                    Text(MobileLocalization.messageTime(date, language: model.appLanguage))
                        .font(MobileDesignTypography.labelSmall.font)
                        .foregroundStyle(OpenBitFunTheme.muted)
                        .accessibilityIdentifier("local-genui-message-time")
                }
                if !user && !message.text.isEmpty {
                    Button(action: onCopyMenu) {
                        ReferenceGlyph(assetName: "ChatCopyGlyph", width: MobileDesignGeometry.messageActionIconSize,
                                       height: MobileDesignGeometry.messageActionIconSize, color: OpenBitFunTheme.muted)
                            .frame(width: MobileDesignGeometry.messageActionTouchSize, height: MobileDesignGeometry.messageActionTouchSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.localized("复制"))
                    .accessibilityIdentifier("local-genui-message-copy")
                    .anchorPreference(key: GenUiCopyAnchor.self, value: .bounds) { copyMenuOpen ? $0 : nil }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var userMessage: some View {
        if let preview = UserMessageTruncationPolicy.shared.truncatedPreview(text: text) {
            Text(fullTextLink(preview))
                .font(MobileDesignTypography.bodyLarge.font)
                .lineSpacing(MobileDesignTypography.bodyLarge.lineSpacing)
                .environment(\.openURL, OpenURLAction { _ in
                    onOpenFullText()
                    return .handled
                })
                .accessibilityIdentifier("local-genui-truncated-message")
                .accessibilityAction(named: Text(model.localized("全文"))) { onOpenFullText() }
                .contextMenu {
                    Button(model.localized("复制全文")) { UIPasteboard.general.string = text }
                }
        } else {
            Text(text)
                .font(MobileDesignTypography.bodyLarge.font)
                .lineSpacing(MobileDesignTypography.bodyLarge.lineSpacing)
                .textSelection(.enabled)
        }
    }

    private func fullTextLink(_ preview: String) -> AttributedString {
        var link = AttributedString(model.localized("全文"))
        link.font = MobileDesignTypography.bodyMedium.font
        link.foregroundColor = MobileDesignColors.fileLink
        link.underlineStyle = .single
        link.link = URL(string: "openbitfun-genui-full-text://message")
        return AttributedString(preview + " ") + link
    }
}

struct GenUiFullTextSheet: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OpenBitFunModalHeader(title: "全文", onClose: onClose)
                .padding(.leading, MobileDesignGeometry.sheetHorizontalPadding)
                .padding(.trailing, 12)
            Rectangle().fill(OpenBitFunTheme.line).frame(height: 0.5)
            ScrollView(showsIndicators: false) {
                Text(text)
                    .font(MobileDesignTypography.bodyMedium.font)
                    .lineSpacing(MobileDesignTypography.bodyMedium.lineSpacing)
                    .foregroundStyle(OpenBitFunTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("local-genui-full-text-content")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MobileDesignGeometry.sheetHorizontalPadding)
                    .padding(.top, 18).padding(.bottom, 24)
            }
        }
        .accessibilityIdentifier("local-genui-full-text-sheet")
    }
}

struct GenUiCopyMenu: View {
    @ObservedObject var model: MobileAppModel
    let source: String
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            action("复制（富文本）") {
                UIPasteboard.general.setItems([[
                    UTType.html.identifier: Data(MarkdownClipboard.shared.html(source: source).utf8),
                    UTType.utf8PlainText.identifier: MarkdownClipboard.shared.plainText(source: source)
                ]])
            }
            action("复制 Markdown") { UIPasteboard.general.string = source }
            action("复制纯文本") { UIPasteboard.general.string = MarkdownClipboard.shared.plainText(source: source) }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(width: MobileDesignGeometry.compactPopoverWidth)
        .background(OpenBitFunTheme.card, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.compactPopoverRadius))
        .overlay(RoundedRectangle(cornerRadius: MobileDesignGeometry.compactPopoverRadius)
            .strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
        .shadow(color: OpenBitFunTheme.shadowSubtle, radius: 10, y: 3)
        .accessibilityAction(.escape, dismiss)
    }

    private func action(_ title: String, copy: @escaping () -> Void) -> some View {
        Button {
            copy()
            dismiss()
        } label: {
            Text(model.localized(title))
                .font(MobileDesignTypography.bodySmall.font)
                .foregroundStyle(OpenBitFunTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: MobileDesignGeometry.compactPopoverActionHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GenUiMessageAppCard: View {
    @ObservedObject var model: MobileAppModel
    let appId: String
    let title: String
    let status: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: MobileDesignGeometry.messageAppCardPadding) {
                LocalGenUiPreview(id: appId) { preview($0) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(MobileDesignTypography.titleSmall.font.weight(.medium))
                        .foregroundStyle(OpenBitFunTheme.ink)
                        .lineLimit(2)
                    Text(status)
                        .font(MobileDesignTypography.labelSmall.font)
                        .foregroundStyle(OpenBitFunTheme.muted)
                        .lineLimit(1)
                    Text(model.localized("打开"))
                        .font(MobileDesignTypography.labelMedium.font.weight(.medium))
                        .foregroundStyle(OpenBitFunTheme.contentOnAction)
                        .padding(.horizontal, MobileDesignGeometry.messageAppOpenHorizontalPadding)
                        .padding(.vertical, MobileDesignGeometry.messageAppOpenVerticalPadding)
                        .background(MobileDesignColors.primaryAction, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.messageAppOpenRadius))
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(MobileDesignGeometry.messageAppCardPadding)
            .background(OpenBitFunTheme.card, in: RoundedRectangle(cornerRadius: MobileDesignGeometry.messageAppCardRadius))
            .overlay(RoundedRectangle(cornerRadius: MobileDesignGeometry.messageAppCardRadius).strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
            .shadow(color: MobileDesignColors.shadowFaint, radius: 12, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(status)
    }

    private func preview(_ thumbnail: UIImage?) -> some View {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = RoundedRectangle(cornerRadius: MobileDesignGeometry.messageAppPreviewRadius)
        let size = MobileDesignGeometry.messageAppPreviewSize
        return ZStack(alignment: .bottomTrailing) {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
                    .frame(width: size, height: size).clipped()
            } else {
                LinearGradient(colors: [MobileDesignColors.connectHeroSurface, MobileDesignColors.connectHeroBg],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Text(trimmedTitle.first.map(String.init) ?? "AI")
                            .font(MobileDesignTypography.displayLarge.font.weight(.bold))
                            .foregroundStyle(MobileDesignColors.connectHeroAccent)
                    }
            }
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11))
                .foregroundStyle(OpenBitFunTheme.contentOnAction)
                .frame(width: MobileDesignGeometry.messageAppBadgeSize, height: MobileDesignGeometry.messageAppBadgeSize)
                .background(MobileDesignColors.toastBackground, in: Circle())
                .padding(MobileDesignGeometry.messageAppBadgeInset)
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(OpenBitFunTheme.line, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
