<p align="center">
  <img src="logo_v2.png" width="160" height="160" alt="Crypto Island Logo">
</p>

<h1 align="center">Crypto Island 🏝️</h1>

<p align="center">
  <strong>专为 macOS 设计的极简主义加密货币行情追踪工具</strong><br>
  巧妙利用 MacBook 的灵动岛区域，提供沉浸式且零干扰的交互体验。
</p>

---

## ✨ v0.3 体验优化 (Latest)

### 💎 细节打磨
- **圆角完美对齐**：详情面板底部的圆角半径精确调整为 **11px**，实现了展开状态下面板与两侧 Ticker 边缘的无缝视觉过渡。
- **切换逻辑修复**：通过 `AppDelegate` 单例模式彻底解决了右键菜单切换币种失效的问题。
- **零延迟切换**：优化了币种切换时的数据初始化逻辑，优先利用内存缓存显示价格，消除切换瞬间的“归零”闪烁感。

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
