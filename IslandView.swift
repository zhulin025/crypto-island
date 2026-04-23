import SwiftUI

struct IslandView: View {
    @ObservedObject var service: BinanceService
    let notchInfo = NotchDetector.shared.getNotchInfo()

    var body: some View {
        let info = notchInfo
        let rect = info.hasNotch ? info.rect : NSRect(x: 0, y: 0, width: 50, height: 33)
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        
        ZStack {
            // 中间补位：在灵动岛位置放一个黑色色块，高度 33
            Color.black
                .frame(width: rect.width, height: 33)
                .position(x: rect.midX, y: 16.5)

            // 左侧 Ticker
            if let coin = service.leftCoin {
                CoinTickerView(coin: coin)
                    .frame(width: CoinDetailPanelView.tickerSideWidth, height: 33)
                    .position(x: rect.minX - CoinDetailPanelView.tickerSideWidth/2 + 26, y: 16.5)
            }
            
            // 右侧 Ticker
            if let coin = service.rightCoin {
                CoinTickerView(coin: coin)
                    .frame(width: CoinDetailPanelView.tickerSideWidth, height: 33)
                    .position(x: rect.maxX + CoinDetailPanelView.tickerSideWidth/2 - 26, y: 16.5)
            }
        }
        .frame(width: screenWidth, height: 33)
    }

    private var loadingText: some View {
        Text("Loading...")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
    }
}

// MARK: - CoinTickerView

struct CoinTickerView: View {
    let coin: Coin

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            // 主行：币种 + 价格
            HStack(spacing: 5) {
                Text(coin.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)

                Text(coin.formattedPrice)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            // 副行：涨跌幅
            Text(coin.formattedChange)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(coin.changeColor)
        }
        .frame(width: CoinDetailPanelView.tickerSideWidth, height: 33) // 调至 33
        .background(Color.black)  // 纯黑背景填充整个 130px 区域
    }
}
