# Crypto Island 🏝️

**Crypto Island** 是一款专为 macOS 设计的极简主义加密货币行情追踪工具。它巧妙地利用了 MacBook 的 **灵动岛 (Notch)** 区域，将实时币价完美融入系统顶栏，提供沉浸式且无干扰的交互体验。

![Screenshot](https://github.com/your-username/crypto-island/raw/main/screenshot_placeholder.png) *(请上传实际截图后替换此链接)*

## ✨ 功能特性

- **灵动岛集成**：币种 Ticker 紧贴刘海边缘，视觉效果与系统高度统一。
- **实时行情**：支持多币种（BTC, ETH 等）实时价格追踪，秒级更新。
- **动态详情面板**：点击刘海两侧可展开精美详情页，包含：
  - **价格走势图**：直观展示近期价格波动。
  - **关键指标**：24h 最高、最低价及成交量。
  - **平滑动画**：支持从刘海滑入/滑出的高级过渡效果。
- **全系统兼容**：智能识别不同尺寸 MacBook 的刘海宽度，自动适配布局。
- **极致轻量**：纯 Swift/SwiftUI 编写，性能卓越，资源占用极低。

## 🚀 快速开始

### 编译安装
1. 克隆仓库：
   ```bash
   git clone https://github.com/your-username/crypto-island.git
   cd crypto-island
   ```
2. 编译 Release 版本：
   ```bash
   swift build -c release
   ```
3. 将二进制文件拷贝到 .app 包中并运行：
   ```bash
   cp .build/release/CryptoIsland CryptoIsland.app/Contents/MacOS/
   open CryptoIsland.app
   ```

## 🛠️ 技术栈
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI & AppKit
- **Layout**: 采用绝对坐标定位技术实现刘海区域的精准对接。

## 📄 开源协议
[MIT License](LICENSE)

---
*Created with ❤️ for Mac Users.*
