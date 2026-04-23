import AppKit
import SwiftUI

// MARK: - 局部点击捕获窗口
class SingleClickWindow: NSWindow {
    init(rect: NSRect, side: ExpandedSide, state: IslandInteractionState) {
        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // 级别稍微调低一点，但在 overlay 之上
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isReleasedWhenClosed = false

        let clickView = SimpleClickView(side: side, state: state)
        let host = NSHostingView(rootView: clickView)
        host.frame = NSRect(x: 0, y: 0, width: rect.width, height: rect.height)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SimpleClickView: View {
    let side: ExpandedSide
    @ObservedObject var state: IslandInteractionState

    var body: some View {
        Color.white.opacity(0.0001) // 极度透明但可点击
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    state.expandedSide = (state.expandedSide == side) ? .none : side
                }
            }
    }
}

// MARK: - 展开面板 NSWindow (保持原样)
class CoinDetailWindow: NSWindow {
    init(state: IslandInteractionState, service: BinanceService) {
        let screen = NSScreen.main?.frame ?? .zero
        let tickerW = CoinDetailPanelView.tickerSideWidth
        let offset  = CoinDetailPanelView.tickerOffset
        let h = CoinDetailPanelView.panelHeight
        
        let notchInfo = NotchDetector.shared.getNotchInfo()
        let notchRect = notchInfo.hasNotch ? notchInfo.rect : NSRect(x: (screen.width - 179)/2, y: screen.height - 32, width: 179, height: 32)
        
        let leftEdge  = notchRect.minX - tickerW + offset
        let rightEdge = notchRect.maxX + tickerW - offset
        
        let x = leftEdge
        let w = rightEdge - leftEdge
        
        let topH = notchInfo.hasNotch ? notchInfo.rect.height : NSStatusBar.system.thickness
        let y = screen.height - topH - h + 16

        super.init(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let panelView = CoinDetailPanelView(state: state, service: service)
        let host = NSHostingView(rootView: panelView)
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
