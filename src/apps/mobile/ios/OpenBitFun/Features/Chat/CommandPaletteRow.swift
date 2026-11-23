import SwiftUI

struct CommandPaletteRow: View {
    @ObservedObject var model: MobileAppModel
    @State private var sheet: PaletteSheet?
    @State private var skillQuery = ""

    private enum PaletteSheet: Identifiable, Equatable {
        case skills, usage
        var id: String { self == .skills ? "skills" : "usage" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("压缩会话", systemImage: "arrow.up.left.and.arrow.down.right") {
                        model.runCommandPaletteAction("compact")
                    } disabled: { model.busy || !model.commandPalette.runningCommand.isEmpty }
                    chip("生成 AGENTS.md", systemImage: "doc.badge.plus") {
                        model.runCommandPaletteAction("init_agents_md")
                    } disabled: { model.busy || !model.commandPalette.runningCommand.isEmpty }
                    chip("会话目标", systemImage: "checklist", filled: model.draft == "/goal ") {
                        if model.draft == "/goal " {
                            model.draft = ""
                        } else if model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            model.draft = "/goal "
                        }
                    }
                    chip("会话用量", systemImage: "square.grid.2x2") {
                        sheet = .usage
                        model.refreshCommandPaletteUsage()
                    } disabled: { model.busy || !model.commandPalette.runningCommand.isEmpty }
                    chip("技能",
                         systemImage: "wrench.and.screwdriver") {
                        sheet = .skills
                    }
                }
                .padding(.horizontal, MobileDesignGeometry.conversationOverlaySideInset)
            }
            .accessibilityIdentifier("commandPalette.chips")
            if !model.commandPalette.noticeLabelKey.isEmpty {
                HStack(spacing: 8) {
                    Text(model.commandPalette.noticeDetail.isEmpty ? noticeText : model.commandPalette.noticeDetail)
                        .font(MobileDesignTypography.labelSmall.font)
                        .foregroundStyle(OpenBitFunTheme.muted)
                    if !model.commandPalette.noticeRetryAction.isEmpty {
                        Button("重试") { model.runCommandPaletteAction(model.commandPalette.noticeRetryAction) }
                            .font(MobileDesignTypography.labelSmall.font)
                    }
                }
                .padding(.horizontal, MobileDesignGeometry.conversationOverlaySideInset)
            }
        }
        .sheet(item: $sheet) { value in
            switch value {
            case .skills:
                skillsSheet
            case .usage:
                usageSheet
            }
        }
    }

    private var noticeText: String {
        switch model.commandPalette.noticeLabelKey {
        case "commands.compactDone": return "会话已压缩"
        case "commands.initDone": return "AGENTS.md 已生成"
        case "commands.compactFailed": return "会话压缩失败"
        case "commands.initFailed": return "AGENTS.md 生成失败"
        case "chat.rolledBackNotice": return "已回退到此消息"
        case "chat.rollbackFailed": return "回退失败"
        default: return model.commandPalette.noticeLabelKey
        }
    }

    private func chip(_ title: String, systemImage: String, filled: Bool = false, action: @escaping () -> Void, disabled: @escaping () -> Bool = { false }) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(MobileDesignTypography.bodySmall.font)
                .foregroundStyle(filled ? OpenBitFunTheme.contentOnAction : OpenBitFunTheme.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background((filled ? OpenBitFunTheme.ink : OpenBitFunTheme.soft), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled())
    }

    private var skillsSheet: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索技能", text: $skillQuery)
                }
                if model.commandPalette.catalogStatus == "LOADING" {
                    ProgressView("正在读取")
                } else if model.commandPalette.catalogStatus == "FAILED" {
                    Text(model.commandPalette.catalogError.isEmpty ? "技能目录读取失败" : model.commandPalette.catalogError)
                    Button("重试") { model.refreshCommandCatalog() }
                } else if model.commandPalette.skills.isEmpty {
                    Text("当前模式没有可用技能")
                } else {
                    ForEach(Array(skillGroups.keys.sorted()), id: \.self) { group in
                        Section(group) {
                            ForEach(skillGroups[group] ?? []) { skill in
                                Button {
                                    model.selectCommandPaletteSkill(id: skill.id, label: skill.name)
                                    sheet = nil
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(skill.name).foregroundStyle(OpenBitFunTheme.ink)
                                            Spacer()
                                            if model.commandPalette.skillID == skill.id { Image(systemName: "checkmark") }
                                        }
                                        if !skill.description.isEmpty { Text(skill.description).font(.footnote).foregroundStyle(OpenBitFunTheme.muted) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择技能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { sheet = nil }
                }
            }
        }
    }

    private var skillGroups: [String: [MobileCommandPaletteSkill]] {
        Dictionary(grouping: model.commandPalette.skills.filter {
            skillQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(skillQuery) || $0.id.localizedCaseInsensitiveContains(skillQuery) || $0.description.localizedCaseInsensitiveContains(skillQuery)
        }) { skill in
            let group = skill.group.trimmingCharacters(in: .whitespacesAndNewlines)
            return group.isEmpty ? (skill.source == "builtin" ? "内置" : "自定义") : group
        }
    }

    private var usageSheet: some View {
        NavigationStack {
            Group {
                if model.commandPalette.usageStatus == "LOADING" {
                    ProgressView("正在读取")
                } else if model.commandPalette.usageStatus == "FAILED" {
                    VStack(spacing: 12) {
                        Text(model.commandPalette.usageError.isEmpty ? "会话用量读取失败" : model.commandPalette.usageError)
                        Button("重试") { model.refreshCommandPaletteUsage() }
                    }
                } else if model.commandPalette.usageSections.isEmpty {
                    Text("当前会话没有可用用量数据").foregroundStyle(OpenBitFunTheme.muted)
                } else {
                    List {
                        ForEach(model.commandPalette.usageSections) { section in
                            Section(usageLabel(section.titleKey)) {
                                ForEach(section.rows) { row in
                                    HStack {
                                        Text(usageLabel(row.labelKey))
                                        Spacer()
                                        Text(row.valueKey.isEmpty ? row.value : usageValue(row.valueKey)).foregroundStyle(OpenBitFunTheme.muted)
                                    }
                                }
                            }
                        }
                        if model.commandPalette.usagePartial {
                            Text("部分指标不可用")
                                .font(.footnote)
                                .foregroundStyle(OpenBitFunTheme.muted)
                        }
                    }
                }
            }
            .navigationTitle("会话用量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { sheet = nil }
                }
            }
        }
    }

    private func usageLabel(_ key: String) -> String {
        switch key {
        case "usage.sectionOverview": return "概览"
        case "usage.sectionTime": return "时间"
        case "usage.sectionTokens": return "令牌"
        case "usage.sectionModels": return "模型"
        case "usage.sectionTools": return "工具"
        case "usage.sectionFiles": return "文件"
        case "usage.sectionCompression": return "压缩"
        case "usage.sectionErrors": return "错误"
        case "usage.sectionPrivacy": return "隐私"
        case "usage.scopeTurns": return "轮次"
        case "usage.scopeKind": return "范围"
        case "usage.scopeSubagents": return "包含子代理"
        case "usage.coverageLevel": return "覆盖范围"
        case "usage.coverageMissing": return "缺少指标"
        case "usage.workspace": return "工作区"
        case "usage.timeSpan": return "总耗时"
        case "usage.timeTurns": return "活跃轮次"
        case "usage.timeModel": return "模型耗时"
        case "usage.timeTools": return "工具耗时"
        case "usage.tokensInput": return "输入令牌"
        case "usage.tokensOutput": return "输出令牌"
        case "usage.tokensTotal": return "总令牌"
        case "usage.tokensCached": return "缓存令牌"
        case "usage.filesChanged": return "变更文件"
        case "usage.filesAdded": return "新增行"
        case "usage.filesDeleted": return "删除行"
        case "usage.compactionCount": return "压缩次数"
        case "usage.manualCompactionCount": return "手动压缩"
        case "usage.automaticCompactionCount": return "自动压缩"
        case "usage.compactionSaved": return "节省令牌"
        case "usage.errorsTotal": return "总错误"
        case "usage.errorsTools": return "工具错误"
        case "usage.errorsModels": return "模型错误"
        case "usage.privacyPrompt": return "包含提示内容"
        case "usage.privacyTools": return "包含工具输入"
        case "usage.privacyCommands": return "包含命令输出"
        case "usage.privacyFiles": return "包含文件内容"
        default: return key
        }
    }

    private func usageValue(_ key: String) -> String { key == "usage.yes" ? "是" : "否" }
}
