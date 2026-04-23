import SwiftUI

// MARK: - Panel Window Wrapper（NSWindow 在 AppDelegate 创建）

struct CoinDetailPanelView: View {
    @ObservedObject var state: IslandInteractionState
    @ObservedObject var service: BinanceService
    @ObservedObject var market: MarketService
    let holdings: [PortfolioHolding]

    static let tickerSideWidth: CGFloat = 130
    static let tickerOffset: CGFloat = 26
    static var panelWidth: CGFloat {
        let notchInfo = NotchDetector.shared.getNotchInfo()
        let notchW = notchInfo.hasNotch ? notchInfo.rect.width : 179
        return notchW + (tickerSideWidth - tickerOffset) * 2
    }
    static let panelHeight: CGFloat = 230

    // Kline state (local to panel)
    @State private var klineBars:     [KlineBar] = []
    @State private var isLoadingKlines = false

    private var currentCoin: Coin? {
        switch state.expandedSide {
        case .left:  return service.leftCoin
        case .right: return service.rightCoin
        case .none:  return nil
        }
    }

    private var currentHistory: [Double] {
        switch state.expandedSide {
        case .left:  return service.leftPriceHistory
        case .right: return service.rightPriceHistory
        case .none:  return []
        }
    }

    private var currentCryptoCoin: CryptoCoin? {
        guard let coin = currentCoin else { return nil }
        let sym = coin.symbol.lowercased()
        // 先从 watchlist 找，再从预设找
        return service.carouselWatchlist.first { $0.id == sym || $0.binanceSymbol.lowercased().hasPrefix(sym) }
            ?? CryptoCoin.presets.first { $0.id == sym }
            ?? CryptoCoin.custom(symbol: coin.symbol)
    }

    private var currentHolding: PortfolioHolding? {
        guard let coin = currentCoin else { return nil }
        return holdings.first { $0.symbol.uppercased() == coin.symbol.uppercased() }
    }

    var body: some View {
        ZStack {
            if state.expandedSide != .none, let coin = currentCoin {
                panelContent(coin: coin)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.expandedSide)
        .frame(width: CoinDetailPanelView.panelWidth,
               height: CoinDetailPanelView.panelHeight)
        .onChange(of: state.expandedSide) { side in
            if side != .none, let coin = currentCoin {
                loadKlines(for: coin)
            } else {
                klineBars = []
            }
        }
        .onChange(of: state.selectedTimeframe) { _ in
            if let coin = currentCoin { loadKlines(for: coin) }
        }
    }

    // MARK: - Panel content

    @ViewBuilder
    private func panelContent(coin: Coin) -> some View {
        ZStack(alignment: .topLeading) {
            IslandDropShape(radius: 14)
                .fill(Color.black)

            VStack(alignment: .leading, spacing: 0) {

                // Row 1：币种 + 价格
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coin.symbol)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text(coinFullName(coin.symbol))
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.38))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$\(coin.formattedPrice)")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        Text(coin.formattedChange)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(coin.changeColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Row 2：H / L / Vol + timeframe selector
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        if let h = coin.high24h { statChip("H", coin.formattedHL(h), color: Color(red: 0.25, green: 0.85, blue: 0.45)) }
                        if let l = coin.low24h  { statChip("L", coin.formattedHL(l), color: Color(red: 1.0, green: 0.35, blue: 0.35)) }
                        if let v = coin.formattedVolume { statChip("Vol", v, color: .white.opacity(0.42)) }
                    }
                    Spacer()
                    TimeframeSelector(selected: $state.selectedTimeframe) { _ in }
                        .padding(.trailing, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                // Row 3：K线图 or 走势图
                Group {
                    if isLoadingKlines {
                        HStack {
                            Spacer()
                            Text("加载中…")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                        }
                        .frame(height: 70)
                    } else if klineBars.count >= 4 {
                        KlineChartView(bars: klineBars)
                            .frame(height: 70)
                            .padding(.horizontal, 12)
                    } else if currentHistory.count >= 4 {
                        SparklineView(prices: currentHistory)
                            .frame(height: 70)
                            .padding(.horizontal, 16)
                    } else {
                        HStack {
                            Spacer()
                            Text("正在收集价格数据…")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.25))
                            Spacer()
                        }
                        .frame(height: 70)
                    }
                }
                .padding(.top, 6)

                // Row 4：持仓信息（如有）
                if let holding = currentHolding {
                    PortfolioRowView(holding: holding, currentPrice: coin.price)
                        .padding(.top, 4)
                }

                Spacer(minLength: 4)

                // Row 5：全局市场行情
                if market.totalMarketCapT > 0 {
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.horizontal, 16)
                    MarketOverviewBar(market: market)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .padding(.top, 4)
                } else {
                    Spacer(minLength: 8)
                }
            }
        }
    }

    // MARK: - Kline Loading

    private func loadKlines(for coin: Coin) {
        guard let cryptoCoin = currentCryptoCoin else {
            // Fallback: construct from symbol
            let fallback = CryptoCoin.presets.first { $0.id == coin.symbol.lowercased() }
                ?? CryptoCoin.custom(symbol: coin.symbol)
            fetchKlines(cryptoCoin: fallback)
            return
        }
        fetchKlines(cryptoCoin: cryptoCoin)
    }

    private func fetchKlines(cryptoCoin: CryptoCoin) {
        isLoadingKlines = true
        klineBars = []
        service.fetchKlines(coin: cryptoCoin, timeframe: state.selectedTimeframe) { bars in
            self.klineBars = bars
            self.isLoadingKlines = false
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func statChip(_ key: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func coinFullName(_ symbol: String) -> String {
        let s = symbol.lowercased()
        return CryptoCoin.presets.first {
            $0.id == s || $0.binanceSymbol.lowercased().hasPrefix(s)
        }?.displayName ?? symbol
    }
}

// MARK: - Sparkline (保留原有走势图)

struct SparklineView: View {
    let prices: [Double]

    private var trendColor: Color {
        guard prices.count >= 2 else { return .gray }
        return prices.last! >= prices.first!
            ? Color(red: 0.25, green: 0.85, blue: 0.45)
            : Color(red: 1.0, green: 0.35, blue: 0.35)
    }

    var body: some View {
        Canvas { ctx, size in
            guard prices.count >= 2 else { return }
            let minP = prices.min()!
            let maxP = prices.max()!
            let range = maxP - minP

            func y(for price: Double) -> CGFloat {
                guard range > 0 else { return size.height / 2 }
                let normalized = CGFloat((price - minP) / range)
                return size.height - (normalized * size.height * 0.90 + size.height * 0.05)
            }

            let step = size.width / CGFloat(prices.count - 1)

            var fillPath = Path()
            fillPath.move(to: CGPoint(x: 0, y: size.height))
            for (i, price) in prices.enumerated() {
                fillPath.addLine(to: CGPoint(x: CGFloat(i) * step, y: y(for: price)))
            }
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()
            ctx.fill(fillPath, with: .color(trendColor.opacity(0.12)))

            var linePath = Path()
            for (i, price) in prices.enumerated() {
                let pt = CGPoint(x: CGFloat(i) * step, y: y(for: price))
                if i == 0 { linePath.move(to: pt) } else { linePath.addLine(to: pt) }
            }
            ctx.stroke(linePath, with: .color(trendColor), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            if let last = prices.last {
                let lastX = CGFloat(prices.count - 1) * step
                let lastY = y(for: last)
                ctx.fill(Path(ellipseIn: CGRect(x: lastX - 2.5, y: lastY - 2.5, width: 5, height: 5)),
                         with: .color(trendColor))
            }
        }
    }
}

// MARK: - Shape：顶角直角，底角圆角

struct IslandDropShape: Shape {
    var radius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                     radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                     radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
        }
    }
}
