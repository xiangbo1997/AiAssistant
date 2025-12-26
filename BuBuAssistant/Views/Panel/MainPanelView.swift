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

    private var tabBar: some View {
        HStack(spacing: 10) {
            TabButton(
                title: "便签",
                icon: "note.text",
                isSelected: selectedTab == .notes
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = .notes }
            }

            TabButton(
                title: "搜索",
                icon: "magnifyingglass",
                isSelected: selectedTab == .search
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = .search }
            }

            TabButton(
                title: "翻译",
                icon: "globe",
                isSelected: selectedTab == .translation
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = .translation }
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
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(BuBuFonts.headline)
            }
            .foregroundColor(isSelected ? .white : BuBuColors.chocolateBrown.opacity(0.8))
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                    .fill(isSelected ? BuBuColors.skyBlue : Color.white.opacity(0.6))
                    .shadow(
                        color: isSelected ? BuBuColors.skyBlue.opacity(0.35) : Color.clear,
                        radius: 10,
                        x: 0,
                        y: 5
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
