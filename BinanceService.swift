import Foundation
import Combine
import UserNotifications

class BinanceService: ObservableObject {
    @Published var leftCoin: Coin?
    @Published var rightCoin: Coin?
    @Published var errorMessage: String?

    // 价格历史，最多保留 120 条（约 2 分钟的实时数据）
    @Published var leftPriceHistory: [Double] = []
    @Published var rightPriceHistory: [Double] = []
    private let maxHistory = 120

    // 外部回调
    var onAlertTriggered: ((UUID) -> Void)?
    var onAutoSwitchDataSource: ((DataSource) -> Void)?

    private var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var config: AppConfig?
    private var timer: Timer?

    // Binance 端点：data-stream.binance.vision 是 CDN 加速节点，最稳定
    private let binanceWsHosts = [
        "data-stream.binance.vision",
        "stream.binance.vision:9443",
        "stream.binance.com:9443",
        "stream.binance.me:9443",
    ]
    private let binanceRestHosts = [
        "api.binance.com",
        "api1.binance.com",
        "api2.binance.com",
        "api.binance.me",
    ]
    private var binanceWsIndex = 0
    private var binanceRestIndex = 0
    private var consecutiveBinanceFailures = 0
    private var alreadyAutoSwitched = false

    // OKX
    private var okxTask: URLSessionWebSocketTask?
    private var okxPingTimer: Timer?
    private var okxLeftSymbol = ""
    private var okxRightSymbol = ""

    // 防止对同一个 alert 重复触发
    private var firedAlertIds = Set<UUID>()

    // MARK: - Public

    func startTracking(config: AppConfig) {
        self.config = config
        self.leftCoin = nil
        self.rightCoin = nil
        self.errorMessage = nil
        consecutiveBinanceFailures = 0
        alreadyAutoSwitched = false
        firedAlertIds.removeAll()
        leftPriceHistory.removeAll()
        rightPriceHistory.removeAll()

        NSLog("CryptoIsland: startTracking \(config.leftCoin.id)/\(config.rightCoin.id) via \(config.dataSource.rawValue)")
        stopTracking()

        switch config.dataSource {
        case .binance:
            connectBinance(symbol: config.leftCoin.binanceSymbol, isLeft: true)
            connectBinance(symbol: config.rightCoin.binanceSymbol, isLeft: false)
            fetchBinanceREST(symbol: config.leftCoin.binanceSymbol, isLeft: true)
            fetchBinanceREST(symbol: config.rightCoin.binanceSymbol, isLeft: false)

        case .okx:
            connectOKX(config: config)
            fetchOKXREST(symbol: config.leftCoin.okxSymbol, isLeft: true)
            fetchOKXREST(symbol: config.rightCoin.okxSymbol, isLeft: false)

        case .coingecko:
            fetchCoinGecko()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.fetchCoinGecko()
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    func stopTracking() {
        webSocketTasks.values.forEach { $0.cancel(with: .goingAway, reason: nil) }
        webSocketTasks.removeAll()
        okxTask?.cancel(with: .goingAway, reason: nil)
        okxTask = nil
        okxPingTimer?.invalidate()
        okxPingTimer = nil
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Binance WebSocket

    private func connectBinance(symbol: String, isLeft: Bool) {
        let host = binanceWsHosts[binanceWsIndex % binanceWsHosts.count]
        let urlStr = "wss://\(host)/ws/\(symbol.lowercased())@ticker"
        guard let url = URL(string: urlStr) else { return }

        NSLog("CryptoIsland: Binance WS → \(urlStr)")
        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTasks[symbol] = task
        task.resume()
        receiveBinance(task: task, symbol: symbol, isLeft: isLeft)
    }

    private func receiveBinance(task: URLSessionWebSocketTask, symbol: String, isLeft: Bool) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                consecutiveBinanceFailures = 0
                if case .string(let text) = msg { parseBinanceTicker(text, isLeft: isLeft) }
                receiveBinance(task: task, symbol: symbol, isLeft: isLeft)

            case .failure(let error):
                let code = (error as NSError).code
                NSLog("CryptoIsland: Binance WS error \(symbol) code=\(code)")
                consecutiveBinanceFailures += 1

                // 连续失败 3 次：轮换端点；失败 6 次：自动切换 OKX
                if consecutiveBinanceFailures % 3 == 0 {
                    binanceWsIndex = (binanceWsIndex + 1) % binanceWsHosts.count
                    NSLog("CryptoIsland: 切换到Binance端点 \(binanceWsHosts[binanceWsIndex])")
                }
                if consecutiveBinanceFailures >= 6 && !alreadyAutoSwitched {
                    alreadyAutoSwitched = true
                    NSLog("CryptoIsland: Binance连续失败\(consecutiveBinanceFailures)次，自动切换OKX")
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let cfg = self.config else { return }
                        self.errorMessage = "已自动切换至 OKX"
                        self.onAutoSwitchDataSource?(.okx)
                        self.connectOKX(config: cfg)
                        self.fetchOKXREST(symbol: cfg.leftCoin.okxSymbol, isLeft: true)
                        self.fetchOKXREST(symbol: cfg.rightCoin.okxSymbol, isLeft: false)
                    }
                    return  // 不再重试 Binance
                }

                DispatchQueue.main.async { self.errorMessage = "Binance连接失败(\(code))" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, self.config?.dataSource == .binance else { return }
                    self.connectBinance(symbol: symbol, isLeft: isLeft)
                }
            }
        }
    }

    private func parseBinanceTicker(_ text: String, isLeft: Bool) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = json["c"] as? String, let price = Double(priceStr),
              let changeStr = json["P"] as? String, let change = Double(changeStr),
              let symbol = json["s"] as? String else { return }

        let high   = (json["h"] as? String).flatMap { Double($0) }
        let low    = (json["l"] as? String).flatMap { Double($0) }
        let volume = (json["q"] as? String).flatMap { Double($0) }   // 24h 成交量 (USDT)

        DispatchQueue.main.async {
            self.errorMessage = nil
            let coin = Coin(id: symbol,
                            symbol: symbol.replacingOccurrences(of: "USDT", with: ""),
                            price: price, priceChangePercent: change,
                            high24h: high, low24h: low, volume24h: volume, lastUpdate: Date())
            if isLeft { self.leftCoin = coin; self.appendHistory(price, isLeft: true) }
            else       { self.rightCoin = coin; self.appendHistory(price, isLeft: false) }
            self.checkAlerts(for: coin)
        }
    }

    private func fetchBinanceREST(symbol: String, isLeft: Bool) {
        let host = binanceRestHosts[binanceRestIndex % binanceRestHosts.count]
        let urlStr = "https://\(host)/api/v3/ticker/24hr?symbol=\(symbol.uppercased())"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTaskPublisher(for: req)
            .map(\.data)
            .decode(type: BinanceTickerResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] c in
                if case .failure(let e) = c {
                    NSLog("CryptoIsland: Binance REST error \(symbol): \(e)")
                    self?.binanceRestIndex += 1
                }
            }, receiveValue: { [weak self] r in
                self?.errorMessage = nil
                let coin = Coin(id: r.symbol,
                                symbol: r.symbol.replacingOccurrences(of: "USDT", with: ""),
                                price: Double(r.lastPrice) ?? 0,
                                priceChangePercent: Double(r.priceChangePercent) ?? 0,
                                high24h: Double(r.highPrice),
                                low24h: Double(r.lowPrice),
                                lastUpdate: Date())
                if isLeft { self?.leftCoin = coin } else { self?.rightCoin = coin }
            })
            .store(in: &cancellables)
    }

    // MARK: - OKX WebSocket

    private func connectOKX(config: AppConfig) {
        okxLeftSymbol  = config.leftCoin.okxSymbol
        okxRightSymbol = config.rightCoin.okxSymbol

        guard let url = URL(string: "wss://ws.okx.com:8443/ws/v5/public") else { return }
        NSLog("CryptoIsland: OKX WS → \(okxLeftSymbol) / \(okxRightSymbol)")

        let task = URLSession.shared.webSocketTask(with: url)
        okxTask = task
        task.resume()

        let sub = """
        {"op":"subscribe","args":[{"channel":"tickers","instId":"\(okxLeftSymbol)"},{"channel":"tickers","instId":"\(okxRightSymbol)"}]}
        """
        task.send(.string(sub)) { err in
            if let err { NSLog("CryptoIsland: OKX subscribe error: \(err)") }
        }

        receiveOKX(task: task)

        // OKX 要求每 25s 发一次 ping 保活
        okxPingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.okxTask?.send(.string("ping")) { _ in }
        }
        RunLoop.main.add(okxPingTimer!, forMode: .common)
    }

    private func receiveOKX(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg, text != "pong" { parseOKXTicker(text) }
                receiveOKX(task: task)
            case .failure(let error):
                let code = (error as NSError).code
                NSLog("CryptoIsland: OKX WS error code=\(code)")
                DispatchQueue.main.async { self.errorMessage = "OKX连接失败(\(code))" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, let cfg = self.config, cfg.dataSource == .okx else { return }
                    self.connectOKX(config: cfg)
                }
            }
        }
    }

    private func parseOKXTicker(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let t = dataArr.first,
              let instId   = t["instId"]   as? String,
              let lastStr  = t["last"]     as? String, let last   = Double(lastStr),
              let openStr  = t["open24h"]  as? String, let open24 = Double(openStr),
              open24 > 0 else { return }

        let change = (last - open24) / open24 * 100
        let high   = (t["high24h"]   as? String).flatMap { Double($0) }
        let low    = (t["low24h"]    as? String).flatMap { Double($0) }
        let volume = (t["volCcy24h"] as? String).flatMap { Double($0) }  // 24h 成交量 (USDT)
        let sym    = instId.components(separatedBy: "-").first ?? instId
        let isLeft = instId == okxLeftSymbol

        DispatchQueue.main.async {
            self.errorMessage = nil
            let coin = Coin(id: instId, symbol: sym, price: last,
                            priceChangePercent: change, high24h: high, low24h: low,
                            volume24h: volume, lastUpdate: Date())
            if isLeft { self.leftCoin = coin; self.appendHistory(last, isLeft: true) }
            else       { self.rightCoin = coin; self.appendHistory(last, isLeft: false) }
            self.checkAlerts(for: coin)
        }
    }

    private func fetchOKXREST(symbol: String, isLeft: Bool) {
        let urlStr = "https://www.okx.com/api/v5/market/ticker?instId=\(symbol)"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTaskPublisher(for: req)
            .map(\.data)
            .tryMap { data -> Coin in
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let arr = json["data"] as? [[String: Any]], let t = arr.first,
                      let instId  = t["instId"]  as? String,
                      let lastStr = t["last"]    as? String, let last = Double(lastStr),
                      let openStr = t["open24h"] as? String, let open = Double(openStr),
                      open > 0
                else { throw URLError(.badServerResponse) }
                let change = (last - open) / open * 100
                let high   = (t["high24h"] as? String).flatMap { Double($0) }
                let low    = (t["low24h"]  as? String).flatMap { Double($0) }
                let sym    = instId.components(separatedBy: "-").first ?? instId
                return Coin(id: instId, symbol: sym, price: last, priceChangePercent: change,
                            high24h: high, low24h: low, lastUpdate: Date())
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { c in
                if case .failure(let e) = c { NSLog("CryptoIsland: OKX REST error \(symbol): \(e)") }
            }, receiveValue: { [weak self] coin in
                self?.errorMessage = nil
                if isLeft { self?.leftCoin = coin } else { self?.rightCoin = coin }
            })
            .store(in: &cancellables)
    }

    // MARK: - CoinGecko

    private func fetchCoinGecko() {
        guard let config else { return }
        let leftId  = config.leftCoin.coinGeckoId
        let rightId = config.rightCoin.coinGeckoId
        let ids = [leftId, rightId].joined(separator: ",")
        let urlStr = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=\(ids)&order=market_cap_desc&per_page=2&page=1&sparkline=false"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTaskPublisher(for: req)
            .map(\.data)
            .decode(type: [CoinGeckoMarketItem].self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] c in
                if case .failure(let e) = c {
                    NSLog("CryptoIsland: CoinGecko error: \(e)")
                    self?.errorMessage = "CoinGecko连接失败"
                }
            }, receiveValue: { [weak self] items in
                guard let self else { return }
                self.errorMessage = nil
                for item in items {
                    let sym = item.symbol.uppercased()
                    let coin = Coin(id: item.id, symbol: sym,
                                   price: item.currentPrice,
                                   priceChangePercent: item.priceChangePercentage24h ?? 0,
                                   high24h: item.high24h, low24h: item.low24h,
                                   volume24h: item.totalVolume,
                                   lastUpdate: Date())
                    if item.id == leftId  {
                        self.leftCoin = coin
                        self.appendHistory(item.currentPrice, isLeft: true)
                        self.checkAlerts(for: coin)
                    }
                    if item.id == rightId {
                        self.rightCoin = coin
                        self.appendHistory(item.currentPrice, isLeft: false)
                        self.checkAlerts(for: coin)
                    }
                }
            })
            .store(in: &cancellables)
    }

    // MARK: - Price History

    private func appendHistory(_ price: Double, isLeft: Bool) {
        if isLeft {
            leftPriceHistory.append(price)
            if leftPriceHistory.count > maxHistory { leftPriceHistory.removeFirst() }
        } else {
            rightPriceHistory.append(price)
            if rightPriceHistory.count > maxHistory { rightPriceHistory.removeFirst() }
        }
    }

    // MARK: - Price Alerts

    private func checkAlerts(for coin: Coin) {
        guard let config else { return }
        let sym = coin.symbol.uppercased()
        for alert in config.priceAlerts where alert.isActive && !firedAlertIds.contains(alert.id) {
            guard alert.coinSymbol.uppercased() == sym else { continue }
            let hit = alert.alertType == .above
                ? coin.price >= alert.threshold
                : coin.price <= alert.threshold
            if hit {
                firedAlertIds.insert(alert.id)
                fireNotification(alert: alert, coin: coin)
                onAlertTriggered?(alert.id)
            }
        }
    }

    private func fireNotification(alert: PriceAlert, coin: Coin) {
        let content = UNMutableNotificationContent()
        content.title = "💰 \(coin.symbol) 价格提醒"
        content.body  = "\(coin.symbol) 当前 $\(coin.formattedPrice)，已\(alert.alertType.rawValue) $\(alert.threshold)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "alert_\(alert.id)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - Response Models

struct BinanceTickerResponse: Codable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String
    let highPrice: String
    let lowPrice: String
}

struct CoinGeckoMarketItem: Codable {
    let id: String
    let symbol: String
    let currentPrice: Double
    let priceChangePercentage24h: Double?
    let high24h: Double?
    let low24h: Double?
    let totalVolume: Double?

    enum CodingKeys: String, CodingKey {
        case id, symbol
        case currentPrice             = "current_price"
        case priceChangePercentage24h = "price_change_percentage_24h"
        case high24h    = "high_24h"
        case low24h     = "low_24h"
        case totalVolume = "total_volume"
    }
}
