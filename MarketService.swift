import Foundation

final class MarketService: ObservableObject {
    @Published var totalMarketCapT: Double = 0
    @Published var btcDominance: Double = 0
    @Published var marketCapChange24h: Double = 0
    @Published var fearGreedIndex: Int = 0
    @Published var fearGreedLabel: String = ""

    private let session: URLSession
    private var timer: Timer?
    private var isRunning = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        fetchGlobal()
        fetchFearGreed()
    }

    private func fetchGlobal() {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let d = json["data"] as? [String: Any]
            else { return }

            let capDict = d["total_market_cap"] as? [String: Double] ?? [:]
            let cap = (capDict["usd"] ?? 0) / 1e12
            let btcDict = d["market_cap_percentage"] as? [String: Double] ?? [:]
            let btcDom = btcDict["btc"] ?? 0
            let change = d["market_cap_change_percentage_24h_usd"] as? Double ?? 0

            DispatchQueue.main.async {
                self.totalMarketCapT = cap
                self.btcDominance = btcDom
                self.marketCapChange24h = change
            }
        }.resume()
    }

    private func fetchFearGreed() {
        guard let url = URL(string: "https://api.alternative.me/fng/") else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let arr = json["data"] as? [[String: Any]],
                let first = arr.first,
                let val = Int(first["value"] as? String ?? ""),
                let label = first["value_classification"] as? String
            else { return }

            DispatchQueue.main.async {
                self.fearGreedIndex = val
                self.fearGreedLabel = label
            }
        }.resume()
    }

    var formattedMarketCap: String {
        String(format: "$%.2fT", totalMarketCapT)
    }

    var formattedBtcDominance: String {
        String(format: "BTC %.1f%%", btcDominance)
    }

    var fearGreedColor: (r: Double, g: Double, b: Double) {
        switch fearGreedIndex {
        case 0..<25: return (1.0, 0.25, 0.25)
        case 25..<45: return (1.0, 0.55, 0.1)
        case 45..<55: return (0.8, 0.8, 0.2)
        case 55..<75: return (0.3, 0.85, 0.4)
        default: return (0.1, 1.0, 0.5)
        }
    }
}
