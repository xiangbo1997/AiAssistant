//
//  SearchView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  智能搜索视图 - AI 驱动的搜索功能
//

import SwiftUI
import MarkdownUI

struct SearchView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @StateObject private var historyService = SearchHistoryService.shared
    @State private var searchQuery = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // 搜索输入框
            searchBar

            Divider()

            // 内容区域（流式期间结果卡片边生成边显示，仅首 chunk 前显示加载）
            if isSearching && searchResults.isEmpty {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if !searchResults.isEmpty {
                resultsView
            } else if searchQuery.isEmpty {
                historyView
            } else {
                emptyResultView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSearch)) { notification in
            // 拖拽文字到布布选「智能搜索」时由此触发
            if let query = notification.object as? String, !query.isEmpty {
                searchQuery = query
                performSearch()
            }
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(BuBuColors.skyBlue)

                TextField("输入搜索内容...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)
                    .onSubmit {
                        performSearch()
                    }

                if !searchQuery.isEmpty {
                    Button {
                        cancelSearch()
                        searchQuery = ""
                        searchResults = []
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 8, x: 0, y: 3)
            )

            Button {
                if isSearching {
                    cancelSearch()
                } else {
                    performSearch()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSearching ? "stop.fill" : "sparkle.magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                    Text(isSearching ? "停止" : "搜索")
                        .font(BuBuFonts.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(isSearching ? BuBuColors.coralPink : BuBuColors.skyBlue)
                        .shadow(
                            color: (isSearching ? BuBuColors.coralPink : BuBuColors.skyBlue).opacity(0.35),
                            radius: 10, x: 0, y: 5
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(searchQuery.isEmpty && !isSearching)
            .opacity(searchQuery.isEmpty && !isSearching ? 0.6 : 1)
        }
        .padding(18)
        .background(BuBuColors.creamWhite)
    }

    // MARK: - 加载视图

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(BuBuColors.skyBlue)

            Text("正在搜索...")
                .font(BuBuFonts.body)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 错误视图

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(BuBuColors.coralPink)

            Text("搜索出错")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown)

            Text(message)
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                .multilineTextAlignment(.center)

            Button("重试") {
                performSearch()
            }
            .font(BuBuFonts.body)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                    .fill(BuBuColors.skyBlue)
            )
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 空结果视图

    private var emptyResultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(BuBuColors.skyBlue.opacity(0.5))

            Text("未找到相关结果")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown)

            Text("尝试使用不同的关键词")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 搜索历史视图

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !historyService.searchHistory.isEmpty {
                HStack {
                    Text("搜索历史")
                        .font(BuBuFonts.headline)
                        .foregroundColor(BuBuColors.chocolateBrown)

                    Spacer()

                    Button("清除") {
                        historyService.clearAllHistory()
                    }
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.skyBlue)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        historyRows
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(BuBuColors.skyBlue.opacity(0.6))

                    Text("智能搜索")
                        .font(BuBuFonts.title)
                        .foregroundColor(BuBuColors.chocolateBrown)

                    Text("输入问题或关键词，AI 将为你提供智能答案")
                        .font(BuBuFonts.body)
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var historyRows: some View {
        ForEach(historyService.searchHistory.prefix(10)) { record in
                    Button {
                        searchQuery = record.query
                        // 显示之前的结果
                        if !record.result.isEmpty {
                            searchResults = [
                                SearchResult(
                                    title: record.query,
                                    summary: record.result,
                                    source: record.provider
                                )
                            ]
                        } else {
                            performSearch()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(BuBuColors.lavender)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.query)
                                    .font(BuBuFonts.body)
                                    .foregroundColor(BuBuColors.chocolateBrown)
                                    .lineLimit(1)
                                if !record.result.isEmpty {
                                    Text(record.result)
                                        .font(BuBuFonts.tiny)
                                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()

                            // 删除按钮
                            Button {
                                historyService.deleteRecord(record)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: BuBuShapes.smallRadius)
                                .fill(Color.white)
                        )
                    }
                    .buttonStyle(.plain)
        }
    }

    // MARK: - 结果视图

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults) { result in
                    SearchResultRow(result: result)
                }
            }
            .padding(16)
        }
    }

    // MARK: - 方法

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        searchTask?.cancel()
        isSearching = true
        errorMessage = nil
        searchResults = []

        // 流式搜索：回答边生成边显示
        searchTask = Task {
            let config = settingsViewModel.currentLLMConfig

            // Ollama 走本地服务，不需要 API Key
            guard !config.apiKey.isEmpty || config.provider == .ollama else {
                await MainActor.run {
                    errorMessage = "请先在设置中配置 AI 服务的 API Key"
                    isSearching = false
                }
                return
            }

            let service = LLMServiceFactory.create(for: config)
            let messages = [
                ChatMessage(role: .system, content: "你是智能搜索助手。用简洁准确的中文回答用户的问题，使用 Markdown 组织内容，要点用列表呈现。"),
                ChatMessage(role: .user, content: query)
            ]

            do {
                await MainActor.run {
                    searchResults = [SearchResult(title: query, summary: "", source: config.provider.displayName)]
                }

                // 节流刷新：chunk 先进缓冲，每 80ms 批量发布一次，
                // 避免 Markdown 全文高频重排
                var buffer = ""
                var lastFlush = ContinuousClock.now
                for try await chunk in service.sendChatStream(messages: messages) {
                    try Task.checkCancellation()
                    buffer += chunk
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(80) {
                        let flush = buffer
                        buffer = ""
                        lastFlush = now
                        await MainActor.run {
                            guard !searchResults.isEmpty else { return }
                            searchResults[0].summary += flush
                        }
                    }
                }
                try Task.checkCancellation()

                let finalFlush = buffer
                await MainActor.run {
                    if !finalFlush.isEmpty, !searchResults.isEmpty {
                        searchResults[0].summary += finalFlush
                    }
                    isSearching = false

                    // 保存到搜索历史
                    if let summary = searchResults.first?.summary, !summary.isEmpty {
                        historyService.addRecord(
                            query: query,
                            type: .general,
                            result: summary,
                            provider: config.provider.displayName
                        )
                    }
                }
            } catch is CancellationError {
                // 被停止按钮或新搜索取消，静默结束
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    errorMessage = "搜索失败：\(error.localizedDescription)"
                    isSearching = false
                    searchResults = []
                }
            }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}

// MARK: - 搜索结果模型

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    var summary: String
    let source: String?
}

// MARK: - 搜索结果行

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.title)
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown)

            // 使用 MarkdownUI 渲染搜索结果
            Markdown(result.summary)
                .markdownTheme(.bubuTheme)
                .textSelection(.enabled)

            if let source = result.source {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                    Text(source)
                        .font(BuBuFonts.caption)
                }
                .foregroundColor(BuBuColors.skyBlue)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - 预览

#Preview {
    SearchView()
        .environmentObject(SettingsViewModel())
        .frame(width: 400, height: 500)
}
