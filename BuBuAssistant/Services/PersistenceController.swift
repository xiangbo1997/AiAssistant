//
//  PersistenceController.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  Core Data 持久化控制器
//

import CoreData

struct PersistenceController {
    // 单例
    static let shared = PersistenceController()

    // 预览用实例
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // 创建示例数据
        for i in 0..<5 {
            let note = NSEntityDescription.insertNewObject(forEntityName: "NoteEntity", into: viewContext)
            note.setValue(UUID(), forKey: "id")
            note.setValue("示例便签 \(i + 1)", forKey: "title")
            note.setValue("这是便签的内容描述", forKey: "content")
            note.setValue(Int16(i % 3), forKey: "status")
            note.setValue(Int16(i % 4), forKey: "priority")
            note.setValue("[]", forKey: "tags")
            note.setValue(Int32(i), forKey: "sortOrder")
            note.setValue(Date(), forKey: "createdAt")
            note.setValue(Date(), forKey: "updatedAt")
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return result
    }()

    // Core Data 容器
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // 创建托管对象模型
        let model = Self.createManagedObjectModel()
        container = NSPersistentContainer(name: "BuBuAssistant", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                // 生产环境应该更优雅地处理错误
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - 创建数据模型

    private static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // NoteEntity
        let noteEntity = NSEntityDescription()
        noteEntity.name = "NoteEntity"
        noteEntity.managedObjectClassName = "NoteEntity"

        var noteProperties: [NSAttributeDescription] = []

        let noteId = NSAttributeDescription()
        noteId.name = "id"
        noteId.attributeType = .UUIDAttributeType
        noteId.isOptional = false
        noteProperties.append(noteId)

        let noteTitle = NSAttributeDescription()
        noteTitle.name = "title"
        noteTitle.attributeType = .stringAttributeType
        noteTitle.isOptional = false
        noteProperties.append(noteTitle)

        let noteContent = NSAttributeDescription()
        noteContent.name = "content"
        noteContent.attributeType = .stringAttributeType
        noteContent.isOptional = true
        noteProperties.append(noteContent)

        let noteStatus = NSAttributeDescription()
        noteStatus.name = "status"
        noteStatus.attributeType = .integer16AttributeType
        noteStatus.defaultValue = 0
        noteProperties.append(noteStatus)

        let notePriority = NSAttributeDescription()
        notePriority.name = "priority"
        notePriority.attributeType = .integer16AttributeType
        notePriority.defaultValue = 1
        noteProperties.append(notePriority)

        let noteTags = NSAttributeDescription()
        noteTags.name = "tags"
        noteTags.attributeType = .stringAttributeType
        noteTags.isOptional = true
        noteProperties.append(noteTags)

        let noteReminderDate = NSAttributeDescription()
        noteReminderDate.name = "reminderDate"
        noteReminderDate.attributeType = .dateAttributeType
        noteReminderDate.isOptional = true
        noteProperties.append(noteReminderDate)

        let noteRepeatType = NSAttributeDescription()
        noteRepeatType.name = "repeatType"
        noteRepeatType.attributeType = .integer16AttributeType
        noteRepeatType.defaultValue = 0
        noteProperties.append(noteRepeatType)

        let noteSortOrder = NSAttributeDescription()
        noteSortOrder.name = "sortOrder"
        noteSortOrder.attributeType = .integer32AttributeType
        noteSortOrder.defaultValue = 0
        noteProperties.append(noteSortOrder)

        let noteCreatedAt = NSAttributeDescription()
        noteCreatedAt.name = "createdAt"
        noteCreatedAt.attributeType = .dateAttributeType
        noteCreatedAt.isOptional = false
        noteProperties.append(noteCreatedAt)

        let noteUpdatedAt = NSAttributeDescription()
        noteUpdatedAt.name = "updatedAt"
        noteUpdatedAt.attributeType = .dateAttributeType
        noteUpdatedAt.isOptional = false
        noteProperties.append(noteUpdatedAt)

        noteEntity.properties = noteProperties

        // SearchRecordEntity
        let searchEntity = NSEntityDescription()
        searchEntity.name = "SearchRecordEntity"
        searchEntity.managedObjectClassName = "SearchRecordEntity"

        var searchProperties: [NSAttributeDescription] = []

        let searchId = NSAttributeDescription()
        searchId.name = "id"
        searchId.attributeType = .UUIDAttributeType
        searchId.isOptional = false
        searchProperties.append(searchId)

        let searchQuery = NSAttributeDescription()
        searchQuery.name = "query"
        searchQuery.attributeType = .stringAttributeType
        searchQuery.isOptional = false
        searchProperties.append(searchQuery)

        let searchType = NSAttributeDescription()
        searchType.name = "type"
        searchType.attributeType = .integer16AttributeType
        searchType.defaultValue = 0
        searchProperties.append(searchType)

        let searchResult = NSAttributeDescription()
        searchResult.name = "result"
        searchResult.attributeType = .stringAttributeType
        searchResult.isOptional = true
        searchProperties.append(searchResult)

        let searchProvider = NSAttributeDescription()
        searchProvider.name = "provider"
        searchProvider.attributeType = .stringAttributeType
        searchProvider.isOptional = true
        searchProperties.append(searchProvider)

        let searchCreatedAt = NSAttributeDescription()
        searchCreatedAt.name = "createdAt"
        searchCreatedAt.attributeType = .dateAttributeType
        searchCreatedAt.isOptional = false
        searchProperties.append(searchCreatedAt)

        searchEntity.properties = searchProperties

        // TranslationRecordEntity
        let translationEntity = NSEntityDescription()
        translationEntity.name = "TranslationRecordEntity"
        translationEntity.managedObjectClassName = "TranslationRecordEntity"

        var translationProperties: [NSAttributeDescription] = []

        let translationId = NSAttributeDescription()
        translationId.name = "id"
        translationId.attributeType = .UUIDAttributeType
        translationId.isOptional = false
        translationProperties.append(translationId)

        let sourceText = NSAttributeDescription()
        sourceText.name = "sourceText"
        sourceText.attributeType = .stringAttributeType
        sourceText.isOptional = false
        translationProperties.append(sourceText)

        let targetText = NSAttributeDescription()
        targetText.name = "targetText"
        targetText.attributeType = .stringAttributeType
        targetText.isOptional = false
        translationProperties.append(targetText)

        let sourceLanguage = NSAttributeDescription()
        sourceLanguage.name = "sourceLanguage"
        sourceLanguage.attributeType = .stringAttributeType
        sourceLanguage.isOptional = false
        translationProperties.append(sourceLanguage)

        let targetLanguage = NSAttributeDescription()
        targetLanguage.name = "targetLanguage"
        targetLanguage.attributeType = .stringAttributeType
        targetLanguage.isOptional = false
        translationProperties.append(targetLanguage)

        let isFavorite = NSAttributeDescription()
        isFavorite.name = "isFavorite"
        isFavorite.attributeType = .booleanAttributeType
        isFavorite.defaultValue = false
        translationProperties.append(isFavorite)

        let translationCreatedAt = NSAttributeDescription()
        translationCreatedAt.name = "createdAt"
        translationCreatedAt.attributeType = .dateAttributeType
        translationCreatedAt.isOptional = false
        translationProperties.append(translationCreatedAt)

        translationEntity.properties = translationProperties

        model.entities = [noteEntity, searchEntity, translationEntity]

        return model
    }

    // MARK: - 数据操作

    /// 保存上下文
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // 保存失败，静默处理
            }
        }
    }

    /// 清除所有数据
    func clearAllData() {
        let entities = ["NoteEntity", "SearchRecordEntity", "TranslationRecordEntity"]
        let context = container.viewContext

        for entityName in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

            do {
                try context.execute(deleteRequest)
            } catch {
                // 清除失败，静默处理
            }
        }

        save()
    }
}
