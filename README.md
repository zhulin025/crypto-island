<p align="center">
  <img src="logo_v2.png" width="160" height="160" alt="Crypto Island Logo">
</p>

<h1 align="center">Crypto Island 🏝️</h1>

<p align="center">
  <strong>专为 macOS 设计的极简主义加密货币行情追踪工具</strong><br>
  巧妙利用 MacBook 的灵动岛区域，提供沉浸式且零干扰的交互体验。
</p>

---

## ✨ v0.4 核心更新

### 稳定性治理

- 重构行情服务层，统一为单连接状态模型，避免重复 WebSocket、重复心跳和定时器累积。
- 修正全局市场服务的重复 `Timer` 启动问题，移除长期轮询中的 `AnyCancellable` 累积风险。
- 为实时源加入连接超时、心跳保活、watchdog 检测、指数退避重连和自动降级逻辑。
- K 线请求增加请求令牌校验，快速切换币种或周期时不会再被旧请求回包覆盖。

### 数据源分层

- 建立 `实时源 / 快照源 / K线源` 三层数据通路，而不是单一数据源硬绑定。
- 详情面板新增来源状态区，直接显示当前实时源、快照源、K 线源及连接状态。
- 为每个数据源维护健康信息：健康分数、延迟、断线次数、最近成功时间、最近消息时间。

### 数据可靠性增强

- 新增 `Coinbase` 实时行情、快照和 K 线支持。
- 支持自动降级到备用源，并在主源恢复后自动回切。
- 设置页新增：
  - 锁定主数据源（关闭自动降级）
  - 故障恢复后自动回切主数据源

### 交互补充

- 右键菜单新增 “在 Coinbase 查看” 快捷跳转。
- 详情面板高度扩展，以容纳来源与健康状态展示。

## ✨ v0.3 核心新增功能

- 隐私模式：一键切换为 ASCII 猫咪动画或天气简报，保护资产隐私。
- 全局快捷键：支持 `Cmd + Opt + X` 快速切换隐私模式。
- 右键交互重构：支持复制价格、复制完整信息、快捷切换币种。
- 原生级“肩部”设计：通过自绘 `FilletShape` 还原系统级 Notch 衔接曲线。
- 即时响应系统：切换币种后可立即看到缓存内容与加载状态。

## ✨ v0.2 视觉进化

- 基于交易所 WebSocket 的实时行情更新。
- 多币种轮播。
- 价格提醒。
- 持仓追踪与盈亏计算。

## ⚙️ 当前能力

- 支持数据源：
  - `Binance`
  - `OKX`
  - `Coinbase`
  - `Gate.io`
  - `CoinGecko`
- 支持双侧币种展示与观察列表轮播。
- 支持快照、实时 ticker、K 线图、持仓盈亏、市场总览。
- 支持自动降级与主源恢复回切。
- 支持来源健康状态可视化。

## 🚀 快速开始

### 环境要求

- macOS 12.0+
- Swift 5.9+

### 编译运行

```bash
# 1. 克隆仓库
git clone https://github.com/zhulin025/crypto-island.git
cd crypto-island

# 2. 编译
swift build -c release

# 3. 复制可执行文件到 .app 并签名
cp .build/release/CryptoIsland CryptoIsland.app/Contents/MacOS/
codesign --force --deep --sign - CryptoIsland.app

# 4. 启动
open CryptoIsland.app
```

## 🧱 架构概览

### 服务层

- `BinanceService.swift`
  统一的行情聚合入口，内部负责：
  - 实时源连接与降级
  - 快照拉取
  - K 线请求
  - 健康分数与连接状态维护
- `MarketService.swift`
  负责全局市场总览数据：
  - 总市值
  - BTC 占比
  - Fear & Greed

### 视图层

- `IslandView.swift`
  灵动岛左右 ticker 渲染。
- `CoinDetailPanelView.swift`
  详情面板，包含价格、K 线、持仓、市场总览、来源状态。
- `SettingsView.swift`
  配置中心，包含数据源选择、观察列表、提醒、持仓与自动降级策略。
- `ClickDetectorWindow.swift`
  左右点击区域与右键菜单。

## 📁 项目结构

```text
cyptoland/
├── BinanceService.swift        # 行情聚合服务：实时源 / 快照 / K线 / 健康状态
├── MarketService.swift         # 全局市场概览服务
├── CoinModel.swift             # 数据模型、数据源枚举、健康状态定义、应用配置
├── IslandView.swift            # 灵动岛 Ticker 渲染
├── CoinDetailPanelView.swift   # 详情面板与来源状态展示
├── SettingsView.swift          # 设置界面与数据源策略控制
├── ClickDetectorWindow.swift   # 点击窗口与右键菜单
├── CryptoIslandApp.swift       # App 生命周期与窗口管理
└── ...
```

## 📝 0.4 变更摘要

- 将原有按交易所散落的连接逻辑收敛到统一状态机。
- 修复重复 `Timer`、重复订阅、重复重连导致的长期运行稳定性问题。
- 增加 Coinbase 作为新的实时与 K 线数据源。
- 增加数据源健康分数与来源状态可视化。
- 增加手动锁定主源、自动降级、恢复回切等可靠性策略。

## 📄 开源协议

[MIT License](LICENSE)

---
*Built with Swift for the next generation of Mac users.*
