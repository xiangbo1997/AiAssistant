//
//  LanguageDetector.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  语言定义与检测 - 使用系统 NaturalLanguage 框架做本地语言识别，
//  替代手写的字符占比启发式；零网络、零成本
//

import Foundation
import NaturalLanguage

// MARK: - 语言枚举

/// 应用支持的翻译语言（原定义在 TranslationView 中，迁出以供翻译引擎/检测器共用）
enum Language: String, CaseIterable {
    case auto = "auto"
    case chinese = "zh"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    /// 界面显示名
    var displayName: String {
        switch self {
        case .auto: return "自动检测"
        case .chinese: return "中文"
        case .english: return "英语"
        case .japanese: return "日语"
        case .korean: return "韩语"
        case .french: return "法语"
        case .german: return "德语"
        case .spanish: return "西班牙语"
        case .russian: return "俄语"
        }
    }

    /// 提示词中使用的语言名（与界面文案解耦）
    var promptName: String {
        switch self {
        case .auto: return "自动检测"
        case .chinese: return "简体中文"
        default: return displayName
        }
    }

    /// TTS 朗读使用的 BCP-47 语音代码
    var speechCode: String {
        switch self {
        case .auto, .chinese: return "zh-CN"
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .spanish: return "es-ES"
        case .russian: return "ru-RU"
        }
    }
}

// MARK: - 语言检测器

enum LanguageDetector {
    /// 检测文本的主导语言；无法识别或不在支持列表时返回 nil。
    /// 只取前 500 字符，足够判定且避免长文本的无谓开销
    static func detect(_ text: String) -> Language? {
        let sample = String(text.prefix(500))
        guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage else { return nil }

        switch dominant {
        case .simplifiedChinese, .traditionalChinese: return .chinese
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        case .russian: return .russian
        default: return nil
        }
    }

    /// 快速翻译的目标语言策略：中文→英语，其他（含无法识别）→中文
    static func quickTargetLanguage(for text: String) -> Language {
        detect(text) == .chinese ? .english : .chinese
    }

    /// 根据文本内容选择 TTS 语音代码，识别失败时回落中文
    static func speechLanguageCode(for text: String) -> String {
        (detect(text) ?? .chinese).speechCode
    }

    /// 是否适合词典模式：单个英文单词（可含连字符/撇号）或 1~4 字的中文词
    static func isDictionaryQuery(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.range(of: "^[A-Za-z][A-Za-z'-]{0,29}$", options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: "^\\p{Han}{1,4}$", options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
