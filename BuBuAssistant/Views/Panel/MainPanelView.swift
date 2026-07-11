//
//  MainPanelView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2025-12-19.
//  主面板视图 - 包含便签、搜索、翻译三个功能模块
//

import SwiftUI

struct MainPanelView: View {
    @EnvironmentObject var notesViewModel: NotesViewModel
    @EnvironmentObject var spriteViewModel: SpriteViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    @State private var selectedTab: PanelType

    init(initialPanel: PanelType = .notes) {
        _selectedTab = State(initialValue: initialPanel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标签栏
            tabBar

            // 内容区域
            contentView
        }
        .frame(minWidth: 420, minHeight: 520)
        .background(BuBuColors.warmGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: .switchPanel)) { notification in
            if let panelType = notification.object as? PanelType {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = panelType
                }
            }
        }
    }

    // MARK: - 标签栏

    /// 标签定义：标题、图标与 Cmd+数字 快捷键
    private static let tabs: [(type: PanelType, title: String, icon: String, key: KeyEquivalent)] = [
        (.notes, "便签", "note.text", "1"),
        (.search, "搜索", "magnifyingglass", "2"),
        (.translation, "翻译", "globe", "3"),
        (.memo, "备忘", "key.fill", "4"),
        (.guidance, "指导", "camera.viewfinder", "5")
    ]

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Self.tabs, id: \.type) { tab in
                TabButton(
                    title: tab.title,
                    icon: tab.icon,
                    isSelected: selectedTab == tab.type
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = tab.type }
                }
                .keyboardShortcut(tab.key, modifiers: .command)
                .help("\(tab.title)（⌘\(tab.key.character)）")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            BuBuColors.creamWhite
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: - 内容视图

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .notes:
            NotesView()
        case .search:
            SearchView()
        case .translation:
            TranslationView()
        case .memo:
            MemoView()
        case .guidance:
            GuidancePanelView()
        }
    }
}

// MARK: - 标签按钮

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(BuBuFonts.caption)
            }
            .foregroundColor(isSelected ? .white : BuBuColors.chocolateBrown.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                    .fill(isSelected ? BuBuColors.skyBlue : Color.white.opacity(0.6))
                    .shadow(
                        color: isSelected ? BuBuColors.skyBlue.opacity(0.35) : BuBuColors.chocolateBrown.opacity(0.05),
                        radius: isSelected ? 10 : 4,
                        x: 0,
                        y: isSelected ? 5 : 2
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - 预览

#Preview {
    MainPanelView()
        .environmentObject(NotesViewModel())
        .environmentObject(SpriteViewModel())
        .environmentObject(SettingsViewModel())
        .frame(width: 480, height: 600)
}
