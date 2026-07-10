//
//  SettingsView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  设置视图 - 应用配置界面
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var spriteViewModel: SpriteViewModel

    var body: some View {
        TabView {
            // 通用设置
            GeneralSettingsView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            // 角色设置
            CharacterSettingsView()
                .environmentObject(viewModel)
                .environmentObject(spriteViewModel)
                .tabItem {
                    Label("角色", systemImage: "person.crop.circle")
                }

            // AI 设置
            AISettingsView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("AI 服务", systemImage: "cpu")
                }

            // 快捷键设置
            ShortcutsSettingsView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            // 关于
            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - 通用设置

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机自动启动", isOn: $viewModel.launchAtLogin)
                Toggle("隐藏 Dock 图标", isOn: $viewModel.hideDockIcon)
            }

            Section("精灵外观") {
                HStack {
                    Text("大小")
                    Slider(value: $viewModel.spriteScale, in: 0.5...2.0, step: 0.1)
                    Text("\(Int(viewModel.spriteScale * 100))%")
                        .frame(width: 50)
                }

                HStack {
                    Text("透明度")
                    Slider(value: $viewModel.spriteOpacity, in: 0.3...1.0, step: 0.1)
                    Text("\(Int(viewModel.spriteOpacity * 100))%")
                        .frame(width: 50)
                }

                Toggle("启用动画", isOn: $viewModel.enableAnimation)
            }

            Section("行为") {
                HStack {
                    Text("空闲睡眠延迟")
                    Slider(value: $viewModel.sleepDelay, in: 60...600, step: 60)
                    Text("\(Int(viewModel.sleepDelay / 60)) 分钟")
                        .frame(width: 60)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 角色设置

struct CharacterSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var spriteViewModel: SpriteViewModel
    @State private var showingImagePicker = false

    var body: some View {
        VStack(spacing: 20) {
            // 预设角色列表
            Text("选择角色")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                ForEach(spriteViewModel.allCharacters) { character in
                    CharacterCard(
                        character: character,
                        isSelected: character.id == viewModel.currentCharacter.id
                    ) {
                        viewModel.currentCharacter = character
                    }
                }

                // 自定义角色按钮
                Button {
                    showingImagePicker = true
                } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 24))
                            )
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.45))

                        Text("添加")
                            .font(.caption)
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 当前角色预览
            VStack(spacing: 8) {
                Text("当前角色: \(viewModel.currentCharacter.name)")
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.png, .jpeg, .gif],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    addCustomCharacter(from: url)
                }
            case .failure:
                break // 导入失败，静默处理
            }
        }
    }

    private func addCustomCharacter(from url: URL) {
        // 复制图片到应用支持目录
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let characterDir = appSupport.appendingPathComponent("BuBuAssistant/Characters", isDirectory: true)
        try? fileManager.createDirectory(at: characterDir, withIntermediateDirectories: true)

        let destURL = characterDir.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)

        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }

            try fileManager.copyItem(at: url, to: destURL)

            // 使用正确的方法签名添加自定义角色
            spriteViewModel.addCustomCharacter(name: "自定义角色", imagePath: destURL.path)

            // 获取刚添加的角色并设置为当前角色
            if let newCharacter = spriteViewModel.customCharacters.last {
                viewModel.currentCharacter = newCharacter
            }
        } catch {
            // 保存失败，静默处理
        }
    }
}

// MARK: - 角色卡片

struct CharacterCard: View {
    let character: SpriteCharacter
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                if character.isCustom, let path = character.customImagePath {
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Image(character.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text(character.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? BuBuColors.skyBlue.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? BuBuColors.skyBlue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI 设置

struct AISettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var showingAPIKey = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?

    // 草稿模式：文本框绑定本地状态，停止输入 0.5s 后才提交到 ViewModel。
    // 直接绑定 llmConfigs 会导致每个按键都触发持久化（JSON+UserDefaults）
    // 并让所有观察该单例的视图（含桌面精灵窗口）全量重渲染，造成输入卡顿
    @State private var baseURLDraft = ""
    @State private var modelDraft = ""
    @State private var draftProvider: LLMProviderType = .openai
    @State private var commitTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("AI 服务提供商") {
                Picker("选择服务", selection: $viewModel.currentProvider) {
                    ForEach(LLMProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: viewModel.currentProvider) { _, _ in
                    commitDrafts()  // 先把上一个服务商的未提交草稿存下
                    loadDrafts()
                    loadAPIKey()
                    // 切换服务商后清空已拉取的模型列表（各家列表不通用）
                    fetchedModels = []
                    modelFetchError = nil
                }
            }

            Section("API 配置") {
                HStack {
                    if showingAPIKey {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }

                    Button {
                        showingAPIKey.toggle()
                    } label: {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.currentProvider == .wenxin {
                    SecureField("Secret Key", text: $secretKey)
                }

                Button("保存 API Key") {
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty)
            }

            Section("模型设置") {
                if let config = viewModel.llmConfigs[viewModel.currentProvider] {
                    TextField("Base URL", text: $baseURLDraft)
                        .onChange(of: baseURLDraft) { _, _ in scheduleCommit() }
                        .onSubmit { commitDrafts() }

                    HStack(spacing: 6) {
                        TextField("模型（可选择或手动输入）", text: $modelDraft)
                            .onChange(of: modelDraft) { _, _ in scheduleCommit() }
                            .onSubmit { commitDrafts() }

                        // 模型下拉：优先展示从 API 拉取的真实列表，未拉取时用静态预设；
                        // 中转站的自定义模型名仍可手动输入
                        Menu {
                            Button {
                                Task { await fetchAvailableModels() }
                            } label: {
                                Label(
                                    isFetchingModels ? "正在拉取…" : "🔄 拉取可用模型",
                                    systemImage: "arrow.clockwise"
                                )
                            }
                            .disabled(isFetchingModels)

                            Divider()

                            ForEach(fetchedModels.isEmpty ? viewModel.currentProvider.availableModels : fetchedModels, id: \.self) { model in
                                Button {
                                    modelDraft = model
                                    commitDrafts()
                                } label: {
                                    HStack {
                                        Text(model)
                                        if model == modelDraft {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            if isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("选择模型（可从 API 拉取真实列表）")
                    }

                    if !fetchedModels.isEmpty {
                        Text("已拉取 \(fetchedModels.count) 个可用模型")
                            .font(.caption)
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                    }

                    if let fetchError = modelFetchError {
                        Text(fetchError)
                            .font(.caption)
                            .foregroundColor(BuBuColors.coralPink)
                            .lineLimit(2)
                    }

                    HStack {
                        Text("Temperature")
                        Slider(value: Binding(
                            get: { config.temperature },
                            set: { newValue in
                                var updatedConfig = config
                                updatedConfig.temperature = newValue
                                viewModel.updateLLMConfig(updatedConfig)
                            }
                        ), in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", config.temperature))
                            .frame(width: 40)
                    }

                    HStack {
                        Text("最大 Tokens")
                        Slider(value: Binding(
                            get: { Double(config.maxTokens) },
                            set: { newValue in
                                var updatedConfig = config
                                updatedConfig.maxTokens = Int(newValue)
                                viewModel.updateLLMConfig(updatedConfig)
                            }
                        ), in: 100...4000, step: 100)
                        Text("\(config.maxTokens)")
                            .frame(width: 50)
                    }
                }
            }

            Section {
                HStack {
                    Button("测试连接") {
                        testConnection()
                    }
                    .disabled(isTesting || apiKey.isEmpty)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("成功") ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadDrafts()
            loadAPIKey()
        }
        .onDisappear {
            commitDrafts()
        }
    }

    private func loadAPIKey() {
        apiKey = KeychainService.shared.getAPIKey(for: viewModel.currentProvider) ?? ""
        secretKey = KeychainService.shared.getSecretKey(for: viewModel.currentProvider) ?? ""
    }

    // MARK: - 草稿提交

    /// 从当前服务商的配置装载草稿
    private func loadDrafts() {
        draftProvider = viewModel.currentProvider
        let config = viewModel.llmConfigs[draftProvider]
        baseURLDraft = config?.baseURL ?? ""
        modelDraft = config?.model ?? ""
    }

    /// 停止输入 0.5s 后自动提交，避免每个按键都触发持久化与全局重渲染
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            commitDrafts()
        }
    }

    /// 将草稿写回 ViewModel（无变化时跳过，不触发无谓的保存）
    private func commitDrafts() {
        commitTask?.cancel()
        guard var config = viewModel.llmConfigs[draftProvider] else { return }
        guard config.baseURL != baseURLDraft || config.model != modelDraft else { return }

        config.baseURL = baseURLDraft
        config.model = modelDraft
        viewModel.updateLLMConfig(config)
    }

    private func saveAPIKey() {
        KeychainService.shared.saveAPIKey(apiKey, for: viewModel.currentProvider)
        if viewModel.currentProvider == .wenxin {
            KeychainService.shared.saveSecretKey(secretKey, for: viewModel.currentProvider)
        }

        // 更新配置
        if var config = viewModel.llmConfigs[viewModel.currentProvider] {
            config.apiKey = apiKey
            config.secretKey = viewModel.currentProvider == .wenxin ? secretKey : nil
            viewModel.updateLLMConfig(config)
        }
    }

    /// 从当前服务的 API 拉取真实可用的模型列表
    private func fetchAvailableModels() async {
        commitDrafts()  // 确保使用输入框中最新的 Base URL
        guard let config = viewModel.llmConfigs[viewModel.currentProvider] else { return }

        isFetchingModels = true
        modelFetchError = nil

        do {
            let service = LLMServiceFactory.create(for: config)
            let models = try await service.listModels()
            fetchedModels = models
            if models.isEmpty {
                modelFetchError = "该服务未返回任何模型"
            }
        } catch {
            modelFetchError = "拉取失败：\(error.localizedDescription)"
        }

        isFetchingModels = false
    }

    private func testConnection() {
        commitDrafts()  // 确保使用输入框中最新的 Base URL 与模型
        isTesting = true
        testResult = nil

        Task {
            let result = await viewModel.testLLMConnection(for: viewModel.currentProvider)

            await MainActor.run {
                isTesting = false
                switch result {
                case .success:
                    testResult = "连接成功"
                case .failure(let error):
                    testResult = "连接失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 快捷键设置

struct ShortcutsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundColor(BuBuColors.skyBlue)
                Text("全局快捷键")
                    .font(BuBuFonts.headline)
                    .foregroundColor(BuBuColors.chocolateBrown)
                Spacer()
            }
            .padding()
            .background(BuBuColors.creamWhite)

            Divider()

            // 快捷键列表
            VStack(spacing: 12) {
                ShortcutRow(
                    icon: "note.text",
                    title: "打开便签",
                    shortcut: viewModel.globalNoteShortcut,
                    color: BuBuColors.mintGreen
                )

                ShortcutRow(
                    icon: "magnifyingglass",
                    title: "智能搜索",
                    shortcut: viewModel.globalSearchShortcut,
                    color: BuBuColors.skyBlue
                )

                ShortcutRow(
                    icon: "globe",
                    title: "快速翻译",
                    shortcut: viewModel.globalTranslateShortcut,
                    color: BuBuColors.lavender
                )
            }
            .padding()

            Spacer()

            // 提示信息
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(BuBuColors.skyBlue.opacity(0.7))
                Text("快捷键功能将在后续版本中支持自定义")
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(BuBuColors.skyBlue.opacity(0.05))
        }
        .background(BuBuColors.creamWhite)
    }
}

struct ShortcutRow: View {
    let icon: String
    let title: String
    let shortcut: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                )

            // 标题
            Text(title)
                .font(BuBuFonts.body)
                .foregroundColor(BuBuColors.chocolateBrown)

            Spacer()

            // 快捷键显示
            Text(shortcut)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 4, x: 0, y: 2)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
}

// MARK: - 关于

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // 应用图标 - 使用布布形象
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BuBuColors.peachBlush, BuBuColors.coralPink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: BuBuColors.coralPink.opacity(0.3), radius: 20, x: 0, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
            }

            // 应用名称
            Text("布布助手")
                .font(BuBuFonts.title)
                .foregroundColor(BuBuColors.chocolateBrown)

            // 版本信息
            Text("版本 1.0.0")
                .font(BuBuFonts.body)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))

            // 描述
            Text("一款可爱的 macOS 桌面精灵应用\n陪伴你的每一天 ✨")
                .font(BuBuFonts.body)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            // 链接
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                        Text("GitHub")
                    }
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.skyBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                            .fill(BuBuColors.skyBlue.opacity(0.1))
                    )
                }

                Link(destination: URL(string: "https://github.com")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.bubble")
                        Text("反馈问题")
                    }
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.lavender)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                            .fill(BuBuColors.lavender.opacity(0.1))
                    )
                }
            }

            Spacer()

            // 版权信息
            VStack(spacing: 4) {
                Text("Made with 💖 by Claude Code")
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                Text("© 2025 BuBuAssistant")
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BuBuColors.creamWhite)
    }
}

// MARK: - 预览

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(SpriteViewModel())
}
