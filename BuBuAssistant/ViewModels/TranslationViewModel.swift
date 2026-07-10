//
//  TranslationViewModel.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  面板翻译视图模型 - 流式翻译、请求取消、历史缓存命中与检测语言回显
//

import Combine
import Foundation

@MainActor
final class TranslationViewModel: ObservableObject {
    /// 自动翻译开关的 UserDefaults 键（TranslationView 的开关与此读写同一键）
    static let autoTranslateKey = "autoTranslateEnabled"
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var sourceLanguage: Language = .auto
    @Published var targetLanguage: Language = .english
    @Published var isTranslating = false
    @Published var errorMessage: String?
    /// 源语言选「自动检测」时的识别结果回显
    @Published var detectedLanguage: Language?

    private var translationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 防抖自动翻译：停止输入 0.8 秒后自动触发（设置开关，默认关闭）
        $sourceText
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self,
                      UserDefaults.standard.bool(forKey: Self.autoTranslateKey),
                      !text.isEmpty else { return }
                self.translate()
            }
            .store(in: &cancellables)
    }

    // MARK: - 翻译

    func translate() {
        guard !sourceText.isEmpty else { return }

        // 相同原文正在翻译中则跳过，防止 onAppear 与通知双触发
        if isTranslating, sourceText == translatingText { return }

        translationTask?.cancel()
        errorMessage = nil
        detectedLanguage = sourceLanguage == .auto ? LanguageDetector.detect(sourceText) : nil
        // 记录本次请求文本（含缓存命中路径），供重复触发去重，避免残留旧值
        translatingText = sourceText

        // 历史缓存命中：零 API 调用直接出结果
        if let cached = TranslationEngine.shared.cachedTranslation(text: sourceText, target: targetLanguage) {
            translatedText = cached
            isTranslating = false
            return
        }

        let text = sourceText
        let source = sourceLanguage
        let target = targetLanguage
        isTranslating = true
        translatedText = ""

        translationTask = Task {
            do {
                let stream = try TranslationEngine.shared.stream(text: text, source: source, target: target)

                // 节流刷新：chunk 先进缓冲，每 80ms 批量发布一次，
                // 避免逐 token 更新 @Published 造成的高频重渲染
                var buffer = ""
                var lastFlush = ContinuousClock.now
                for try await chunk in stream {
                    try Task.checkCancellation()
                    buffer += chunk
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(80) {
                        translatedText += buffer
                        buffer = ""
                        lastFlush = now
                    }
                }
                try Task.checkCancellation()
                translatedText += buffer
                isTranslating = false

                TranslationEngine.shared.saveRecord(
                    sourceText: text,
                    targetText: translatedText,
                    source: source,
                    target: target
                )
            } catch is CancellationError {
                // 新翻译顶替了旧任务，静默结束
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "翻译失败：\(error.localizedDescription)"
                isTranslating = false
            }
        }
    }

    /// 正在翻译的原文快照（用于去重判断）
    private var translatingText = ""

    /// 接收外部文字（选中文字通知/初始文字）并触发翻译
    func translateExternalText(_ text: String) {
        guard !text.isEmpty else { return }
        if isTranslating, text == translatingText { return }
        sourceText = text
        translate()
    }

    // MARK: - 操作

    func swapLanguages() {
        guard sourceLanguage != .auto else { return }

        let tempLang = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = tempLang

        let tempText = sourceText
        sourceText = translatedText
        translatedText = tempText
    }

    func clear() {
        translationTask?.cancel()
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        detectedLanguage = nil
        isTranslating = false
    }

    /// 应用历史记录
    func applyRecord(_ record: TranslationRecordDTO) {
        translationTask?.cancel()
        isTranslating = false
        errorMessage = nil
        sourceText = record.sourceText
        translatedText = record.targetText
    }

    /// 朗读文本，按内容自动选择语音
    func speak(_ text: String) {
        SpeechService.shared.speak(text)
    }
}
