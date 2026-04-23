import Foundation
import SwiftUI

// MARK: - Coin

struct Coin: Identifiable, Codable {
    let id: String
    var symbol: String
    var price: Double
    var priceChangePercent: Double
    var high24h: Double?
    var low24h: Double?
    var volume24h: Double?
    var lastUpdate: Date

    var formattedPrice: String {
        if price >= 10000  { return String(format: "%.0f", price) }
        if price >= 1000   { return String(format: "%.1f", price) }
        if price >= 1.0    { return String(format: "%.2f", price) }
        if price >= 0.0001 { return String(format: "%.5f", price) }
        return String(format: "%.8f", price)
    }

    func formattedHL(_ value: Double) -> String {
        if value >= 10000  { return String(format: "%.0f", value) }
        if value >= 1000   { return String(format: "%.1f", value) }
        if value >= 1.0    { return String(format: "%.2f", value) }
        if value >= 0.0001 { return String(format: "%.5f", value) }
        return String(format: "%.8f", value)
    }

    var formattedChange: String {
        let sign = priceChangePercent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", priceChangePercent))%"
    }

    var formattedVolume: String? {
        guard let vol = volume24h, vol > 0 else { return nil }
        if vol >= 1_000_000_000 { return String(format: "$%.1fB", vol / 1_000_000_000) }
        if vol >= 1_000_000     { return String(format: "$%.1fM", vol / 1_000_000) }
        if vol >= 1_000         { return String(format: "$%.1fK", vol / 1_000) }
        return String(format: "$%.0f", vol)
    }

    var changeColor: Color {
        priceChangePercent >= 0 ? Color(red: 0.2, green: 0.9, blue: 0.4) : Color(red: 1.0, green: 0.3, blue: 0.3)
    }
}

// MARK: - Kline

struct KlineBar: Identifiable {
    var id: Date { time }
    let open, high, low, close: Double
    let volume: Double
    let time: Date
    var isBullish: Bool { close >= open }
}

enum KlineTimeframe: String, CaseIterable, Codable {
    case h1 = "1H"
    case h4 = "4H"
    case d1 = "1D"

    var binanceInterval: String {
        switch self {
        case .h1: return "1h"
        case .h4: return "4h"
        case .d1: return "1d"
        }
    }

    var okxBar: String {
        switch self {
        case .h1: return "1H"
        case .h4: return "4H"
        case .d1: return "1Dutc"
        }
    }
}

// MARK: - Portfolio

struct PortfolioHolding: Codable, Identifiable {
    var id = UUID()
    var coinId: String
    var symbol: String
    var quantity: Double
    var avgCostUSD: Double

    func currentValue(price: Double) -> Double { quantity * price }
    func pnl(price: Double) -> Double { (price - avgCostUSD) * quantity }
    func pnlPercent(price: Double) -> Double {
        guard avgCostUSD > 0 else { return 0 }
        return (price - avgCostUSD) / avgCostUSD * 100
    }
}

// MARK: - Island Interaction State

enum ExpandedSide: Equatable {
    case none, left, right
}

class IslandInteractionState: ObservableObject {
    @Published var expandedSide: ExpandedSide = .none
    @Published var selectedTimeframe: KlineTimeframe = .h1
}

// MARK: - Data Source

enum DataSource: String, Codable, CaseIterable {
    case binance   = "Binance (实时WebSocket)"
    case okx       = "OKX (实时WebSocket)"
    case coingecko = "CoinGecko (稳定轮询)"
    case gate      = "Gate.io (实时WebSocket)"
}

// MARK: - CryptoCoin

struct CryptoCoin: Codable, Hashable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var binanceSymbol: String
    var okxSymbol: String
    var coinGeckoId: String
    var isCustom: Bool = false

    var gateSymbol: String { okxSymbol.replacingOccurrences(of: "-", with: "_") }

    static func == (lhs: CryptoCoin, rhs: CryptoCoin) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func custom(symbol: String) -> CryptoCoin {
        let s = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        return CryptoCoin(id: "custom_\(s)", displayName: s,
                          binanceSymbol: "\(s)USDT", okxSymbol: "\(s)-USDT",
                          coinGeckoId: s.lowercased(), isCustom: true)
    }

    // swiftlint:disable line_length
    static let presets: [CryptoCoin] = [
        .init(id: "btc",  displayName: "Bitcoin (BTC)",      binanceSymbol: "BTCUSDT",  okxSymbol: "BTC-USDT",  coinGeckoId: "bitcoin"),
        .init(id: "eth",  displayName: "Ethereum (ETH)",     binanceSymbol: "ETHUSDT",  okxSymbol: "ETH-USDT",  coinGeckoId: "ethereum"),
        .init(id: "sol",  displayName: "Solana (SOL)",       binanceSymbol: "SOLUSDT",  okxSymbol: "SOL-USDT",  coinGeckoId: "solana"),
        .init(id: "bnb",  displayName: "BNB",                binanceSymbol: "BNBUSDT",  okxSymbol: "BNB-USDT",  coinGeckoId: "binancecoin"),
        .init(id: "xrp",  displayName: "XRP",                binanceSymbol: "XRPUSDT",  okxSymbol: "XRP-USDT",  coinGeckoId: "ripple"),
        .init(id: "doge", displayName: "Dogecoin (DOGE)",    binanceSymbol: "DOGEUSDT", okxSymbol: "DOGE-USDT", coinGeckoId: "dogecoin"),
        .init(id: "ada",  displayName: "Cardano (ADA)",      binanceSymbol: "ADAUSDT",  okxSymbol: "ADA-USDT",  coinGeckoId: "cardano"),
        .init(id: "avax", displayName: "Avalanche (AVAX)",   binanceSymbol: "AVAXUSDT", okxSymbol: "AVAX-USDT", coinGeckoId: "avalanche-2"),
        .init(id: "link", displayName: "Chainlink (LINK)",   binanceSymbol: "LINKUSDT", okxSymbol: "LINK-USDT", coinGeckoId: "chainlink"),
        .init(id: "dot",  displayName: "Polkadot (DOT)",     binanceSymbol: "DOTUSDT",  okxSymbol: "DOT-USDT",  coinGeckoId: "polkadot"),
        .init(id: "sui",  displayName: "Sui (SUI)",          binanceSymbol: "SUIUSDT",  okxSymbol: "SUI-USDT",  coinGeckoId: "sui"),
        .init(id: "trx",  displayName: "TRON (TRX)",         binanceSymbol: "TRXUSDT",  okxSymbol: "TRX-USDT",  coinGeckoId: "tron"),
        .init(id: "uni",  displayName: "Uniswap (UNI)",      binanceSymbol: "UNIUSDT",  okxSymbol: "UNI-USDT",  coinGeckoId: "uniswap"),
        .init(id: "pepe", displayName: "PEPE",               binanceSymbol: "PEPEUSDT", okxSymbol: "PEPE-USDT", coinGeckoId: "pepe"),
        .init(id: "pol",  displayName: "Polygon (POL)",      binanceSymbol: "POLUSDT",  okxSymbol: "POL-USDT",  coinGeckoId: "matic-network"),
        .init(id: "shib", displayName: "Shiba Inu (SHIB)",   binanceSymbol: "SHIBUSDT", okxSymbol: "SHIB-USDT", coinGeckoId: "shiba-inu"),
        .init(id: "ltc",  displayName: "Litecoin (LTC)",     binanceSymbol: "LTCUSDT",  okxSymbol: "LTC-USDT",  coinGeckoId: "litecoin"),
        .init(id: "atom", displayName: "Cosmos (ATOM)",      binanceSymbol: "ATOMUSDT", okxSymbol: "ATOM-USDT", coinGeckoId: "cosmos"),
        .init(id: "op",   displayName: "Optimism (OP)",      binanceSymbol: "OPUSDT",   okxSymbol: "OP-USDT",   coinGeckoId: "optimism"),
        .init(id: "arb",  displayName: "Arbitrum (ARB)",     binanceSymbol: "ARBUSDT",  okxSymbol: "ARB-USDT",  coinGeckoId: "arbitrum"),
    ]
    // swiftlint:enable line_length
}

// MARK: - Price Alert

struct PriceAlert: Codable, Identifiable {
    var id: UUID = UUID()
    var coinSymbol: String
    var threshold: Double
    var alertType: AlertType
    var isActive: Bool = true

    enum AlertType: String, Codable, CaseIterable {
        case above = "高于"
        case below = "低于"
    }
}

// MARK: - App Config

struct AppConfig: Codable {
    var leftCoin: CryptoCoin         = CryptoCoin.presets[0]
    var rightCoin: CryptoCoin        = CryptoCoin.presets[1]
    var watchlist: [CryptoCoin]      = Array(CryptoCoin.presets.prefix(6))
    var carouselEnabled: Bool        = false
    var carouselInterval: Double     = 5.0
    var dataSource: DataSource       = .okx
    var priceAlerts: [PriceAlert]    = []
    var launchAtLogin: Bool          = false
    var holdings: [PortfolioHolding] = []

    // Graceful decoding for new fields (backward compatible with old saved config)
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leftCoin         = (try? c.decode(CryptoCoin.self,         forKey: .leftCoin))         ?? CryptoCoin.presets[0]
        rightCoin        = (try? c.decode(CryptoCoin.self,         forKey: .rightCoin))        ?? CryptoCoin.presets[1]
        watchlist        = (try? c.decode([CryptoCoin].self,        forKey: .watchlist))        ?? [leftCoin, rightCoin]
        carouselEnabled  = (try? c.decode(Bool.self,               forKey: .carouselEnabled))  ?? false
        carouselInterval = (try? c.decode(Double.self,             forKey: .carouselInterval)) ?? 5.0
        dataSource       = (try? c.decode(DataSource.self,         forKey: .dataSource))       ?? .okx
        priceAlerts      = (try? c.decode([PriceAlert].self,       forKey: .priceAlerts))      ?? []
        launchAtLogin    = (try? c.decode(Bool.self,               forKey: .launchAtLogin))    ?? false
        holdings         = (try? c.decode([PortfolioHolding].self, forKey: .holdings))         ?? []
    }
}
