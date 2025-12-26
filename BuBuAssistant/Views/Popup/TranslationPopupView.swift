//
//  TranslationPopupView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-22.
//  翻译气泡弹窗 - 在选中文字位置显示翻译结果
//

import SwiftUI

struct TranslationPopupView: View {
    let sourceText: String
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    @State private var translatedText: String = ""
    @State private var isTranslating: Bool = true
    @State private var errorMessage: String?
    @State private var targetLanguage: Language = .chinese

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 原文（折叠显示）
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 12))
                    .foregroundColor(BuBuColors.skyBlue)

                Text(sourceText)
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))
                    .lineLimit(2)

                Spacer()

                // 目标语言切换
                Menu {
                    ForEach(Language.allCases.filter { $0 != .auto }, id: \.self) { lang in
                        Button {
                            targetLanguage = lang
                            performTranslation()
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                if targetLanguage == lang {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(targetLanguage.displayName)
                            .font(BuBuFonts.tiny)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(BuBuColors.skyBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BuBuColors.skyBlue.opacity(0.1))
                    )
                }
                .menuStyle(.borderlessButton)
            }

            Divider()

            // 翻译结果
            if isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(BuBuColors.skyBlue)
                    Text("翻译中...")
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(BuBuColors.coralPink)
                    Text(error)
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.coralPink)
                }
            } else {
                Text(translatedText)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
                    .textSelection(.enabled)

                // 操作按钮
                HStack(spacing: 12) {
                    Spacer()

                    // 复制按钮
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translatedText, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("复制")
                        }
                        .font(BuBuFonts.tiny)
                        .foregroundColor(BuBuColors.skyBlue)
                    }
                    .buttonStyle(.plain)

                    // 朗读按钮
                    Button {
                        speakText(translatedText)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2")
                            Text("朗读")
                        }
                        .font(BuBuFonts.tiny)
                        .foregroundColor(BuBuColors.lavender)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.15), radius: 12, x: 0, y: 6)
        )
        .onAppear {
            // 智能检测目标语言
            detectTargetLanguage()
            performTranslation()
        }
    }

    // MARK: - 方法

    /// 智能检测目标语言
    private func detectTargetLanguage() {
        // 简单判断：如果原文主要是中文，则翻译成英文；否则翻译成中文
        let chineseCount = sourceText.filter { $0.isChineseCharacter }.count
        let totalCount = sourceText.filter { !$0.isWhitespace }.count

        if totalCount > 0 && Double(chineseCount) / Double(totalCount) > 0.3 {
            targetLanguage = .english
        } else {
            targetLanguage = .chinese
        }
    }

    /// 执行翻译
    private func performTranslation() {
        isTranslating = true
        errorMessage = nil

        Task {
            do {
                let config = settingsViewModel.currentLLMConfig

                if config.apiKey.isEmpty {
                    await MainActor.run {
                        errorMessage = "请先配置 API Key"
                        isTranslating = false
                    }
                    return
                }

                let service = LLMServiceFactory.create(for: config)
                let result = try await service.translate(
                    text: sourceText,
                    from: "自动检测",
                    to: targetLanguage.displayName
                )

                await MainActor.run {
                    translatedText = result
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "翻译失败"
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

// MARK: - Character 扩展

extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        // 中文 Unicode 范围
        return (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value)
    }
}

// MARK: - 预览

#Preview {
    TranslationPopupView(sourceText: "Hello, how are you today?")
        .environmentObject(SettingsViewModel())
}
