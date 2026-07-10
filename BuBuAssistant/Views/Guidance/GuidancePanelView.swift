//
//  GuidancePanelView.swift
//  BuBuAssistant
//
//  Created by Claude Code on 2026-07-10.
//  指导标签页 - 主面板中的指导功能入口
//

import SwiftUI

struct GuidancePanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 英雄区：布布形象 + 引导文案
            VStack(spacing: 12) {
                Image("bubu")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 90, height: 90)

                Text("遇到不会的操作？截图问布布")
                    .font(BuBuFonts.title)
                    .foregroundColor(BuBuColors.chocolateBrown)

                Text("布布看得懂你的屏幕，一步步教你操作\n还会把步骤朗读给你听")
                    .font(BuBuFonts.caption)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // 主操作按钮
            Button {
                NotificationCenter.default.post(name: .showGuidance, object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text("截图提问")
                }
                .font(BuBuFonts.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: BuBuShapes.buttonRadius)
                        .fill(BuBuColors.skyBlue)
                        .shadow(color: BuBuColors.skyBlue.opacity(0.35), radius: 10, x: 0, y: 5)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 26)

            // 快捷键提示
            HStack(spacing: 5) {
                Text("快捷键")
                    .font(BuBuFonts.tiny)
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.5))
                Text("⌘⇧G")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BuBuColors.chocolateBrown.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.8))
                    )
            }
            .padding(.top, 12)

            Spacer()

            // 隐私说明
            Text("截图仅用于本次提问，不会保存")
                .font(BuBuFonts.tiny)
                .foregroundColor(BuBuColors.chocolateBrown.opacity(0.4))
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 预览

#Preview {
    GuidancePanelView()
        .frame(width: 460, height: 520)
        .background(BuBuColors.warmGradient)
}
