import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandInteractionState
    @ObservedObject var service: BinanceService
    let notchInfo = NotchDetector.shared.getNotchInfo()

    var body: some View {
        let info = notchInfo
        let rect = info.hasNotch ? info.rect : NSRect(x: 0, y: 0, width: 50, height: 33)
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        
        ZStack {
            // 中间补位
            Color.black
                .frame(width: rect.width, height: 33)
                .position(x: rect.midX, y: 16.5)

            // 左侧 Ticker
            if let coin = service.leftCoin {
                CoinTickerView(coin: coin, side: .left, state: state)
                    .frame(width: CoinDetailPanelView.tickerSideWidth + 20, height: 33) // 增加宽度以容纳反向圆角
                    .position(x: rect.minX - (CoinDetailPanelView.tickerSideWidth + 20)/2 + 26 + 10, y: 16.5)
            }
            
            // 右侧 Ticker
            if let coin = service.rightCoin {
                CoinTickerView(coin: coin, side: .right, state: state)
                    .frame(width: CoinDetailPanelView.tickerSideWidth + 20, height: 33)
                    .position(x: rect.maxX + (CoinDetailPanelView.tickerSideWidth + 20)/2 - 26 - 10, y: 16.5)
            }
        }
        .frame(width: screenWidth, height: 33)
    }
}

// MARK: - CoinTickerView

struct CoinTickerView: View {
    let coin: Coin
    let side: ExpandedSide
    @ObservedObject var state: IslandInteractionState

    var body: some View {
        let isExpanded = state.expandedSide != .none
        
        ZStack(alignment: side == .left ? .trailing : .leading) {
            // 真正的内容区域 (130px)
            VStack(alignment: .center, spacing: 1) {
                HStack(spacing: 5) {
                    Text(coin.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    Text(coin.formattedPrice)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                Text(coin.formattedChange)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(coin.changeColor)
            }
            .frame(width: CoinDetailPanelView.tickerSideWidth, height: 33)
            .background(Color.black)
            .clipShape(TickerMainShape(side: side, isExpanded: isExpanded))
            
            // 额外的反向圆角衔接块 (始终显示)
            FilletShape(side: side)
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .offset(x: side == .left ? -CoinDetailPanelView.tickerSideWidth : CoinDetailPanelView.tickerSideWidth, y: -10.5)
        }
    }
}

// 1. Ticker 主体形状 (底部大圆角)
struct TickerMainShape: Shape {
    let side: ExpandedSide
    let isExpanded: Bool
    
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = isExpanded ? 0 : 11 // 动态切换底部圆角
        var path = Path()
        
        if side == .left {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            if r > 0 {
                path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            } else {
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            if r > 0 {
                path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            } else {
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

// 2. 反向圆角形状 (凹曲线衔接)
struct FilletShape: Shape {
    let side: ExpandedSide
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.width
        if side == .left {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX, y: rect.maxY), radius: r, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.maxX, y: rect.maxY), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}
