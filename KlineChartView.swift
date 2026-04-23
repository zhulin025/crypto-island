import SwiftUI

// MARK: - Candlestick Chart

struct KlineChartView: View {
    let bars: [KlineBar]

    private var minLow:  Double { bars.map(\.low).min()  ?? 0 }
    private var maxHigh: Double { bars.map(\.high).max() ?? 1 }

    var body: some View {
        Canvas { ctx, size in
            guard bars.count >= 2 else { return }
            let lo = minLow
            let hi = maxHigh
            let range = hi - lo
            guard range > 0 else { return }

            let barWidth = size.width / CGFloat(bars.count)
            let bodyW    = max(1.5, barWidth * 0.55)

            let priceAreaH  = size.height * 0.70
            let volumeAreaH = size.height * 0.20
            let gap: CGFloat = 8

            func yFor(_ price: Double) -> CGFloat {
                let norm = CGFloat((price - lo) / range)
                // Price chart sits in the top area
                return priceAreaH - (norm * priceAreaH * 0.9 + priceAreaH * 0.05)
            }

            for (i, bar) in bars.enumerated() {
                let cx    = CGFloat(i) * barWidth + barWidth / 2
                let green = Color(red: 0.25, green: 0.85, blue: 0.45)
                let red   = Color(red: 1.0,  green: 0.35, blue: 0.35)
                let color = bar.isBullish ? green : red

                // Volume Bar (at the very bottom area)
                let maxVol = bars.map(\.volume).max() ?? 1
                let volH   = CGFloat(bar.volume / maxVol) * volumeAreaH
                let volRect = CGRect(x: cx - bodyW / 2, y: size.height - volH, width: bodyW, height: volH)
                ctx.fill(Path(volRect), with: .color(color.opacity(0.35)))

                // Wick
                let wickTop = yFor(bar.high)
                let wickBot = yFor(bar.low)
                let wickRect = CGRect(x: cx - 0.5, y: wickTop, width: 1, height: max(1, wickBot - wickTop))
                ctx.fill(Path(wickRect), with: .color(color.opacity(0.75)))

                // Body
                let bodyTop = yFor(max(bar.open, bar.close))
                let bodyBot = yFor(min(bar.open, bar.close))
                let bodyH   = max(1.5, bodyBot - bodyTop)
                let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyTop, width: bodyW, height: bodyH)
                ctx.fill(Path(bodyRect), with: .color(color))
            }
        }
    }
}

// MARK: - Timeframe Selector

struct TimeframeSelector: View {
    @Binding var selected: KlineTimeframe
    var onChange: (KlineTimeframe) -> Void


    var body: some View {
        HStack(spacing: 4) {
            ForEach(KlineTimeframe.allCases, id: \.self) { tf in
                Button(action: {
                    selected = tf
                    onChange(tf)
                }) {
                    Text(tf.rawValue)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(selected == tf ? .black : .white.opacity(0.5))
                        .frame(width: 32, height: 16)
                        .background(selected == tf ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Market Overview Bar

struct MarketOverviewBar: View {
    @ObservedObject var market: MarketService


    var body: some View {
        HStack(spacing: 10) {
            Group {
                marketChip("总市值", market.formattedMarketCap,
                           positive: market.marketCapChange24h >= 0)
                marketChip("BTC占比", market.formattedBtcDominance, positive: nil)
                if market.fearGreedIndex > 0 {
                    fearGreedChip()
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func marketChip(_ label: String, _ value: String, positive: Bool?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(chipColor(positive: positive))
        }
    }

    @ViewBuilder
    private func fearGreedChip() -> some View {
        let fg = market.fearGreedColor
        HStack(spacing: 3) {
            Text("贪婪")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.35))
            Text("\(market.fearGreedIndex)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: fg.r, green: fg.g, blue: fg.b))
        }
    }

    private func chipColor(positive: Bool?) -> Color {
        guard let p = positive else { return .white.opacity(0.7) }
        return p ? Color(red: 0.25, green: 0.85, blue: 0.45) : Color(red: 1.0, green: 0.35, blue: 0.35)
    }
}

// MARK: - Portfolio Row

struct PortfolioRowView: View {
    let holding: PortfolioHolding
    let currentPrice: Double

    var body: some View {
        let pnlPct = holding.pnlPercent(price: currentPrice)
        let pnlAbs = holding.pnl(price: currentPrice)
        let isPos  = pnlAbs >= 0
        let color: Color = isPos ? Color(red: 0.25, green: 0.85, blue: 0.45) : Color(red: 1.0, green: 0.35, blue: 0.35)
        let sign = isPos ? "+" : ""

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("持仓 \(holding.symbol)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Text("\(String(format: "%.4f", holding.quantity)) 枚")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("$\(formatValue(holding.currentValue(price: currentPrice)))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Text("\(sign)\(String(format: "%.2f", pnlPct))%  \(sign)$\(formatValue(abs(pnlAbs)))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.04))
        .cornerRadius(5)
        .padding(.horizontal, 10)
    }

    private func formatValue(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0f", v) }
        if v >= 1    { return String(format: "%.2f", v) }
        return String(format: "%.4f", v)
    }
}
