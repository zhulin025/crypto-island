import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandInteractionState
    @ObservedObject var service: BinanceService
    let notchInfo = NotchDetector.shared.getNotchInfo()

    var body: some View {
        let info = notchInfo
        let rect = info.hasNotch ? info.rect : NSRect(x: 0, y: 0, width: 50, height: 33)
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let tickerW = CoinDetailPanelView.tickerSideWidth
        
        ZStack {
            // 中间补位 (灵动岛主体)
            Color.black
                .frame(width: rect.width, height: 33)
                .position(x: rect.midX, y: 16.5)

            // 左侧 Ticker
            Group {
                if state.isPrivacyMode {
                    PrivacySideView(side: .left, state: state)
                } else if let coin = service.leftCoin {
                    CoinTickerView(coin: coin, side: .left, state: state)
                } else {
                    LoadingTickerView(side: .left)
                }
            }
            .frame(width: tickerW + 20, height: 33) // 增加宽度以容纳反向圆角
            .position(x: rect.minX - (tickerW + 20)/2 + 26 + 10, y: 16.5)
            
            // 右侧 Ticker
            Group {
                if state.isPrivacyMode {
                    PrivacySideView(side: .right, state: state)
                } else if let coin = service.rightCoin {
                    CoinTickerView(coin: coin, side: .right, state: state)
                } else {
                    LoadingTickerView(side: .right)
                }
            }
            .frame(width: tickerW + 20, height: 33)
            .position(x: rect.maxX + (tickerW + 20)/2 - 26 - 10, y: 16.5)
        }
        .frame(width: screenWidth, height: 33)
    }
}

// MARK: - Loading Ticker

struct LoadingTickerView: View {
    let side: ExpandedSide
    var body: some View {
        ZStack(alignment: side == .left ? .trailing : .leading) {
            Text("...")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: CoinDetailPanelView.tickerSideWidth, height: 33)
                .background(Color.black)
                .clipShape(TickerMainShape(side: side, isExpanded: false))
                
            FilletShape(side: side)
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .offset(x: side == .left ? -CoinDetailPanelView.tickerSideWidth : CoinDetailPanelView.tickerSideWidth, y: -10.5)
        }
    }
}

// MARK: - CoinTickerView

struct CoinTickerView: View {
    let coin: Coin
    let side: ExpandedSide
    @ObservedObject var state: IslandInteractionState

    var body: some View {
        let isExpanded = state.expandedSide != .none
        let tickerW = CoinDetailPanelView.tickerSideWidth
        
        ZStack(alignment: side == .left ? .trailing : .leading) {
            // 真正的内容区域 (130px)
            HStack(spacing: 0) {
                if side == .right { Spacer() }
                
                VStack(alignment: side == .left ? .leading : .trailing, spacing: 1) {
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
                .padding(.horizontal, 10)
                
                if side == .left { Spacer() }
            }
            .frame(width: tickerW, height: 33)
            .background(Color.black)
            .clipShape(TickerMainShape(side: side, isExpanded: isExpanded))
            
            // 额外的反向圆角衔接块 (始终显示)
            FilletShape(side: side)
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .offset(x: side == .left ? -tickerW : tickerW, y: -10.5)
        }
    }
}

// 1. Ticker 主体形状 (底部大圆角)
struct TickerMainShape: Shape {
    let side: ExpandedSide
    let isExpanded: Bool
    
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = isExpanded ? 0 : 11 // 底部圆角
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

// MARK: - Privacy Mode Subviews

struct PrivacySideView: View {
    let side: ExpandedSide
    @ObservedObject var state: IslandInteractionState

    var body: some View {
        let tickerW = CoinDetailPanelView.tickerSideWidth
        ZStack(alignment: side == .left ? .trailing : .leading) {
            HStack(spacing: 0) {
                if side == .right { Spacer() }
                Group {
                    if side == .left {
                        AsciiAnimationView()
                    } else {
                        WeatherMiniView()
                    }
                }
                .padding(.horizontal, 10)
                if side == .left { Spacer() }
            }
            .frame(width: tickerW, height: 33)
            .background(Color.black)
            .clipShape(TickerMainShape(side: side, isExpanded: false))

            FilletShape(side: side)
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .offset(x: side == .left ? -tickerW : tickerW, y: -10.5)
        }
    }
}

struct AsciiAnimationView: View {
    @State private var frame: Int = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    private let catFrames = [
        "(=^.^=)",
        "(=^. .^=)",
        "(=-.-=)",
        "(=^·^=)"
    ]

    var body: some View {
        Text(catFrames[frame % catFrames.count])
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
            .onReceive(timer) { _ in
                frame += 1
            }
    }
}

struct WeatherMiniView: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text("北京")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            Text("24°C")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}
