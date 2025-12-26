//
//  TranslationView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  翻译视图 - 多语言翻译功能
//

import SwiftUI

struct TranslationView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @StateObject private var historyService = TranslationHistoryService.shared
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var sourceLanguage: Language = .auto
    @State private var targetLanguage: Language = .english
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var showHistory = false

    /// 用于接收外部传入的待翻译文字（如选中文字）
    var initialText: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 语言选择栏
            languageBar

            Divider()

            // 翻译区域
            HStack(spacing: 0) {
                // 源文本
                VStack(alignment: .leading, spacing: 10) {
                    Text("原文")
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

                    TextEditor(text: $sourceText)
                        .font(BuBuFonts.body)
                        .foregroundColor(BuBuColors.chocolateBrown)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                                .fill(Color.white)
                                .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
                        )

                    HStack {
                        Text("\(sourceText.count) 字符")
                            .font(BuBuFonts.tiny)
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))

                        Spacer()

                        Button {
                            sourceText = ""
                            translatedText = ""
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(sourceText.isEmpty)

                        Button {
                            if let content = NSPasteboard.general.string(forType: .string) {
                                sourceText = content
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.skyBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)

                // 交换按钮
                VStack {
                    Spacer()

                    Button {
                        swapLanguages()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(BuBuColors.skyBlue)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(BuBuColors.skyBlue.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(sourceLanguage == .auto)

                    Spacer()
                }

                // 译文
                VStack(alignment: .leading, spacing: 10) {
                    Text("译文")
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

                    if isTranslating {
                        VStack(spacing: 10) {
                            Spacer()
                            ProgressView()
                                .tint(BuBuColors.skyBlue)
                            Text("翻译中...")
                                .font(BuBuFonts.caption)
                                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                                .fill(Color.white)
                                .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
                        )
                    } else {
                        TextEditor(text: .constant(translatedText))
                            .font(BuBuFonts.body)
                            .foregroundColor(BuBuColors.chocolateBrown)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                                    .fill(Color.white)
                                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
                            )
                    }

                    HStack {
                        if let error = errorMessage {
                            Text(error)
                                .font(BuBuFonts.tiny)
                                .foregroundColor(BuBuColors.coralPink)
                        } else {
                            Text("\(translatedText.count) 字符")
                                .font(BuBuFonts.tiny)
                                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                        }

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(translatedText, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.skyBlue)
                        }
                        .buttonStyle(.plain)
                        .disabled(translatedText.isEmpty)

                        Button {
                            speakText(translatedText)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.lavender)
                        }
                        .buttonStyle(.plain)
                        .disabled(translatedText.isEmpty)
                    }
                }
                .padding(14)
            }

            Divider()

            // 翻译按钮
            HStack {
                Spacer()

                Button {
                    performTranslation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .medium))
                        Text("翻译")
                    }
                    .font(BuBuFonts.headline)
                    .foregroundColor(.white)
                    .frame(width: 150)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                            .fill(BuBuColors.skyBlue)
                            .shadow(color: BuBuColors.skyBlue.opacity(0.35), radius: 12, x: 0, y: 6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(sourceText.isEmpty || isTranslating)
                .opacity(sourceText.isEmpty || isTranslating ? 0.6 : 1)
                .keyboardShortcut(.return, modifiers: .command)

                Spacer()
            }
            .padding(18)
            .background(BuBuColors.creamWhite)
        }
        .onAppear {
            // 如果有初始文字，填充并自动翻译
            if let text = initialText, !text.isEmpty {
                sourceText = text
                performTranslation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .translateSelectedText)) { notification in
            // 接收选中文字翻译通知
            if let text = notification.object as? String, !text.isEmpty {
                sourceText = text
                translatedText = ""
                errorMessage = nil
                performTranslation()
            }
        }
    }

    // MARK: - 语言选择栏

    private var languageBar: some View {
        HStack(spacing: 20) {
            // 源语言
            Picker("源语言", selection: $sourceLanguage) {
                ForEach(Language.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .tint(BuBuColors.skyBlue)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BuBuColors.skyBlue.opacity(0.6))

            // 目标语言
            Picker("目标语言", selection: $targetLanguage) {
                ForEach(Language.allCases.filter { $0 != .auto }, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .tint(BuBuColors.skyBlue)

            Spacer()

            // 历史记录按钮
            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(showHistory ? BuBuColors.skyBlue : BuBuColors.chocolateBrown.opacity(0.5))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(showHistory ? BuBuColors.skyBlue.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHistory) {
                translationHistoryPopover
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(BuBuColors.creamWhite)
    }

    // MARK: - 翻译历史弹出框

    private var translationHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("翻译历史")
                    .font(BuBuFonts.headline)
                    .foregroundColor(BuBuColors.chocolateBrown)

                Spacer()

                if !historyService.translationHistory.isEmpty {
                    Button("清除") {
                        historyService.clearHistory(keepFavorites: true)
                    }
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.coralPink)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if historyService.translationHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.3))
                    Text("暂无翻译历史")
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(historyService.translationHistory.prefix(20)) { record in
                            TranslationHistoryRow(record: record) {
                                // 点击使用该翻译
                                sourceText = record.sourceText
                                translatedText = record.targetText
                                showHistory = false
                            } onToggleFavorite: {
                                historyService.toggleFavorite(record)
                            } onDelete: {
                                historyService.deleteRecord(record)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(BuBuColors.creamWhite)
    }

    // MARK: - 方法

    private func swapLanguages() {
        guard sourceLanguage != .auto else { return }

        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp

        let tempText = sourceText
        sourceText = translatedText
        translatedText = tempText
    }

    private func performTranslation() {
        guard !sourceText.isEmpty else { return }

        isTranslating = true
        errorMessage = nil

        // 调用 LLM 服务进行翻译
        Task {
            do {
                // 获取 LLM 配置并创建服务
                let config = settingsViewModel.currentLLMConfig

                // 检查 API Key 是否配置
                if config.apiKey.isEmpty {
                    await MainActor.run {
                        errorMessage = "请先在设置中配置 AI 服务的 API Key"
                        isTranslating = false
                    }
                    return
                }

                let service = LLMServiceFactory.create(for: config)

                // 构建翻译提示词
                let sourceLangName = sourceLanguage == .auto ? "自动检测语言" : sourceLanguage.displayName
                let targetLangName = targetLanguage.displayName

                let result = try await service.translate(
                    text: sourceText,
                    from: sourceLangName,
                    to: targetLangName
                )

                await MainActor.run {
                    translatedText = result
                    isTranslating = false

                    // 保存到翻译历史
                    historyService.addRecord(
                        sourceText: sourceText,
                        targetText: translatedText,
                        sourceLanguage: sourceLanguage.displayName,
                        targetLanguage: targetLanguage.displayName
                    )
                }
            } catch {
                await MainActor.run {
                    errorMessage = "翻译失败：\(error.localizedDescription)"
                    isTranslating = false
                }
            }
        }
    }

    private func speakText(_ text: String) {
        let synthesizer = NSSpeechSynthesizer()
        synthesizer.startSpeaking(text)
    }
}

// MARK: - 语言枚举

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
}

// MARK: - 翻译历史行视图

struct TranslationHistoryRow: View {
    let record: TranslationRecordDTO
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                // 原文
                Text(record.sourceText)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
                    .lineLimit(2)

                // 译文
                Text(record.targetText)
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                    .lineLimit(2)

                // 语言信息
                Text("\(record.sourceLanguage) → \(record.targetLanguage)")
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.skyBlue)
            }

            Spacer()

            VStack(spacing: 8) {
                // 收藏按钮
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: record.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(record.isFavorite ? BuBuColors.peachBlush : BuBuColors.chocolateBrown.opacity(0.3))
                }
                .buttonStyle(.plain)

                // 删除按钮
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                .fill(Color.white)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - 预览

#Preview {
    TranslationView()
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 400)
}
