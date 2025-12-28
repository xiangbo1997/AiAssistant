//
//  NoteEditorView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  便签编辑视图 - 创建和编辑便签
//

import SwiftUI

struct NoteDTOEditorView: View {
    enum Mode {
        case add
        case edit(NoteDTO)
    }

    let mode: Mode
    let onSave: (NoteDTO) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var priority: NotePriority = .medium
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @State private var hasReminder: Bool = false
    @State private var reminderDate: Date = Date()
    @State private var repeatType: RepeatType = .none

    init(mode: Mode, onSave: @escaping (NoteDTO) -> Void) {
        self.mode = mode
        self.onSave = onSave

        // 编辑模式时初始化值
        if case .edit(let note) = mode {
            _title = State(initialValue: note.title)
            _content = State(initialValue: note.content)
            _priority = State(initialValue: note.priority)
            _tags = State(initialValue: note.tags)
            _hasReminder = State(initialValue: note.reminderDate != nil)
            _reminderDate = State(initialValue: note.reminderDate ?? Date())
            _repeatType = State(initialValue: note.repeatType)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            header

            Divider()

            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 标题输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("标题")
                            .font(BuBuFonts.headline)
                            .foregroundColor(BuBuColors.chocolateBrown)
                        TextField("便签标题", text: $title)
                            .textFieldStyle(.plain)
                            .font(BuBuFonts.body)
                            .foregroundColor(BuBuColors.chocolateBrown)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                                    .fill(Color.white)
                                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 4, x: 0, y: 2)
                            )
                    }

                    // 内容输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("内容")
                            .font(BuBuFonts.headline)
                            .foregroundColor(BuBuColors.chocolateBrown)
                        TextEditor(text: $content)
                            .font(BuBuFonts.body)
                            .foregroundColor(BuBuColors.chocolateBrown)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                                    .fill(Color.white)
                                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 4, x: 0, y: 2)
                            )
                    }

                    // 优先级选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("优先级")
                            .font(BuBuFonts.headline)
                            .foregroundColor(BuBuColors.chocolateBrown)
                        HStack(spacing: 10) {
                            ForEach(NotePriority.allCases, id: \.self) { p in
                                Button {
                                    priority = p
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(p.bubuColor)
                                            .frame(width: 10, height: 10)
                                        Text(p.title)
                                            .font(BuBuFonts.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                                            .fill(priority == p ? p.bubuColor.opacity(0.2) : Color.white)
                                            .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 4, x: 0, y: 2)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                                            .stroke(priority == p ? p.bubuColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(BuBuColors.chocolateBrown)
                            }
                        }
                    }

                    // 标签
                    VStack(alignment: .leading, spacing: 8) {
                        Text("标签")
                            .font(BuBuFonts.headline)
                            .foregroundColor(BuBuColors.chocolateBrown)

                        // 已添加的标签
                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                TagChip(tag: tag) {
                                    tags.removeAll { $0 == tag }
                                }
                            }
                        }

                        // 添加新标签
                        HStack(spacing: 10) {
                            TextField("添加标签", text: $newTag)
                                .textFieldStyle(.plain)
                                .font(BuBuFonts.body)
                                .foregroundColor(BuBuColors.chocolateBrown)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                                        .fill(Color.white)
                                        .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 4, x: 0, y: 2)
                                )
                                .onSubmit {
                                    addTag()
                                }

                            Button {
                                addTag()
                            } label: {
                                Text("添加")
                                    .font(BuBuFonts.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                                            .fill(newTag.isEmpty ? BuBuColors.chocolateBrown.opacity(0.3) : BuBuColors.skyBlue)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(newTag.isEmpty)
                        }
                    }

                    // 提醒设置
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $hasReminder) {
                            Text("设置提醒")
                                .font(BuBuFonts.headline)
                                .foregroundColor(BuBuColors.chocolateBrown)
                        }
                        .tint(BuBuColors.skyBlue)

                        if hasReminder {
                            VStack(alignment: .leading, spacing: 10) {
                                DatePicker(
                                    "提醒时间",
                                    selection: $reminderDate,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .font(BuBuFonts.body)
                                .tint(BuBuColors.skyBlue)

                                Picker("重复", selection: $repeatType) {
                                    ForEach(RepeatType.allCases, id: \.self) { type in
                                        Text(type.title).tag(type)
                                    }
                                }
                                .font(BuBuFonts.body)
                                .tint(BuBuColors.skyBlue)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                                    .fill(BuBuColors.lavender.opacity(0.1))
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(BuBuColors.creamWhite)
        }
        .frame(width: 420, height: 520)
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(mode.isEdit ? "编辑便签" : "新建便签")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown)

            Spacer()

            Button {
                saveNote()
            } label: {
                Text("保存")
                    .font(BuBuFonts.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                            .fill(title.isEmpty ? BuBuColors.chocolateBrown.opacity(0.3) : BuBuColors.skyBlue)
                    )
            }
            .buttonStyle(.plain)
            .disabled(title.isEmpty)
        }
        .padding(16)
        .background(BuBuColors.creamWhite)
    }

    // MARK: - 方法

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
            newTag = ""
        }
    }

    private func saveNote() {
        var note: NoteDTO

        if case .edit(let existingNote) = mode {
            note = existingNote
        } else {
            note = NoteDTO(title: title)
        }

        note.title = title
        note.content = content
        note.priority = priority
        note.tags = tags
        note.reminderDate = hasReminder ? reminderDate : nil
        note.repeatType = hasReminder ? repeatType : .none

        onSave(note)
        dismiss()
    }
}

// MARK: - Mode 扩展

extension NoteDTOEditorView.Mode {
    var isEdit: Bool {
        if case .edit = self {
            return true
        }
        return false
    }
}

// MARK: - 标签芯片

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(BuBuFonts.tiny)
                .foregroundColor(BuBuColors.skyBlue)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(BuBuColors.skyBlue.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BuBuColors.skyBlue.opacity(0.15))
        )
    }
}

// MARK: - 流式布局

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, spacing: spacing, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, spacing: spacing, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0

        init(in width: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            height = y + rowHeight
        }
    }
}

// MARK: - 预览

#Preview("新建") {
    NoteDTOEditorView(mode: .add) { _ in }
}

#Preview("编辑") {
    NoteDTOEditorView(mode: .edit(NoteDTO(title: "测试便签", content: "这是测试内容"))) { _ in }
}
