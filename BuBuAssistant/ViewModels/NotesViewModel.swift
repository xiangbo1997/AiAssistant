//
//  NotesViewModel.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  便签视图模型 - 管理便签的 CRUD 和筛选排序
//

import SwiftUI
import Combine
import CoreData

class NotesViewModel: ObservableObject {
    // MARK: - 便签列表

    @Published var notes: [NoteDTO] = []
    @Published var filteredNotes: [NoteDTO] = []

    // MARK: - 筛选和排序

    @Published var filter = NoteFilter()
    @Published var sortOption: NoteSortOption = .createdAt
    @Published var sortAscending: Bool = false

    // MARK: - 视图状态

    @Published var viewMode: NoteViewMode = .list
    @Published var selectedNote: NoteDTO?
    @Published var isEditing: Bool = false

    // MARK: - 标签管理

    @Published var allTags: [String] = []

    // MARK: - Core Data

    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    // MARK: - 订阅

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    init() {
        setupBindings()
        fetchNotes()
    }

    // MARK: - 数据绑定

    private func setupBindings() {
        // 监听筛选条件变化
        Publishers.CombineLatest4(
            $notes,
            $filter,
            $sortOption,
            $sortAscending
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] notes, filter, sortOption, ascending in
            self?.applyFilterAndSort(notes: notes, filter: filter, sortOption: sortOption, ascending: ascending)
        }
        .store(in: &cancellables)
    }

    // MARK: - 筛选和排序

    private func applyFilterAndSort(notes: [NoteDTO], filter: NoteFilter, sortOption: NoteSortOption, ascending: Bool) {
        var result = notes

        // 应用筛选
        if !filter.searchText.isEmpty {
            let searchText = filter.searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(searchText) ||
                $0.content.lowercased().contains(searchText)
            }
        }

        if let status = filter.status {
            result = result.filter { $0.status == status }
        }

        if let priority = filter.priority {
            result = result.filter { $0.priority == priority }
        }

        if !filter.tags.isEmpty {
            result = result.filter { note in
                !Set(note.tags).isDisjoint(with: Set(filter.tags))
            }
        }

        // 应用排序
        result = sortNotes(result, by: sortOption, ascending: ascending)

        filteredNotes = result
    }

    private func sortNotes(_ notes: [NoteDTO], by option: NoteSortOption, ascending: Bool) -> [NoteDTO] {
        let sorted: [NoteDTO]

        switch option {
        case .createdAt:
            sorted = notes.sorted { ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        case .updatedAt:
            sorted = notes.sorted { ascending ? $0.updatedAt < $1.updatedAt : $0.updatedAt > $1.updatedAt }
        case .priority:
            sorted = notes.sorted { ascending ? $0.priority.rawValue < $1.priority.rawValue : $0.priority.rawValue > $1.priority.rawValue }
        case .status:
            sorted = notes.sorted { ascending ? $0.status.rawValue < $1.status.rawValue : $0.status.rawValue > $1.status.rawValue }
        case .manual:
            sorted = notes.sorted { $0.sortOrder < $1.sortOrder }
        }

        return sorted
    }

    // MARK: - CRUD 操作

    /// 获取所有便签
    func fetchNotes() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "NoteEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let results = try viewContext.fetch(request)
            notes = results.map { entity in
                NoteDTO(
                    id: entity.value(forKey: "id") as? UUID ?? UUID(),
                    title: entity.value(forKey: "title") as? String ?? "",
                    content: entity.value(forKey: "content") as? String ?? "",
                    status: NoteStatus(rawValue: entity.value(forKey: "status") as? Int16 ?? 0) ?? .todo,
                    priority: NotePriority(rawValue: entity.value(forKey: "priority") as? Int16 ?? 1) ?? .medium,
                    tags: parseTagsJSON(entity.value(forKey: "tags") as? String),
                    reminderDate: entity.value(forKey: "reminderDate") as? Date,
                    repeatType: RepeatType(rawValue: entity.value(forKey: "repeatType") as? Int16 ?? 0) ?? .none,
                    sortOrder: entity.value(forKey: "sortOrder") as? Int32 ?? 0
                )
            }
            updateAllTags()
        } catch {
            // 获取失败，静默处理
        }
    }

    /// 创建便签
    func createNote(_ note: NoteDTO) {
        let entity = NSEntityDescription.insertNewObject(forEntityName: "NoteEntity", into: viewContext)

        entity.setValue(note.id, forKey: "id")
        entity.setValue(note.title, forKey: "title")
        entity.setValue(note.content, forKey: "content")
        entity.setValue(note.status.rawValue, forKey: "status")
        entity.setValue(note.priority.rawValue, forKey: "priority")
        entity.setValue(tagsToJSON(note.tags), forKey: "tags")
        entity.setValue(note.reminderDate, forKey: "reminderDate")
        entity.setValue(note.repeatType.rawValue, forKey: "repeatType")
        entity.setValue(note.sortOrder, forKey: "sortOrder")
        entity.setValue(Date(), forKey: "createdAt")
        entity.setValue(Date(), forKey: "updatedAt")

        saveContext()
        fetchNotes()

        // 设置提醒
        if let reminderDate = note.reminderDate {
            scheduleReminder(for: note, at: reminderDate)
        }
    }

    /// 更新便签
    func updateNote(_ note: NoteDTO) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "NoteEntity")
        request.predicate = NSPredicate(format: "id == %@", note.id as CVarArg)

        do {
            let results = try viewContext.fetch(request)
            if let entity = results.first {
                entity.setValue(note.title, forKey: "title")
                entity.setValue(note.content, forKey: "content")
                entity.setValue(note.status.rawValue, forKey: "status")
                entity.setValue(note.priority.rawValue, forKey: "priority")
                entity.setValue(tagsToJSON(note.tags), forKey: "tags")
                entity.setValue(note.reminderDate, forKey: "reminderDate")
                entity.setValue(note.repeatType.rawValue, forKey: "repeatType")
                entity.setValue(note.sortOrder, forKey: "sortOrder")
                entity.setValue(Date(), forKey: "updatedAt")

                saveContext()
                fetchNotes()

                // 更新提醒
                cancelReminder(for: note)
                if let reminderDate = note.reminderDate {
                    scheduleReminder(for: note, at: reminderDate)
                }
            }
        } catch {
            // 更新失败，静默处理
        }
    }

    /// 删除便签
    func deleteNote(_ note: NoteDTO) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "NoteEntity")
        request.predicate = NSPredicate(format: "id == %@", note.id as CVarArg)

        do {
            let results = try viewContext.fetch(request)
            if let entity = results.first {
                viewContext.delete(entity)
                saveContext()
                fetchNotes()

                // 取消提醒
                cancelReminder(for: note)
            }
        } catch {
            // 删除失败，静默处理
        }
    }

    /// 批量删除
    func deleteNotes(_ notes: [NoteDTO]) {
        for note in notes {
            deleteNote(note)
        }
    }

    /// 切换状态
    func toggleStatus(_ note: NoteDTO) {
        var updatedNote = note
        switch note.status {
        case .todo:
            updatedNote.status = .inProgress
        case .inProgress:
            updatedNote.status = .completed
        case .completed:
            updatedNote.status = .todo
        }
        updateNote(updatedNote)
    }

    /// 快速完成
    func completeNote(_ note: NoteDTO) {
        var updatedNote = note
        updatedNote.status = .completed
        updateNote(updatedNote)
    }

    // MARK: - 标签管理

    private func updateAllTags() {
        var tags = Set<String>()
        for note in notes {
            tags.formUnion(note.tags)
        }
        allTags = Array(tags).sorted()
    }

    // MARK: - 提醒管理

    private func scheduleReminder(for note: NoteDTO, at date: Date) {
        NotificationService.shared.scheduleReminder(
            id: note.id.uuidString,
            title: note.title,
            body: note.content.isEmpty ? "便签提醒" : note.content,
            date: date,
            repeatType: note.repeatType
        )
    }

    private func cancelReminder(for note: NoteDTO) {
        NotificationService.shared.cancelReminder(id: note.id.uuidString)
    }

    // MARK: - 辅助方法

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            // 保存失败，静默处理
        }
    }

    private func parseTagsJSON(_ json: String?) -> [String] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return tags
    }

    private func tagsToJSON(_ tags: [String]) -> String {
        guard let data = try? JSONEncoder().encode(tags),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - 便捷方法

    /// 按状态分组（用于看板视图）
    var notesByStatus: [NoteStatus: [NoteDTO]] {
        Dictionary(grouping: filteredNotes, by: { $0.status })
    }

    /// 今日待办
    var todayNotes: [NoteDTO] {
        let calendar = Calendar.current
        return filteredNotes.filter { note in
            guard let reminderDate = note.reminderDate else { return false }
            return calendar.isDateInToday(reminderDate)
        }
    }

    /// 过期未完成
    var overdueNotes: [NoteDTO] {
        let now = Date()
        return filteredNotes.filter { note in
            guard let reminderDate = note.reminderDate else { return false }
            return reminderDate < now && note.status != .completed
        }
    }

    // MARK: - 数据导入导出

    /// 导出便签数据为 JSON
    func exportNotes() -> Data? {
        let exportData = NotesExportData(
            version: "1.0",
            exportDate: Date(),
            notes: notes
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(exportData)
        } catch {
            return nil
        }
    }

    /// 导出便签到文件
    func exportToFile() -> URL? {
        guard let data = exportNotes() else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "BuBuNotes_\(dateFormatter.string(from: Date())).json"

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    /// 从 JSON 数据导入便签
    func importNotes(from data: Data, mergeStrategy: ImportMergeStrategy = .skipExisting) -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let importData = try decoder.decode(NotesExportData.self, from: data)

            var imported = 0
            var skipped = 0
            var updated = 0

            for note in importData.notes {
                let existingNote = notes.first { $0.id == note.id }

                switch mergeStrategy {
                case .skipExisting:
                    if existingNote == nil {
                        createNote(note)
                        imported += 1
                    } else {
                        skipped += 1
                    }

                case .overwriteExisting:
                    if existingNote != nil {
                        updateNote(note)
                        updated += 1
                    } else {
                        createNote(note)
                        imported += 1
                    }

                case .keepBoth:
                    if existingNote != nil {
                        // 创建新 ID 的副本
                        var newNote = note
                        newNote.id = UUID()
                        newNote.title = note.title + " (导入)"
                        createNote(newNote)
                        imported += 1
                    } else {
                        createNote(note)
                        imported += 1
                    }
                }
            }

            return ImportResult(
                success: true,
                totalCount: importData.notes.count,
                importedCount: imported,
                skippedCount: skipped,
                updatedCount: updated,
                errorMessage: nil
            )
        } catch {
            return ImportResult(
                success: false,
                totalCount: 0,
                importedCount: 0,
                skippedCount: 0,
                updatedCount: 0,
                errorMessage: "导入失败: \(error.localizedDescription)"
            )
        }
    }

    /// 从文件 URL 导入便签
    func importFromFile(_ url: URL, mergeStrategy: ImportMergeStrategy = .skipExisting) -> ImportResult {
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            return importNotes(from: data, mergeStrategy: mergeStrategy)
        } catch {
            return ImportResult(
                success: false,
                totalCount: 0,
                importedCount: 0,
                skippedCount: 0,
                updatedCount: 0,
                errorMessage: "读取文件失败: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - 导出数据结构

struct NotesExportData: Codable {
    let version: String
    let exportDate: Date
    let notes: [NoteDTO]
}

// MARK: - 导入合并策略

enum ImportMergeStrategy {
    case skipExisting      // 跳过已存在的便签
    case overwriteExisting // 覆盖已存在的便签
    case keepBoth          // 保留两者（重命名导入的）
}

// MARK: - 导入结果

struct ImportResult {
    let success: Bool
    let totalCount: Int
    let importedCount: Int
    let skippedCount: Int
    let updatedCount: Int
    let errorMessage: String?

    var summary: String {
        if success {
            var parts: [String] = []
            if importedCount > 0 { parts.append("导入 \(importedCount) 条") }
            if skippedCount > 0 { parts.append("跳过 \(skippedCount) 条") }
            if updatedCount > 0 { parts.append("更新 \(updatedCount) 条") }
            return parts.isEmpty ? "无需导入" : parts.joined(separator: "，")
        } else {
            return errorMessage ?? "导入失败"
        }
    }
}
