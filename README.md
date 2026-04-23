<p align="center">
  <img src="logo.png" width="160" height="160" alt="Crypto Island Logo">
</p>

<h1 align="center">Crypto Island 🏝️</h1>

<p align="center">
  <strong>专为 macOS 设计的极简主义加密货币行情追踪工具</strong><br>
  巧妙利用 MacBook 的灵动岛区域，提供沉浸式且零干扰的交互体验。
</p>

---

## ✨ v0.2 全新进化

### 🎨 极致视觉工艺
- **原生动态衔接**：Ticker 顶部采用**反向圆角（Fillet）**设计，完美衔接屏幕顶栏边缘，复现系统级流体感。
- **智能形态切换**：收起时呈现优雅胶囊状；展开详情时，底部自动切换为直角以实现面板的无缝拼接。
- **自适应窗口**：设置页面支持内容高度自适应，告别冗余空白，极致干练。

### 📊 深度行情交互
- **点击展开**：精准点击刘海两侧即可唤起黑色高斯模糊详情面板。
- **历史 K 线图**：蜡烛图支持 **1H / 4H / 1D** 自由切换，趋势尽在掌握。
- **实时走势**：内置高性能 Canvas 绘图引擎，实时展现价格波动。

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
├── logo.png                  # 项目标识
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
