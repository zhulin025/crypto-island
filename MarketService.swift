import Foundation
import Combine

class MarketService: ObservableObject {
    @Published var totalMarketCapT: Double = 0      // 单位：万亿 USD
    @Published var btcDominance: Double    = 0      // 百分比
    @Published var marketCapChange24h: Double = 0   // 24h 涨跌 %
    @Published var fearGreedIndex: Int     = 0      // 0~100
    @Published var fearGreedLabel: String  = ""     // "Fear", "Greed" 等

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        fetchGlobal()
        fetchFearGreed()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.fetchGlobal()
            self?.fetchFearGreed()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    // MARK: - CoinGecko Global

    private func fetchGlobal() {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else { return }
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .tryMap { data -> (Double, Double, Double) in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let d = json["data"] as? [String: Any] else {
                    throw URLError(.badServerResponse)
                }
                let capDict  = d["total_market_cap"] as? [String: Double] ?? [:]
                let cap      = (capDict["usd"] ?? 0) / 1e12
                let btcDict  = d["market_cap_percentage"] as? [String: Double] ?? [:]
                let btcDom   = btcDict["btc"] ?? 0
                let change   = d["market_cap_change_percentage_24h_usd"] as? Double ?? 0
                return (cap, btcDom, change)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] cap, dom, change in
                self?.totalMarketCapT = cap
                self?.btcDominance    = dom
                self?.marketCapChange24h = change
            })
            .store(in: &cancellables)
    }

    // MARK: - Fear & Greed Index (alternative.me)

    private func fetchFearGreed() {
        guard let url = URL(string: "https://api.alternative.me/fng/") else { return }
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .tryMap { data -> (Int, String) in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let arr  = json["data"] as? [[String: Any]],
                      let first = arr.first,
                      let val   = Int(first["value"] as? String ?? ""),
                      let label = first["value_classification"] as? String
                else { throw URLError(.badServerResponse) }
                return (val, label)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] idx, label in
                self?.fearGreedIndex = idx
                self?.fearGreedLabel = label
            })
            .store(in: &cancellables)
    }

    // MARK: - Formatted Helpers

    var formattedMarketCap: String {
        String(format: "$%.2fT", totalMarketCapT)
    }

    var formattedBtcDominance: String {
        String(format: "BTC %.1f%%", btcDominance)
    }

    var fearGreedColor: (r: Double, g: Double, b: Double) {
        switch fearGreedIndex {
        case 0..<25:  return (1.0, 0.25, 0.25)   // Extreme Fear - red
        case 25..<45: return (1.0, 0.55, 0.1)    // Fear - orange
        case 45..<55: return (0.8, 0.8, 0.2)     // Neutral - yellow
        case 55..<75: return (0.3, 0.85, 0.4)    // Greed - green
        default:      return (0.1, 1.0, 0.5)     // Extreme Greed - bright green
        }
    }
}
