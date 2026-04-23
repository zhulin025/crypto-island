<p align="center">
  <img src="logo_v2.png" width="160" height="160" alt="Crypto Island Logo">
</p>

<h1 align="center">Crypto Island 🏝️</h1>

<p align="center">
  <strong>专为 macOS 设计的极简主义加密货币行情追踪工具</strong><br>
  巧妙利用 MacBook 的灵动岛区域，提供沉浸式且零干扰的交互体验。
</p>

---

## ✨ v0.3 核心新增功能

- 隐私模式 (Privacy Mode)：新增一键开启隐私状态，原本显示价格的区域会变为可爱的 ASCII 猫咪动画或天气简报，保护资产隐私的同时增加趣味性。
- 全局快捷键支持：实现了 Cmd + Opt + X 全局热键，支持在任何界面下快速切换隐私模式或展开详情。
- 右键交互重构：为 Ticker 注入了强大的右键上下文菜单，支持直接从收藏列表中一键切换当前监控的币种。
- 原生级“肩部”设计：通过自绘 FilletShape 还原了 macOS 系统级的 Notch 衔接曲线。
- 即时响应系统：通过 AppDelegate 单例和数据缓存逻辑，实现了点击切换后的“零等待”反馈，并引入了骨架屏加载状态。

## ✨ v0.2 视觉进化

### ⚙️ 核心功能

- **实时更新**：基于 Binance/OKX WebSocket 推送，毫秒级延迟。
- **多币种轮播**：支持最多 8 个币种自动轮播，数据不中断。
- **价格提醒**：支持自定义阈值，触发系统级推送通知。
- **持仓追踪**：实时计算投资组合的盈亏金额与百分比。

## 🚀 快速开始

### 环境要求

- macOS 12.0+（推荐 macOS 13+ 以获得最佳视觉效果）
- Swift 5.9+

### 编译运行

```bash
# 1. 克隆仓库
git clone https://github.com/zhulin025/crypto-island.git
cd crypto-island

# 2. 编译并运行 Release 版本
swift build -c release
cp .build/release/CryptoIsland CryptoIsland.app/Contents/MacOS/
codesign --force --deep --sign - CryptoIsland.app
open CryptoIsland.app
```

## 📁 项目结构

```text
cyptoland/
├── logo_v2.png                  # 项目标识
├── IslandView.swift          # 灵动岛 Ticker 渲染 (含反向圆角逻辑)
├── ClickDetectorWindow.swift # 交互窗口管理 (点击拦截 + 动态透传)
├── CoinDetailPanelView.swift # 详情面板核心视图
├── SettingsView.swift        # 自适应高度设置界面
├── BinanceService.swift      # WebSocket 多源数据流服务
└── ...
```

## 📄 开源协议

[MIT License](LICENSE)

---
*Built with Swift for the next generation of Mac users.*
