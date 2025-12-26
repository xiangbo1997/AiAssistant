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
        .frame(minWidth: 400, minHeight: 500)
        .background(BuBuColors.warmGradient)
        .onReceive(NotificationCenter.default.publisher(for: .switchPanel)) { notification in
            if let panelType = notification.object as? PanelType {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = panelType
                }
            }
        }
    }

    // MARK: - 标签栏

    private var tabBar: some View {
        HStack(spacing: 8) {
            TabButton(
                title: "便签",
                icon: "note.text",
                isSelected: selectedTab == .notes
            ) {
                withAnimation { selectedTab = .notes }
            }

            TabButton(
                title: "搜索",
                icon: "magnifyingglass",
                isSelected: selectedTab == .search
            ) {
                withAnimation { selectedTab = .search }
            }

            TabButton(
                title: "翻译",
                icon: "globe",
                isSelected: selectedTab == .translation
            ) {
                withAnimation { selectedTab = .translation }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            BuBuColors.creamWhite
                .shadow(color: BuBuColors.chocolateBrown.opacity(0.05), radius: 4, x: 0, y: 2)
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(BuBuFonts.body)
                Text(title)
                    .font(BuBuFonts.headline)
            }
            .foregroundColor(isSelected ? .white : BuBuColors.chocolateBrown)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                    .fill(isSelected ? BuBuColors.skyBlue : BuBuColors.creamWhite)
                    .shadow(
                        color: isSelected ? BuBuColors.skyBlue.opacity(0.3) : Color.clear,
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
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
