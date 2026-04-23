import AppKit
import SwiftUI

// MARK: - 左/右点击捕获窗口

class SingleClickWindow: NSWindow {
    init(rect: NSRect, side: ExpandedSide, state: IslandInteractionState,
         service: BinanceService, onOpenSettings: @escaping () -> Void) {
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isReleasedWhenClosed = false

        let clickView = SimpleClickView(side: side, state: state,
                                        service: service, onOpenSettings: onOpenSettings)
        let host = NSHostingView(rootView: clickView)
        host.frame = NSRect(x: 0, y: 0, width: rect.width, height: rect.height)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 点击视图（含右键菜单）

struct SimpleClickView: View {
    let side: ExpandedSide
    @ObservedObject var state: IslandInteractionState
    @ObservedObject var service: BinanceService
    var onOpenSettings: () -> Void

    private var coin: Coin? {
        side == .left ? service.leftCoin : service.rightCoin
    }

    var body: some View {
        Color.white.opacity(0.0001)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    state.expandedSide = (state.expandedSide == side) ? .none : side
                }
            }
            .contextMenu {
                contextMenuItems()
            }
    }

    @ViewBuilder
    private func contextMenuItems() -> some View {
        if let coin = coin {
            // 复制价格
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(coin.formattedPrice, forType: .string)
            }) {
                Label("复制价格  $\(coin.formattedPrice)", systemImage: "doc.on.doc")
            }

            Button(action: {
                let full = "\(coin.symbol)  $\(coin.formattedPrice)  \(coin.formattedChange)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(full, forType: .string)
            }) {
                Label("复制完整信息", systemImage: "doc.on.clipboard")
            }

            Divider()

            // 跳转到交易所
            Button(action: {
                let sym = coin.symbol.lowercased()
                if let url = URL(string: "https://www.binance.com/en/trade/\(sym)_usdt") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("在 Binance 查看", systemImage: "safari")
            }

            Button(action: {
                let sym = coin.symbol.uppercased()
                if let url = URL(string: "https://www.okx.com/trade-spot/\(sym)-usdt") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("在 OKX 查看", systemImage: "safari")
            }

            Button(action: {
                let sym = coin.symbol.lowercased()
                if let url = URL(string: "https://www.coingecko.com/en/coins/\(sym)") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("在 CoinGecko 查看", systemImage: "chart.line.uptrend.xyaxis")
            }

            Divider()

            // 展开/收起详情
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    state.expandedSide = (state.expandedSide == side) ? .none : side
                }
            }) {
                let isExpanded = state.expandedSide == side
                Label(isExpanded ? "收起详情" : "展开详情", systemImage: isExpanded ? "chevron.up" : "chevron.down")
            }

            Divider()

            Button(action: { onOpenSettings() }) {
                Label("设置…", systemImage: "gear")
            }
        } else {
            Text("等待数据…")
                .foregroundColor(.secondary)
        }
    }
}

import Combine

class CoinDetailWindow: NSWindow {
    private var cancellables = Set<AnyCancellable>()

    init(state: IslandInteractionState, service: BinanceService, market: MarketService, holdings: [PortfolioHolding]) {
        let screen    = NSScreen.screens.first?.frame ?? .zero
        let tickerW   = CoinDetailPanelView.tickerSideWidth
        let offset    = CoinDetailPanelView.tickerOffset
        let h         = CoinDetailPanelView.panelHeight

        let notchInfo = NotchDetector.shared.getNotchInfo()
        let notchRect = notchInfo.hasNotch ? notchInfo.rect : NSRect(x: (screen.width - 179)/2, y: screen.height - 32, width: 179, height: 32)

        let leftEdge  = notchRect.minX - tickerW + offset
        let rightEdge = notchRect.maxX + tickerW - offset
        let x = leftEdge
        let w = rightEdge - leftEdge

        let topH = notchInfo.hasNotch ? notchInfo.rect.height : NSStatusBar.system.thickness
        let y    = screen.height - topH - h + 16

        super.init(contentRect: NSRect(x: x, y: y, width: w, height: h),
                   styleMask: [.borderless], backing: .buffered, defer: false)

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true // 初始设为 true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        // 监听展开状态：展开时响应点击，收起时透传
        state.$expandedSide
            .sink { [weak self] side in
                self?.ignoresMouseEvents = (side == .none)
            }
            .store(in: &cancellables)

        let panelView = CoinDetailPanelView(state: state, service: service,
                                             market: market, holdings: holdings)
        let host = NSHostingView(rootView: panelView)
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
