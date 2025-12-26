//
//  SearchHistoryService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-22.
//  搜索历史服务 - 管理搜索记录的持久化
//

import Foundation
import CoreData

class SearchHistoryService: ObservableObject {
    // 单例
    static let shared = SearchHistoryService()

    // 搜索历史
    @Published var searchHistory: [SearchRecordDTO] = []

    // Core Data 上下文
    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    // 最大历史记录数
    private let maxHistoryCount = 50

    private init() {
        fetchHistory()
    }

    // MARK: - CRUD 操作

    /// 获取搜索历史
    func fetchHistory() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SearchRecordEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = maxHistoryCount

        do {
            let results = try viewContext.fetch(request)
            searchHistory = results.map { entity in
                SearchRecordDTO(
                    id: entity.value(forKey: "id") as? UUID ?? UUID(),
                    query: entity.value(forKey: "query") as? String ?? "",
                    type: SearchType(rawValue: entity.value(forKey: "type") as? Int16 ?? 0) ?? .general,
                    result: entity.value(forKey: "result") as? String ?? "",
                    provider: entity.value(forKey: "provider") as? String ?? "",
                    createdAt: entity.value(forKey: "createdAt") as? Date ?? Date()
                )
            }
        } catch {
            // 获取失败，静默处理
        }
    }

    /// 添加搜索记录
    func addRecord(query: String, type: SearchType = .general, result: String, provider: String) {
        // 检查是否已存在相同查询
        if let existingIndex = searchHistory.firstIndex(where: { $0.query == query }) {
            // 更新已存在的记录
            let existingRecord = searchHistory[existingIndex]
            updateRecord(existingRecord, result: result, provider: provider)
            return
        }

        let entity = NSEntityDescription.insertNewObject(forEntityName: "SearchRecordEntity", into: viewContext)

        let id = UUID()
        entity.setValue(id, forKey: "id")
        entity.setValue(query, forKey: "query")
        entity.setValue(type.rawValue, forKey: "type")
        entity.setValue(result, forKey: "result")
        entity.setValue(provider, forKey: "provider")
        entity.setValue(Date(), forKey: "createdAt")

        saveContext()

        // 清理超出限制的旧记录
        cleanupOldRecords()

        fetchHistory()
    }

    /// 更新搜索记录
    private func updateRecord(_ record: SearchRecordDTO, result: String, provider: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SearchRecordEntity")
        request.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)

        do {
            let results = try viewContext.fetch(request)
            if let entity = results.first {
                entity.setValue(result, forKey: "result")
                entity.setValue(provider, forKey: "provider")
                entity.setValue(Date(), forKey: "createdAt")
                saveContext()
                fetchHistory()
            }
        } catch {
            // 更新失败，静默处理
        }
    }

    /// 删除搜索记录
    func deleteRecord(_ record: SearchRecordDTO) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SearchRecordEntity")
        request.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)

        do {
            let results = try viewContext.fetch(request)
            if let entity = results.first {
                viewContext.delete(entity)
                saveContext()
                fetchHistory()
            }
        } catch {
            // 删除失败，静默处理
        }
    }

    /// 清除所有搜索历史
    func clearAllHistory() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "SearchRecordEntity")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)

        do {
            try viewContext.execute(deleteRequest)
            saveContext()
            searchHistory = []
        } catch {
            // 清除失败，静默处理
        }
    }

    /// 获取最近的查询字符串列表
    func getRecentQueries(limit: Int = 10) -> [String] {
        return Array(searchHistory.prefix(limit).map { $0.query })
    }

    // MARK: - 辅助方法

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            // 保存失败，静默处理
        }
    }

    private func cleanupOldRecords() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SearchRecordEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let results = try viewContext.fetch(request)
            if results.count > maxHistoryCount {
                // 删除超出限制的旧记录
                for i in maxHistoryCount..<results.count {
                    viewContext.delete(results[i])
                }
                saveContext()
            }
        } catch {
            // 清理失败，静默处理
        }
    }
}

// MARK: - 搜索记录 DTO

struct SearchRecordDTO: Identifiable, Codable {
    let id: UUID
    let query: String
    let type: SearchType
    let result: String
    let provider: String
    let createdAt: Date
}

// MARK: - 搜索类型

enum SearchType: Int16, Codable {
    case general = 0    // 通用搜索
    case term = 1       // 术语解释
    case code = 2       // 代码解析
    case summary = 3    // 总结归纳
}
