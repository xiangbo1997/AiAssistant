//
//  TranslationHistoryService.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-22.
//  翻译历史服务 - 管理翻译记录的持久化
//

import Foundation
import CoreData

class TranslationHistoryService: ObservableObject {
    // 单例
    static let shared = TranslationHistoryService()

    // 翻译历史
    @Published var translationHistory: [TranslationRecordDTO] = []

    // 收藏列表
    var favorites: [TranslationRecordDTO] {
        translationHistory.filter { $0.isFavorite }
    }

    // Core Data 上下文
    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    // 最大历史记录数
    private let maxHistoryCount = 100

    private init() {
        fetchHistory()
    }

    // MARK: - CRUD 操作

    /// 获取翻译历史
    func fetchHistory() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TranslationRecordEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = maxHistoryCount

        do {
            let results = try viewContext.fetch(request)
            translationHistory = results.map { entity in
                TranslationRecordDTO(
                    id: entity.value(forKey: "id") as? UUID ?? UUID(),
                    sourceText: entity.value(forKey: "sourceText") as? String ?? "",
                    targetText: entity.value(forKey: "targetText") as? String ?? "",
                    sourceLanguage: entity.value(forKey: "sourceLanguage") as? String ?? "",
                    targetLanguage: entity.value(forKey: "targetLanguage") as? String ?? "",
                    isFavorite: entity.value(forKey: "isFavorite") as? Bool ?? false,
                    createdAt: entity.value(forKey: "createdAt") as? Date ?? Date()
                )
            }
        } catch {
            // 获取失败，静默处理
        }
    }

    /// 添加翻译记录
    func addRecord(
        sourceText: String,
        targetText: String,
        sourceLanguage: String,
        targetLanguage: String
    ) {
        // 检查是否已存在相同的翻译
        if let existingIndex = translationHistory.firstIndex(where: {
            $0.sourceText == sourceText &&
            $0.sourceLanguage == sourceLanguage &&
            $0.targetLanguage == targetLanguage
        }) {
            // 更新已存在的记录
            let existingRecord = translationHistory[existingIndex]
            updateRecord(existingRecord, targetText: targetText)
            return
        }

        let entity = NSEntityDescription.insertNewObject(forEntityName: "TranslationRecordEntity", into: viewContext)

        let id = UUID()
        entity.setValue(id, forKey: "id")
        entity.setValue(sourceText, forKey: "sourceText")
        entity.setValue(targetText, forKey: "targetText")
        entity.setValue(sourceLanguage, forKey: "sourceLanguage")
        entity.setValue(targetLanguage, forKey: "targetLanguage")
        entity.setValue(false, forKey: "isFavorite")
        entity.setValue(Date(), forKey: "createdAt")

        saveContext()

        // 清理超出限制的旧记录（保留收藏）
        cleanupOldRecords()

        fetchHistory()
    }

    /// 更新翻译记录
    private func updateRecord(_ record: TranslationRecordDTO, targetText: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TranslationRecordEntity")
        request.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)

        do {
            let results = try viewContext.fetch(request)
            if let entity = results.first {
                entity.setValue(targetText, forKey: "targetText")
                entity.setValue(Date(), forKey: "createdAt")
                saveContext()
                fetchHistory()
            }
        } catch {
            // 更新失败，静默处理
        }
    }

    /// 切换收藏状态
    func toggleFavorite(_ record: TranslationRecordDTO) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TranslationRecordEntity")
        request.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)

        do {
            let results = try viewContext.fetch(request)
            if let entity = results.first {
                let currentFavorite = entity.value(forKey: "isFavorite") as? Bool ?? false
                entity.setValue(!currentFavorite, forKey: "isFavorite")
                saveContext()
                fetchHistory()
            }
        } catch {
            // 切换失败，静默处理
        }
    }

    /// 删除翻译记录
    func deleteRecord(_ record: TranslationRecordDTO) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TranslationRecordEntity")
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

    /// 清除所有翻译历史（保留收藏）
    func clearHistory(keepFavorites: Bool = true) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TranslationRecordEntity")

        if keepFavorites {
            request.predicate = NSPredicate(format: "isFavorite == NO")
        }

        do {
            let results = try viewContext.fetch(request)
            for entity in results {
                viewContext.delete(entity)
            }
            saveContext()
            fetchHistory()
        } catch {
            // 清除失败，静默处理
        }
    }

    /// 清除所有数据（包括收藏）
    func clearAllHistory() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "TranslationRecordEntity")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)

        do {
            try viewContext.execute(deleteRequest)
            saveContext()
            translationHistory = []
        } catch {
            // 清除失败，静默处理
        }
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
        let request = NSFetchRequest<NSManagedObject>(entityName: "TranslationRecordEntity")
        // 只清理非收藏的记录
        request.predicate = NSPredicate(format: "isFavorite == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let results = try viewContext.fetch(request)
            // 保留最近的记录，删除超出限制的
            let nonFavoriteLimit = maxHistoryCount - favorites.count
            if results.count > nonFavoriteLimit {
                for i in nonFavoriteLimit..<results.count {
                    viewContext.delete(results[i])
                }
                saveContext()
            }
        } catch {
            // 清理失败，静默处理
        }
    }
}

// MARK: - 翻译记录 DTO

struct TranslationRecordDTO: Identifiable, Codable {
    let id: UUID
    let sourceText: String
    let targetText: String
    let sourceLanguage: String
    let targetLanguage: String
    var isFavorite: Bool
    let createdAt: Date
}
