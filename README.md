# 🎯 LightDo - 轻量级桌面待办应用

![Flutter](https://img.shields.io/badge/Flutter-3.41.6-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.11.4-0175C2?logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-4C8CBF)
![Release](https://img.shields.io/badge/Release-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)

> 一个采用**悬浮球交互**设计的极简桌面待办应用。当前主线实现基于 **Flutter Desktop**，默认以桌面小球作为入口，点击后展开窄长待办窗口。

## ✨ 核心特性

- 🎯 **悬浮球入口**：Windows / macOS 启动即显示小球，点击后展开主界面
- ✅ **完整待办功能**：新增、编辑、删除、完成 / 取消完成、拖拽排序
- 📦 **分组管理**：进行中与已完成任务分区展示，已完成区支持折叠和一键清空
- 💾 **本地存储**：任务与设置自动保存到本地 JSON 文件，无云同步依赖
- 🪟 **多窗口桌面体验**：悬浮球窗口与编辑窗口独立存在，主界面按小球位置展开
- ⌨️ **桌面快捷操作**：支持全局快捷键 `Alt+Shift+T`、主界面置顶、关闭回到悬浮球
- ⚙️ **系统集成**：Windows 支持托盘与开机自启；macOS / Windows 都提供桌面设置项
- 🚀 **自动发布**：在 `main` 分支打 `vX.Y.Z` tag 后，GitHub Actions 自动构建并发布 Release

## 🚀 快速开始

### 方式一：直接下载发布版

- 前往 GitHub Releases 下载对应平台产物
- 当前发布产物命名：
  - `lightdo-vX.Y.Z-macos-x64.zip`
  - `lightdo-vX.Y.Z-macos-arm64.zip`
  - `lightdo-vX.Y.Z-windows-x64.zip`
  - `lightdo-vX.Y.Z-linux-x64.tar.gz`

说明：
- 日常交互当前主要在 **macOS / Windows** 上验证
- **Linux x64** 已接入构建与发布链路，适合作为持续集成产物分发

### 方式二：开发者模式

```bash
# 1. 克隆仓库
git clone https://github.com/HappiLife-oh/LightDo.git
cd LightDo

# 2. 安装依赖
flutter pub get

# 3. 运行桌面应用
flutter run -d macos
# 或
flutter run -d windows
# 或
flutter run -d linux
```

## 💡 使用指南

| 操作 | 说明 |
|------|------|
| 点击悬浮球 | 展开主界面 |
| `Alt+Shift+T` | 快速显示主界面 |
| 输入框回车 / 点击“添加” | 新增任务 |
| 勾选复选框 | 标记完成 / 取消完成 |
| 点击编辑按钮 | 修改任务内容 |
| 点击删除按钮 | 删除任务 |
| 拖拽左侧手柄 | 调整进行中任务顺序 |
| 已完成区域右上角按钮 | 折叠 / 展开已完成任务 |
| “清空已完成” | 一次性删除全部已完成任务 |
| 右上角齿轮 | 打开设置面板 |

### 悬浮球交互

- **默认位置**：启动后显示在桌面右上区域
- **窗口形态**：悬浮球与主界面是两个独立窗口
- **打开方式**：点击小球展开待办主界面
- **收起方式**：关闭主界面或失焦后回到悬浮球

### 设置项

- **关闭时回到悬浮球**
- **启用全局快捷键 `Alt+Shift+T`**
- **主界面置顶**
- **开机自启**：当前仅在 Windows 提供

## 🔧 技术栈

| 技术 | 版本 / 说明 | 用途 |
|------|------|------|
| Flutter | 3.41.6 | 跨平台桌面应用框架 |
| Dart | 3.11.4 | 应用逻辑与类型系统 |
| bitsdojo_window | 0.1.6 | macOS 自定义窗口外观与启动控制 |
| window_manager | 0.5.1 | 桌面窗口显示、位置与置顶控制 |
| desktop_multi_window | 0.3.0 | 悬浮球与主界面多窗口通信 |
| hotkey_manager | 0.2.3 | 全局快捷键 |
| system_tray | 2.0.3 | Windows 托盘集成 |
| screen_retriever | 0.2.0 | 多显示器与屏幕区域计算 |
| launch_at_startup | 0.5.1 | Windows 开机自启 |

## 📦 构建与发布

### 本地构建

```bash
flutter build macos
flutter build windows
flutter build linux
```

### GitHub Actions 自动发布

仓库已内置发布工作流，文件见 [release.yml](/Users/wakejiao/Project/private/LightDo/.github/workflows/release.yml)。

触发条件：

- 仅在 **`main` 分支对应提交** 上打 `vX.Y.Z` tag 时触发

示例：

```bash
git checkout main
git pull
git tag v1.2.3
git push origin main
git push origin v1.2.3
```

工作流会自动：

1. 校验 tag 格式和所属分支
2. 构建 `macos-x64`、`macos-arm64`、`windows-x64`、`linux-x64`
3. 打包产物
4. 上传到对应 GitHub Release

## 📂 项目结构

```text
LightDo/
├── lib/
│   ├── desktop/                   # 悬浮球窗口、多窗口参数
│   ├── models/                    # 待办与设置模型
│   ├── services/                  # 本地存储、桌面集成
│   └── main.dart                  # 主入口与主界面
├── assets/
│   └── windows/
├── macos/                         # macOS Runner 与原生窗口定制
├── windows/                       # Windows Runner 与原生窗口裁剪
├── linux/                         # Linux 桌面平台工程
├── test/
│   └── widget_test.dart
├── docs/
│   ├── 项目能力分析.md
│   └── flutter重构-todolist.md
└── .github/workflows/
    └── release.yml
```

## 📌 当前状态说明

- 当前主线是 **Flutter 桌面版 LightDo**
- Electron 历史工程文件已从仓库主线移除，当前仓库只保留 Flutter Desktop 相关内容
- 旧版本中的 Electron、React、TypeScript、Node.js 开发方式已不再适用于当前项目
- 当前桌面入口与多窗口逻辑主要在：
  - [main.dart](/Users/wakejiao/Project/private/LightDo/lib/main.dart)
  - [floating_ball_app.dart](/Users/wakejiao/Project/private/LightDo/lib/desktop/floating_ball_app.dart)
  - [desktop_integration.dart](/Users/wakejiao/Project/private/LightDo/lib/services/desktop_integration.dart)

## 🧪 开发校验

```bash
flutter analyze
flutter test
```

当前仓库在提交前以这两项作为基础静态校验。
