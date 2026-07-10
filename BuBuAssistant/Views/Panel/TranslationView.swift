//
//  TranslationView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  翻译视图 - 多语言翻译功能（流式输出，逻辑收拢在 TranslationViewModel）
//

import SwiftUI

struct TranslationView: View {
    @StateObject private var viewModel = TranslationViewModel()
    @StateObject private var historyService = TranslationHistoryService.shared
    @State private var showHistory = false
    /// 自动翻译开关（停止输入 0.8 秒后自动触发），持久化到 UserDefaults
    @AppStorage(TranslationViewModel.autoTranslateKey) private var autoTranslate = false

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

                    TextEditor(text: $viewModel.sourceText)
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
                        Text("\(viewModel.sourceText.count) 字符")
                            .font(BuBuFonts.tiny)
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))

                        Spacer()

                        Button {
                            viewModel.clear()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.sourceText.isEmpty)

                        Button {
                            if let content = NSPasteboard.general.string(forType: .string) {
                                viewModel.sourceText = content
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.skyBlue)
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.speak(viewModel.sourceText)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.lavender)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.sourceText.isEmpty)
                    }
                }
                .padding(14)

                // 交换按钮
                VStack {
                    Spacer()

                    Button {
                        viewModel.swapLanguages()
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
                    .disabled(viewModel.sourceLanguage == .auto)

                    Spacer()
                }

                // 译文（流式输出，边生成边显示）
                VStack(alignment: .leading, spacing: 10) {
                    Text("译文")
                        .font(BuBuFonts.caption)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

                    TextEditor(text: .constant(viewModel.translatedText))
                        .font(BuBuFonts.body)
                        .foregroundColor(BuBuColors.chocolateBrown)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                                .fill(Color.white)
                                .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 6, x: 0, y: 3)
                        )
                        .overlay {
                            // 首个字符到达前显示等待提示
                            if viewModel.isTranslating && viewModel.translatedText.isEmpty {
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .tint(BuBuColors.skyBlue)
                                    Text("翻译中...")
                                        .font(BuBuFonts.caption)
                                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                                }
                            }
                        }

                    HStack {
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(BuBuFonts.tiny)
                                .foregroundColor(BuBuColors.coralPink)
                        } else if viewModel.isTranslating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(BuBuColors.skyBlue)
                                Text("翻译中...")
                                    .font(BuBuFonts.tiny)
                                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                            }
                        } else {
                            Text("\(viewModel.translatedText.count) 字符")
                                .font(BuBuFonts.tiny)
                                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                        }

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.translatedText, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.skyBlue)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.translatedText.isEmpty)

                        Button {
                            viewModel.speak(viewModel.translatedText)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 15))
                                .foregroundColor(BuBuColors.lavender)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.translatedText.isEmpty)
                    }
                }
                .padding(14)
            }

            Divider()

            // 翻译按钮
            HStack {
                Spacer()

                Button {
                    viewModel.translate()
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
                .disabled(viewModel.sourceText.isEmpty || viewModel.isTranslating)
                .opacity(viewModel.sourceText.isEmpty || viewModel.isTranslating ? 0.6 : 1)
                .keyboardShortcut(.return, modifiers: .command)

                Spacer()
            }
            .padding(18)
            .background(BuBuColors.creamWhite)
        }
        .onReceive(NotificationCenter.default.publisher(for: .translateSelectedText)) { notification in
            // 接收选中文字翻译通知（重复触发的去重在 ViewModel 内处理）
            if let text = notification.object as? String {
                viewModel.translateExternalText(text)
            }
        }
    }

    // MARK: - 语言选择栏

    private var languageBar: some View {
        HStack(spacing: 20) {
            // 源语言
            Picker("源语言", selection: $viewModel.sourceLanguage) {
                ForEach(Language.allCases, id: \.self) { lang in
                    Text(lang.displayName)
                        .foregroundColor(BuBuColors.chocolateBrown)
                        .tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .accentColor(BuBuColors.chocolateBrown)

            // 自动检测的识别结果回显
            if viewModel.sourceLanguage == .auto, let detected = viewModel.detectedLanguage {
                Text("检测到：\(detected.displayName)")
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.skyBlue)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BuBuColors.skyBlue)

            // 目标语言
            Picker("目标语言", selection: $viewModel.targetLanguage) {
                ForEach(Language.allCases.filter { $0 != .auto }, id: \.self) { lang in
                    Text(lang.displayName)
                        .foregroundColor(BuBuColors.chocolateBrown)
                        .tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .accentColor(BuBuColors.chocolateBrown)

            Spacer()

            // 自动翻译开关
            Toggle("自动翻译", isOn: $autoTranslate)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(BuBuFonts.tiny)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))
                .help("停止输入 0.8 秒后自动翻译")

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
                                viewModel.applyRecord(record)
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
        .frame(width: 500, height: 400)
}
