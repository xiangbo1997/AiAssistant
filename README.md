# 布布助手 (BuBuAssistant)

一款可爱的 macOS 桌面精灵应用，集成 AI 聊天、翻译、便签管理和智能搜索功能。

## 功能特性

### 桌面精灵
- 可爱的悬浮精灵角色，陪伴你的日常工作
- 支持拖拽移动，自动记忆位置
- 多种角色可选，支持自定义角色
- 丰富的动画效果（悬浮、走路、跑步、挥手、思考、专用趴睡等）
- 点击头、耳朵、眼睛、脸颊、肚子、手和脚会触发布布本体的不同表情与动作，不显示额外 Emoji 徽章
- 无聊时会偶尔自己走几步、跑两步或打招呼，真实用户长时间不互动后会趴下并伴随身体呼吸起伏

### 和布布聊天
- 支持多轮对话与流式 Markdown 回复
- 点击角色手里的手机即可展开紧凑输入框；默认不常驻额外聊天按钮
- 首包前显示思考状态，回复过程中同步说话动画和桌面气泡
- 根据回复内容触发布布本体的打招呼、开心、抱抱、好奇、惊喜等动作
- 支持停止生成、新对话和本地历史恢复

### 快捷翻译
- **双击精灵**：自动翻译当前选中的文字
- **拖拽文字**：将文字拖到精灵上进行翻译
- 翻译结果直接显示在气泡中，支持 Markdown 格式
- 自动检测语言，中英互译

### 便签管理
- 创建、编辑、删除便签
- 支持优先级标记（低/中/高/紧急）
- 三种视图模式：列表/卡片/看板
- 标签分类和搜索筛选
- 提醒功能
- 导入/导出便签数据

### 智能搜索
- 基于 AI 的智能搜索
- 搜索历史记录
- 快速访问常用搜索

## 快捷键

| 功能 | 快捷键 |
|------|--------|
| 和布布聊天 | `⌘ + ⇧ + C` |
| 角色旁快聊 | `⌘ + ⌃ + C` |
| 打开便签 | `⌘ + ⇧ + N` |
| 智能搜索 | `⌘ + ⇧ + F` |
| 快速翻译 | `⌘ + ⇧ + T` |
| 打开备忘 | `⌘ + ⇧ + M` |
| 截图求指导 | `⌘ + ⇧ + G` |
| 截图翻译 | `⌘ + ⌃ + T` |
| 显示/隐藏布布 | `⌘ + ⌃ + B` |
| 切换 2D/3D | `⌘ + ⌃ + 5` |
| 走路 / 跑步 / 跳跃 / 挥手 | `⌘ + ⌃ + 1 / 2 / 3 / 4` |
| 停止当前动作 | `⌘ + ⌃ + 0` |

## 使用方法

### 基本操作

1. **启动应用**：应用启动后，精灵会出现在屏幕右下角
2. **移动精灵**：直接拖拽精灵到任意位置
3. **单击精灵**：
   - 点击角色不同部位，触发对应表情与动作
   - 点击布布/一二手里的手机，直接展开聊天输入框
   - 如有选中文字，显示操作菜单（搜索/翻译/添加便签）
   - 点击角色外的空白区域且无选中文字时，打开便签面板
4. **双击精灵**：快速翻译当前选中的文字
5. **右键精灵**：显示快捷菜单

### 聊天功能

1. 点击角色手里的手机，或按 `⌘ + ⇧ + C`/从菜单选择“和布布聊天”
2. 输入消息后，布布会先思考，再边生成边显示回复和说话动画
3. 紧凑输入框可发送、停止、收起或打开完整聊天；回复继续显示在角色气泡中

### 翻译功能

**方式一：双击翻译**
1. 在任意应用中选中要翻译的文字
2. 双击桌面精灵
3. 翻译结果显示在气泡中

**方式二：拖拽翻译**
1. 选中文字并拖拽到精灵上
2. 选择"翻译"操作
3. 翻译结果显示在气泡中

**方式三：快捷键翻译**
1. 选中要翻译的文字
2. 按 `⌘ + ⇧ + T`
3. 打开翻译面板并自动翻译

### 便签管理

1. 点击精灵或按 `⌘ + ⇧ + N` 打开便签面板
2. 点击右上角 `+` 创建新便签
3. 设置标题、内容、优先级、标签和提醒时间
4. 右键便签可快速切换状态或删除

### 菜单栏

点击菜单栏的 ✨ 图标可以：
- 和布布聊天
- 打开便签管理
- 打开智能搜索
- 打开翻译面板
- 显示/隐藏精灵
- 打开设置
- 退出应用

## 设置说明

### 通用设置
- **开机自动启动**：系统启动时自动运行
- **隐藏 Dock 图标**：在 Dock 中不显示应用图标
- **精灵大小**：调整精灵显示比例 (50%-200%)
- **透明度**：调整精灵透明度 (30%-100%)
- **启用动画**：开启/关闭精灵动画效果
- **空闲睡眠延迟**：无操作后精灵进入睡眠状态的时间

### 角色设置
- 选择预设角色或添加自定义角色
- 支持 PNG、JPEG、GIF 格式图片

### AI 服务设置
支持多种 AI 服务提供商：
- OpenAI (GPT-4o, GPT-4, GPT-3.5)
- Claude (Claude 3.5 Sonnet, Claude 3 Opus)
- 通义千问 (Qwen)
- 文心一言 (ERNIE)
- DeepSeek
- Ollama (本地部署)

配置步骤：
1. 选择 AI 服务提供商
2. 输入 API Key（文心一言还需要 Secret Key）
3. 可选：修改 Base URL 和模型
4. 点击"测试连接"验证配置
5. 点击"保存 API Key"

### 快捷键设置
设置页会按“主功能”和“角色与动作”完整展示当前全局快捷键；所有快捷键在其它应用位于前台时仍可触发，后续版本支持自定义。

## 权限说明

应用需要以下权限才能正常工作：

### 辅助功能权限
用于获取其他应用中选中的文字，实现快速翻译功能。

授权方法：
1. 打开「系统设置」→「隐私与安全性」→「辅助功能」
2. 点击 `+` 添加布布助手
3. 确保开关已打开

### 通知权限
用于便签提醒功能。

## 数据存储

- **便签数据**：存储在本地 Core Data 数据库
- **API Key**：安全存储在系统 Keychain 中
- **设置项**：存储在 UserDefaults
- **精灵位置**：自动保存，下次启动恢复

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon 或 Intel 处理器
- Xcode 15.0 或更高版本（仅构建时需要）

## 构建说明

### 环境准备

1. 安装 Xcode 15.0 或更高版本
2. 确保已安装 Xcode Command Line Tools：
   ```bash
   xcode-select --install
   ```

### 方式一：使用 Xcode 构建（推荐）

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd BuBuAssistant
   ```

2. **打开项目**
   ```bash
   open BuBuAssistant.xcodeproj
   ```

3. **构建运行**
   - 在 Xcode 中选择 `BuBuAssistant` scheme
   - 点击 `Product` → `Build`（或按 `⌘ + B`）
   - 点击 `Product` → `Run`（或按 `⌘ + R`）运行应用

4. **导出应用**
   - 点击 `Product` → `Archive`
   - 在 Organizer 中选择导出方式

### 方式二：使用命令行构建

1. **克隆并进入项目目录**
   ```bash
   git clone <repository-url>
   cd BuBuAssistant
   ```

2. **解析依赖**
   ```bash
   swift package resolve
   ```

3. **使用 xcodebuild 构建**
   ```bash
   # Debug 构建
   xcodebuild -project BuBuAssistant.xcodeproj \
              -scheme BuBuAssistant \
              -configuration Debug \
              build

   # Release 构建
   xcodebuild -project BuBuAssistant.xcodeproj \
              -scheme BuBuAssistant \
              -configuration Release \
              build
   ```

4. **构建产物位置**
   - 构建成功后，应用位于 `~/Library/Developer/Xcode/DerivedData/BuBuAssistant-xxx/Build/Products/Debug/BuBuAssistant.app`

### 方式三：使用 Swift Package Manager 构建

```bash
# 进入项目目录
cd BuBuAssistant

# 构建项目
swift build

# Release 构建
swift build -c release
```

### 依赖说明

项目使用 Swift Package Manager 管理依赖：

| 依赖 | 版本 | 说明 |
|------|------|------|
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | 2.0.2+ | Markdown 渲染库 |

依赖会在首次构建时自动下载。

### 常见问题

**Q: 构建时提示找不到 MarkdownUI**
```bash
# 清理并重新解析依赖
swift package reset
swift package resolve
```

**Q: Xcode 提示签名错误**
- 在 Xcode 中选择 `BuBuAssistant` target
- 在 `Signing & Capabilities` 中选择你的开发团队
- 或选择 `Sign to Run Locally`

**Q: 运行时提示需要辅助功能权限**
- 这是正常现象，应用需要此权限来获取选中文字
- 按提示在系统设置中授权即可

## 技术栈

- SwiftUI
- Core Data
- Combine
- MarkdownUI
- Keychain Services
- Accessibility API

## 版本历史

### v1.0.0
- 初始版本发布
- 桌面精灵功能
- AI 翻译功能
- 便签管理功能
- 智能搜索功能

---

Made with 💖 by Claude Code
© 2025 BuBuAssistant
