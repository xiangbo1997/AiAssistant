//
//  MemoView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-27.
//  备忘录视图 - 安全存储命令、账号密码等敏感信息
//

import SwiftUI

struct MemoView: View {
    @StateObject private var memoService = MemoService.shared
    @State private var searchText = ""
    @State private var selectedType: MemoType? = nil
    @State private var showingAddMemo = false
    @State private var showingUnlock = true
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSettingPassword = false
    @State private var unlockError = false
    @State private var showPassword = false

    var body: some View {
        Group {
            if memoService.isLocked {
                lockScreenView
            } else {
                mainContentView
            }
        }
        .onAppear {
            isSettingPassword = !memoService.hasPassword
        }
    }

    // MARK: - 锁定界面

    private var lockScreenView: some View {
        VStack(spacing: 0) {
            Spacer()

            // 锁图标动画
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BuBuColors.lavender.opacity(0.3), BuBuColors.softCloud],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: isSettingPassword ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BuBuColors.lavender, BuBuColors.skyBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.bottom, 24)

            // 标题
            Text(isSettingPassword ? "设置访问密码" : "备忘录已锁定")
                .font(BuBuFonts.title)
                .foregroundColor(BuBuColors.chocolateBrown)

            Text(isSettingPassword ? "首次使用，请设置密码保护您的数据" : "请输入密码解锁")
                .font(BuBuFonts.caption)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                .padding(.top, 4)
                .padding(.bottom, 28)

            // 密码输入
            VStack(spacing: 14) {
                passwordField(
                    placeholder: "输入密码",
                    text: $password,
                    showPassword: showPassword
                )

                if isSettingPassword {
                    passwordField(
                        placeholder: "确认密码",
                        text: $confirmPassword,
                        showPassword: showPassword
                    )
                }

                // 显示密码切换
                HStack {
                    Button {
                        showPassword.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                            Text(showPassword ? "隐藏密码" : "显示密码")
                                .font(BuBuFonts.caption)
                        }
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .frame(width: 260)

            // 错误提示
            if unlockError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(isSettingPassword ? "两次密码不一致" : "密码错误，请重试")
                        .font(BuBuFonts.caption)
                }
                .foregroundColor(BuBuColors.coralPink)
                .padding(.top, 12)
            }

            // 解锁按钮
            Button {
                handleUnlock()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSettingPassword ? "checkmark.shield" : "lock.open")
                        .font(.system(size: 15, weight: .medium))
                    Text(isSettingPassword ? "设置密码" : "解锁")
                        .font(BuBuFonts.headline)
                }
                .foregroundColor(.white)
                .frame(width: 200)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(
                            LinearGradient(
                                colors: [BuBuColors.lavender, BuBuColors.skyBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: BuBuColors.lavender.opacity(0.4), radius: 12, x: 0, y: 6)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
            .disabled(password.isEmpty || (isSettingPassword && confirmPassword.isEmpty))
            .opacity(password.isEmpty || (isSettingPassword && confirmPassword.isEmpty) ? 0.6 : 1)

            Spacer()

            // 安全提示
            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 11))
                Text("数据使用 AES-256 加密存储")
                    .font(BuBuFonts.tiny)
            }
            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BuBuColors.warmGradient)
    }

    private func passwordField(placeholder: String, text: Binding<String>, showPassword: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 15))
                .foregroundColor(BuBuColors.lavender)

            Group {
                if showPassword {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(BuBuFonts.body)
            .foregroundColor(BuBuColors.chocolateBrown)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }

    private func handleUnlock() {
        unlockError = false

        if isSettingPassword {
            guard password == confirmPassword else {
                unlockError = true
                return
            }
            if memoService.setInitialPassword(password) {
                password = ""
                confirmPassword = ""
            } else {
                unlockError = true
            }
        } else {
            if memoService.unlock(with: password) {
                password = ""
            } else {
                unlockError = true
            }
        }
    }

    // MARK: - 主内容视图

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbar

            Divider()

            // 类型筛选标签
            typeFilterBar

            // 内容区域
            if filteredMemos.isEmpty {
                emptyStateView
            } else {
                memoListView
            }
        }
        .sheet(isPresented: $showingAddMemo) {
            MemoEditorView(mode: .add) { memo in
                memoService.addMemo(memo)
            }
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 14) {
            // 搜索框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(BuBuColors.lavender)

                TextField("搜索备忘录...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(BuBuFonts.body)
                    .foregroundColor(BuBuColors.chocolateBrown)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.inputRadius)
                    .fill(Color.white)
                    .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 8, x: 0, y: 3)
            )

            // 锁定按钮
            Button {
                memoService.lock()
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(BuBuColors.coralPink)
            }
            .buttonStyle(.plain)
            .help("锁定备忘录")

            // 添加按钮
            Button {
                showingAddMemo = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(BuBuColors.lavender)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BuBuColors.creamWhite)
    }

    // MARK: - 类型筛选

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // 全部
                FilterChip(
                    title: "全部",
                    icon: "tray.full",
                    color: BuBuColors.chocolateBrown,
                    isSelected: selectedType == nil,
                    count: memoService.memos.count
                ) {
                    selectedType = nil
                }

                // 收藏
                FilterChip(
                    title: "收藏",
                    icon: "star.fill",
                    color: BuBuColors.sunshineYellow,
                    isSelected: false,
                    count: memoService.favorites.count
                ) {
                    // 特殊处理收藏筛选
                }

                // 各类型
                ForEach(MemoType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.title,
                        icon: type.icon,
                        color: type.color,
                        isSelected: selectedType == type,
                        count: memoService.memos.filter { $0.type == type }.count
                    ) {
                        selectedType = type
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(BuBuColors.creamWhite.opacity(0.5))
    }

    // MARK: - 备忘录列表

    private var memoListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredMemos) { memo in
                    MemoRowView(memo: memo)
                        .contextMenu {
                            memoContextMenu(for: memo)
                        }
                }
            }
            .padding(14)
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedType?.icon ?? "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(BuBuColors.lavender.opacity(0.6))

            Text(searchText.isEmpty ? "暂无备忘录" : "未找到匹配项")
                .font(BuBuFonts.headline)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))

            if searchText.isEmpty {
                Button("添加第一条备忘录") {
                    showingAddMemo = true
                }
                .font(BuBuFonts.body)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(BuBuColors.lavender)
                )
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func memoContextMenu(for memo: MemoItem) -> some View {
        Button {
            copyToClipboard(memo.content)
            memoService.recordUsage(memo)
        } label: {
            Label("复制内容", systemImage: "doc.on.doc")
        }

        if memo.type == .credential, let username = memo.username {
            Button {
                copyToClipboard(username)
            } label: {
                Label("复制用户名", systemImage: "person.crop.circle")
            }
        }

        Divider()

        Button {
            memoService.toggleFavorite(memo)
        } label: {
            Label(
                memo.isFavorite ? "取消收藏" : "收藏",
                systemImage: memo.isFavorite ? "star.slash" : "star"
            )
        }

        Divider()

        Button(role: .destructive) {
            memoService.deleteMemo(memo)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - 辅助方法

    private var filteredMemos: [MemoItem] {
        var result = memoService.memos

        if let type = selectedType {
            result = result.filter { $0.type == type }
        }

        if !searchText.isEmpty {
            result = memoService.search(searchText)
            if let type = selectedType {
                result = result.filter { $0.type == type }
            }
        }

        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - 筛选标签组件

struct FilterChip: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(BuBuFonts.caption)

                if count > 0 {
                    Text("\(count)")
                        .font(BuBuFonts.tiny)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.3) : color.opacity(0.2))
                        )
                }
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? color : color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 备忘录行视图

struct MemoRowView: View {
    let memo: MemoItem
    @StateObject private var memoService = MemoService.shared
    @State private var showingEditor = false
    @State private var showContent = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            // 类型图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(memo.type.color.opacity(0.15))
                    .frame(width: 42, height: 42)

                Image(systemName: memo.type.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(memo.type.color)
            }

            // 内容
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(memo.title)
                        .font(BuBuFonts.body)
                        .foregroundColor(BuBuColors.chocolateBrown)

                    if memo.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(BuBuColors.sunshineYellow)
                    }
                }

                // 用户名（仅账号类型）
                if memo.type == .credential, let username = memo.username {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 10))
                        Text(username)
                            .font(BuBuFonts.caption)
                    }
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.6))
                }

                // 内容预览（可切换显示）
                HStack(spacing: 4) {
                    if showContent {
                        Text(memo.content)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.8))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "•", count: min(memo.content.count, 16)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                    }
                }

                // 标签
                if !memo.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(memo.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(BuBuFonts.tiny)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(memo.type.color.opacity(0.12))
                                .foregroundColor(memo.type.color)
                                .cornerRadius(6)
                        }
                    }
                }
            }

            Spacer()

            // 操作按钮
            VStack(spacing: 8) {
                // 显示/隐藏
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showContent.toggle()
                    }
                } label: {
                    Image(systemName: showContent ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                }
                .buttonStyle(.plain)

                // 复制
                Button {
                    copyContent()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(copied ? BuBuColors.mintGreen : BuBuColors.lavender)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .fill(Color.white)
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BuBuShapes.cardRadius)
                .stroke(memo.type.color.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            showingEditor = true
        }
        .sheet(isPresented: $showingEditor) {
            MemoEditorView(mode: .edit(memo)) { updated in
                memoService.updateMemo(updated)
            }
        }
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(memo.content, forType: .string)
        memoService.recordUsage(memo)

        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

// MARK: - 预览

#Preview {
    MemoView()
        .frame(width: 420, height: 520)
}
