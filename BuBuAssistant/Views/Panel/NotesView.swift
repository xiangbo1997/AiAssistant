//
//  NotesView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  便签视图 - 显示和管理便签列表
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 优先级布布主题扩展

extension NotePriority {
    var bubuColor: Color {
        switch self {
        case .low: return BuBuColors.lavender
        case .medium: return BuBuColors.skyBlue
        case .high: return BuBuColors.peachBlush
        case .urgent: return BuBuColors.coralPink
        }
    }
}

struct NotesView: View {
    @EnvironmentObject var viewModel: NotesViewModel
    @State private var showingAddNote = false
    @State private var searchText = ""
    @State private var selectedFilter: NoteListFilter = .all
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var importResult: ImportResult?
    @State private var showingImportResult = false
    @State private var currentViewMode: NoteViewMode = .list

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbar

            Divider()

            // 便签内容区域
            if filteredNotes.isEmpty {
                emptyStateView
            } else {
                switch currentViewMode {
                case .list:
                    notesList
                case .card:
                    notesCardView
                case .kanban:
                    notesKanbanView
                }
            }
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 14) {
            // 搜索框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(BuBuColors.skyBlue)
                TextField("搜索便签...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 8, x: 0, y: 3)
            )

            // 筛选菜单
            Menu {
                ForEach(NoteListFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack {
                            Text(filter.title)
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(BuBuColors.skyBlue)
            }
            .menuStyle(.borderlessButton)

            // 更多操作菜单（导入/导出）
            Menu {
                Button {
                    exportNotes()
                } label: {
                    Label("导出便签", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("导入便签", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(BuBuColors.lavender)
            }
            .menuStyle(.borderlessButton)

            // 视图模式切换
            Menu {
                ForEach(NoteViewMode.allCases, id: \.self) { mode in
                    Button {
                        currentViewMode = mode
                    } label: {
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                            if currentViewMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: currentViewMode.icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(BuBuColors.mintGreen)
            }
            .menuStyle(.borderlessButton)

            // 添加按钮
            Button {
                showingAddNote = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(BuBuColors.skyBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BuBuColors.creamWhite)
        .sheet(isPresented: $showingAddNote) {
            NoteDTOEditorView(mode: .add) { note in
                viewModel.createNote(note)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("导入结果", isPresented: $showingImportResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importResult?.summary ?? "")
        }
    }

    // MARK: - 导入导出方法

    private func exportNotes() {
        guard let fileURL = viewModel.exportToFile() else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = fileURL.lastPathComponent
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            if response == .OK, let destURL = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: destURL)
                } catch {
                    // 导出失败，静默处理
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                importResult = viewModel.importFromFile(url)
                showingImportResult = true
            }
        case .failure(let error):
            importResult = ImportResult(
                success: false,
                totalCount: 0,
                importedCount: 0,
                skippedCount: 0,
                updatedCount: 0,
                errorMessage: error.localizedDescription
            )
            showingImportResult = true
        }
    }

    // MARK: - 便签列表

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredNotes) { note in
                    NoteDTORowView(note: note)
                        .contextMenu {
                            noteContextMenu(for: note)
                        }
                }
            }
            .padding(14)
        }
    }

    // MARK: - 卡片视图

    private var notesCardView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(filteredNotes) { note in
                    NoteCardView(note: note)
                        .contextMenu {
                            noteContextMenu(for: note)
                        }
                }
            }
            .padding(12)
        }
    }

    // MARK: - 看板视图

    private var notesKanbanView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                // 待办列
                KanbanColumn(
                    title: "待办",
                    icon: "circle",
                    color: BuBuColors.chocolateBrown.opacity(0.5),
                    notes: filteredNotes.filter { $0.status == .todo },
                    onNoteAction: noteContextMenu
                )

                // 进行中列
                KanbanColumn(
                    title: "进行中",
                    icon: "circle.lefthalf.filled",
                    color: BuBuColors.skyBlue,
                    notes: filteredNotes.filter { $0.status == .inProgress },
                    onNoteAction: noteContextMenu
                )

                // 已完成列
                KanbanColumn(
                    title: "已完成",
                    icon: "checkmark.circle.fill",
                    color: BuBuColors.mintGreen,
                    notes: filteredNotes.filter { $0.status == .completed },
                    onNoteAction: noteContextMenu
                )
            }
            .padding(16)
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(BuBuColors.skyBlue.opacity(0.6))

            Text(searchText.isEmpty ? "暂无便签" : "未找到匹配的便签")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

            if searchText.isEmpty {
                Button("创建第一个便签") {
                    showingAddNote = true
                }
                .font(BuBuFonts.body)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(BuBuColors.skyBlue)
                )
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func noteContextMenu(for note: NoteDTO) -> some View {
        Button {
            viewModel.toggleStatus(note)
        } label: {
            Label(
                note.status == .completed ? "标记为未完成" : "标记为完成",
                systemImage: note.status == .completed ? "circle" : "checkmark.circle"
            )
        }

        Divider()

        Menu("优先级") {
            ForEach(NotePriority.allCases, id: \.self) { priority in
                Button {
                    var updatedNote = note
                    updatedNote.priority = priority
                    viewModel.updateNote(updatedNote)
                } label: {
                    HStack {
                        Text(priority.title)
                        if note.priority == priority {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            viewModel.deleteNote(note)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - 筛选逻辑

    private var filteredNotes: [NoteDTO] {
        var notes = viewModel.notes

        // 按状态筛选
        switch selectedFilter {
        case .all:
            break
        case .active:
            notes = notes.filter { $0.status != .completed }
        case .completed:
            notes = notes.filter { $0.status == .completed }
        case .highPriority:
            notes = notes.filter { $0.priority == .high || $0.priority == .urgent }
        }

        // 按搜索词筛选
        if !searchText.isEmpty {
            notes = notes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        return notes
    }
}

// MARK: - 筛选类型

enum NoteListFilter: CaseIterable {
    case all
    case active
    case completed
    case highPriority

    var title: String {
        switch self {
        case .all: return "全部"
        case .active: return "进行中"
        case .completed: return "已完成"
        case .highPriority: return "高优先级"
        }
    }
}

// MARK: - 便签行视图

struct NoteDTORowView: View {
    let note: NoteDTO
    @EnvironmentObject var viewModel: NotesViewModel
    @State private var showingEditor = false

    var body: some View {
        HStack(spacing: 14) {
            // 完成状态按钮
            Button {
                viewModel.toggleStatus(note)
            } label: {
                Image(systemName: note.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(note.status == .completed ? BuBuColors.mintGreen : BuBuColors.chocolateBrown.opacity(0.35))
            }
            .buttonStyle(.plain)

            // 优先级指示器
            Circle()
                .fill(note.priority.bubuColor)
                .frame(width: 9, height: 9)

            // 内容
            VStack(alignment: .leading, spacing: 5) {
                Text(note.title)
                    .font(BuBuFonts.body)
                    .strikethrough(note.status == .completed)
                    .foregroundColor(note.status == .completed ? BuBuColors.chocolateBrown.opacity(0.5) : BuBuColors.chocolateBrown)

                if !note.content.isEmpty {
                    Text(note.content)
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                        .lineLimit(2)
                }

                // 标签和提醒
                HStack(spacing: 8) {
                    if !note.tags.isEmpty {
                        ForEach(note.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(BuBuFonts.tiny)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(BuBuColors.skyBlue.opacity(0.15))
                                .foregroundColor(BuBuColors.skyBlue)
                                .cornerRadius(7)
                        }
                    }

                    if note.reminderDate != nil {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11))
                            .foregroundColor(BuBuColors.coralPink)
                    }
                }
            }

            Spacer()

            // 编辑按钮
            Button {
                showingEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15))
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .sheet(isPresented: $showingEditor) {
            NoteDTOEditorView(mode: .edit(note)) { updatedNote in
                viewModel.updateNote(updatedNote)
            }
        }
    }
}

// MARK: - 预览

#Preview {
    NotesView()
        .environmentObject(NotesViewModel())
        .frame(width: 400, height: 500)
}

// MARK: - 卡片视图组件

struct NoteCardView: View {
    let note: NoteDTO
    @EnvironmentObject var viewModel: NotesViewModel
    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部：优先级和状态
            HStack {
                Circle()
                    .fill(note.priority.bubuColor)
                    .frame(width: 8, height: 8)

                Spacer()

                Button {
                    viewModel.toggleStatus(note)
                } label: {
                    Image(systemName: note.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(note.status == .completed ? BuBuColors.mintGreen : BuBuColors.chocolateBrown.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            // 标题
            Text(note.title)
                .font(BuBuFonts.headline)
                .foregroundColor(note.status == .completed ? BuBuColors.chocolateBrown.opacity(0.5) : BuBuColors.chocolateBrown)
                .strikethrough(note.status == .completed)
                .lineLimit(2)

            // 内容预览
            if !note.content.isEmpty {
                Text(note.content)
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            // 底部：标签和提醒
            HStack(spacing: 6) {
                if !note.tags.isEmpty {
                    Text(note.tags.first ?? "")
                        .font(BuBuFonts.tiny)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BuBuColors.skyBlue.opacity(0.15))
                        .foregroundColor(BuBuColors.skyBlue)
                        .cornerRadius(4)

                    if note.tags.count > 1 {
                        Text("+\(note.tags.count - 1)")
                            .font(BuBuFonts.tiny)
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                    }
                }

                Spacer()

                if note.reminderDate != nil {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10))
                        .foregroundColor(BuBuColors.coralPink)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .onTapGesture {
            showingEditor = true
        }
        .sheet(isPresented: $showingEditor) {
            NoteDTOEditorView(mode: .edit(note)) { updatedNote in
                viewModel.updateNote(updatedNote)
            }
        }
    }
}

// MARK: - 看板列组件

struct KanbanColumn<MenuContent: View>: View {
    let title: String
    let icon: String
    let color: Color
    let notes: [NoteDTO]
    @ViewBuilder let onNoteAction: (NoteDTO) -> MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 列标题
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(BuBuFonts.headline)
                    .foregroundColor(BuBuColors.chocolateBrown)

                Spacer()

                Text("\(notes.count)")
                    .font(BuBuFonts.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(color)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                    .fill(color.opacity(0.1))
            )

            // 便签列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(notes) { note in
                        KanbanNoteCard(note: note)
                            .contextMenu {
                                onNoteAction(note)
                            }
                    }
                }
            }
        }
        .frame(width: 220)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(BuBuColors.creamWhite)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - 看板便签卡片

struct KanbanNoteCard: View {
    let note: NoteDTO
    @EnvironmentObject var viewModel: NotesViewModel
    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 优先级指示条
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(note.priority.bubuColor)
                    .frame(width: 4, height: 16)

                Text(note.title)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
                    .lineLimit(2)
            }

            if !note.content.isEmpty {
                Text(note.content)
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                    .lineLimit(2)
            }

            // 标签
            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(BuBuColors.skyBlue.opacity(0.15))
                            .foregroundColor(BuBuColors.skyBlue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .onTapGesture {
            showingEditor = true
        }
        .sheet(isPresented: $showingEditor) {
            NoteDTOEditorView(mode: .edit(note)) { updatedNote in
                viewModel.updateNote(updatedNote)
            }
        }
    }
}
