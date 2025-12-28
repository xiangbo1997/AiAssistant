//
//  MemoEditorView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-27.
//  备忘录编辑器 - 添加/编辑备忘录
//

import SwiftUI

struct MemoEditorView: View {
    enum Mode {
        case add
        case edit(MemoItem)
    }

    let mode: Mode
    let onSave: (MemoItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var type: MemoType
    @State private var title: String
    @State private var content: String
    @State private var username: String
    @State private var url: String
    @State private var tags: [String]
    @State private var isFavorite: Bool
    @State private var newTag: String = ""
    @State private var showContent = false

    init(mode: Mode, onSave: @escaping (MemoItem) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .add:
            _type = State(initialValue: .command)
            _title = State(initialValue: "")
            _content = State(initialValue: "")
            _username = State(initialValue: "")
            _url = State(initialValue: "")
            _tags = State(initialValue: [])
            _isFavorite = State(initialValue: false)
        case .edit(let memo):
            _type = State(initialValue: memo.type)
            _title = State(initialValue: memo.title)
            _content = State(initialValue: memo.content)
            _username = State(initialValue: memo.username ?? "")
            _url = State(initialValue: memo.url ?? "")
            _tags = State(initialValue: memo.tags)
            _isFavorite = State(initialValue: memo.isFavorite)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerBar

            Divider()

            // 表单内容
            ScrollView {
                VStack(spacing: 20) {
                    // 类型选择
                    typeSelector

                    // 基本信息
                    basicInfoSection

                    // 内容区域
                    contentSection

                    // 账号专属字段
                    if type == .credential {
                        credentialSection
                    }

                    // URL
                    urlSection

                    // 标签
                    tagsSection
                }
                .padding(20)
            }

            Divider()

            // 底部按钮
            footerBar
        }
        .frame(width: 420, height: 560)
        .background(BuBuColors.warmGradient)
    }

    // MARK: - 标题栏

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(isEditing ? "编辑备忘录" : "新建备忘录")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown)

            Spacer()

            // 收藏按钮
            Button {
                isFavorite.toggle()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isFavorite ? BuBuColors.sunshineYellow : BuBuColors.chocolateBrown.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(BuBuColors.creamWhite)
    }

    // MARK: - 类型选择

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("类型")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

            HStack(spacing: 10) {
                ForEach(MemoType.allCases, id: \.self) { memoType in
                    TypeButton(
                        type: memoType,
                        isSelected: type == memoType
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            type = memoType
                        }
                    }
                }
            }
        }
    }

    // MARK: - 基本信息

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("标题")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

            TextField("输入标题...", text: $title)
                .textFieldStyle(.plain)
                .font(BuBuFonts.body)
                .foregroundColor(BuBuColors.chocolateBrown)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                        .fill(Color.white)
                        .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
                )
        }
    }

    // MARK: - 内容区域

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(contentLabel)
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

                Spacer()

                // 显示/隐藏切换
                Button {
                    showContent.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showContent ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                        Text(showContent ? "隐藏" : "显示")
                            .font(BuBuFonts.tiny)
                    }
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            ZStack(alignment: .topLeading) {
                if showContent {
                    TextEditor(text: $content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(BuBuColors.chocolateBrown)
                        .scrollContentBackground(.hidden)
                } else {
                    // 密码遮罩模式
                    TextEditor(text: $content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.clear)
                        .scrollContentBackground(.hidden)
                        .overlay(
                            Text(String(repeating: "•", count: content.count))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(4)
                                .allowsHitTesting(false)
                        )
                }

                if content.isEmpty {
                    Text(contentPlaceholder)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.3))
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 80)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .stroke(type.color.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - 账号专属字段

    private var credentialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("用户名")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 15))
                    .foregroundColor(BuBuColors.coralPink)

                TextField("输入用户名...", text: $username)
                    .textFieldStyle(.plain)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
            )
        }
    }

    // MARK: - URL

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关联链接（可选）")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 15))
                    .foregroundColor(BuBuColors.skyBlue)

                TextField("https://...", text: $url)
                    .textFieldStyle(.plain)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
            )
        }
    }

    // MARK: - 标签

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("标签")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

            // 已有标签
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(BuBuFonts.caption)

                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundColor(type.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(type.color.opacity(0.15))
                        )
                    }
                }
            }

            // 添加新标签
            HStack(spacing: 10) {
                TextField("添加标签...", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
                    .onSubmit {
                        addTag()
                    }

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(type.color)
                }
                .buttonStyle(.plain)
                .disabled(newTag.isEmpty)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
            )
        }
    }

    // MARK: - 底部按钮

    private var footerBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(BuBuFonts.headline)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                            .fill(Color.white)
                            .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 6, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)

            Button {
                save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isEditing ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .medium))
                    Text(isEditing ? "保存" : "添加")
                        .font(BuBuFonts.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(
                            LinearGradient(
                                colors: [type.color, type.color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: type.color.opacity(0.4), radius: 10, x: 0, y: 5)
                )
            }
            .buttonStyle(.plain)
            .disabled(title.isEmpty || content.isEmpty)
            .opacity(title.isEmpty || content.isEmpty ? 0.6 : 1)
        }
        .padding(18)
        .background(BuBuColors.creamWhite)
    }

    // MARK: - 辅助属性和方法

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var contentLabel: String {
        switch type {
        case .command: return "命令"
        case .credential: return "密码"
        case .snippet: return "代码"
        case .note: return "内容"
        }
    }

    private var contentPlaceholder: String {
        switch type {
        case .command: return "输入命令..."
        case .credential: return "输入密码..."
        case .snippet: return "输入代码片段..."
        case .note: return "输入备注内容..."
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }

    private func save() {
        var memo: MemoItem

        switch mode {
        case .add:
            memo = MemoItem(
                type: type,
                title: title,
                content: content,
                username: type == .credential ? username : nil,
                url: url.isEmpty ? nil : url,
                tags: tags,
                isFavorite: isFavorite
            )
        case .edit(let existing):
            memo = existing
            memo.type = type
            memo.title = title
            memo.content = content
            memo.username = type == .credential ? username : nil
            memo.url = url.isEmpty ? nil : url
            memo.tags = tags
            memo.isFavorite = isFavorite
            memo.updatedAt = Date()
        }

        onSave(memo)
        dismiss()
    }
}

// MARK: - 类型按钮

struct TypeButton: View {
    let type: MemoType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .medium))

                Text(type.title)
                    .font(BuBuFonts.tiny)
            }
            .foregroundColor(isSelected ? .white : type.color)
            .frame(width: 70, height: 60)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                    .fill(isSelected ? type.color : type.color.opacity(0.12))
                    .shadow(
                        color: isSelected ? type.color.opacity(0.4) : Color.clear,
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 预览

#Preview {
    MemoEditorView(mode: .add) { _ in }
}
