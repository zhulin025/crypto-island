import Foundation
import Combine
import UserNotifications

class BinanceService: ObservableObject {
    // MARK: - Displayed Coins (driven by carousel)
    @Published var leftCoin: Coin?
    @Published var rightCoin: Coin?
    @Published var leftPriceHistory: [Double] = []
    @Published var rightPriceHistory: [Double] = []

    // MARK: - All Tracked Coins (for carousel; keyed by CryptoCoin.id)
    @Published var allCoins: [String: Coin] = [:]

    @Published var errorMessage: String?

    // MARK: - Callbacks
    var onAlertTriggered: ((UUID) -> Void)?
    var onAutoSwitchDataSource: ((DataSource) -> Void)?

    // MARK: - WebSocket Tasks
    private var binanceCombinedTask: URLSessionWebSocketTask?
    private var okxTask: URLSessionWebSocketTask?
    private var gateTask: URLSessionWebSocketTask?

    // MARK: - Timers
    private var coinGeckoTimer: Timer?
    private var okxPingTimer: Timer?
    private var gatePingTimer: Timer?
    private var carouselTimer: Timer?

    // MARK: - Combine (REST)
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Config & State
    private var config: AppConfig?
    private let maxHistory = 120

    // 省电模式（由 AppDelegate 根据系统状态设置）
    var isLowPowerMode = false {
        didSet {
            guard oldValue != isLowPowerMode, config?.dataSource == .coingecko else { return }
            // 重启 CoinGecko 定时器以应用新的轮询间隔
            coinGeckoTimer?.invalidate()
            coinGeckoTimer = nil
            fetchCoinGecko()
            let interval = isLowPowerMode ? 10.0 : 2.0
            coinGeckoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.fetchCoinGecko()
            }
            RunLoop.main.add(coinGeckoTimer!, forMode: .common)
        }
    }

    // Carousel state
    @Published private(set) var carouselWatchlist: [CryptoCoin] = []
    private var carouselIdx = 0
    private var leftCoinId = ""
    private var rightCoinId = ""

    // Symbol → CryptoCoin.id mapping
    private var binanceSymToId: [String: String] = [:]  // "BTCUSDT" → "btc"
    private var okxInstToId:    [String: String] = [:]  // "BTC-USDT" → "btc"
    private var gateSymToId:    [String: String] = [:]  // "BTC_USDT" → "btc"

    // Binance endpoint rotation
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

    // Alert dedup
    private var firedAlertIds = Set<UUID>()

    // MARK: - Public API

    init() {
        // Listen for manual quick switch
        NotificationCenter.default.addObserver(forName: NSNotification.Name("QuickSwitchCoin"), object: nil, queue: .main) { [weak self] note in
            if let config = note.object as? AppConfig {
                self?.startTracking(config: config)
            }
        }
    }

    func startTracking(config: AppConfig) {
        self.config = config
        errorMessage = nil
        allCoins.removeAll()
        leftCoin = nil
        rightCoin = nil
        consecutiveBinanceFailures = 0
        alreadyAutoSwitched = false
        firedAlertIds.removeAll()

        stopTracking()

        // 1. Set up carousel watchlist
        carouselWatchlist = config.watchlist.isEmpty ? [config.leftCoin, config.rightCoin] : config.watchlist
        
        // 2. Ensure leftCoin and rightCoin are in watchlist to receive updates
        if !carouselWatchlist.contains(config.leftCoin) { carouselWatchlist.insert(config.leftCoin, at: 0) }
        if !carouselWatchlist.contains(config.rightCoin) { carouselWatchlist.insert(config.rightCoin, at: 1) }

        // 3. Build symbol → id lookup tables from the actual tracked list
        buildSymbolMaps(watchlist: carouselWatchlist)

        // EXPLICITLY set the starting coins
        if config.carouselEnabled {
            // If carousel is on, try to stay at current index or start at 0
            let idx = (0..<carouselWatchlist.count).first(where: { carouselWatchlist[$0].id == leftCoinId }) ?? 0
            carouselIdx = idx / 2
            updateCarouselPair(animated: false)
        } else {
            // If carousel is off, STRICTLY use the ones from config
            leftCoinId  = config.leftCoin.id
            rightCoinId = config.rightCoin.id
            carouselIdx = 0
            
            DispatchQueue.main.async {
                self.leftCoin  = self.allCoins[self.leftCoinId] ?? Coin(id: self.leftCoinId, symbol: config.leftCoin.id.uppercased(), price: 0, priceChangePercent: 0, high24h: 0, low24h: 0, volume24h: 0, lastUpdate: Date())
                self.rightCoin = self.allCoins[self.rightCoinId] ?? Coin(id: self.rightCoinId, symbol: config.rightCoin.id.uppercased(), price: 0, priceChangePercent: 0, high24h: 0, low24h: 0, volume24h: 0, lastUpdate: Date())
                self.leftPriceHistory.removeAll()
                self.rightPriceHistory.removeAll()
            }
        }

        let trackingCoins = carouselWatchlist
        
        // Force the UI to notice the change immediately on main thread
        DispatchQueue.main.async {
            self.objectWillChange.send()
            NSLog("CryptoIsland: service state reset for \(trackingCoins.map(\.id).joined(separator: ","))")
        }

        NSLog("CryptoIsland: startTracking \(trackingCoins.map(\.id).joined(separator: ",")) via \(config.dataSource.rawValue)")

        switch config.dataSource {
        case .binance:
            connectBinanceCombined(coins: trackingCoins)
            fetchBinanceREST(coins: trackingCoins)
        case .okx:
            connectOKX(coins: trackingCoins)
            fetchOKXREST(coins: trackingCoins)
        case .coingecko:
            fetchCoinGecko()
            let cgInterval = isLowPowerMode ? 10.0 : 2.0
            coinGeckoTimer = Timer.scheduledTimer(withTimeInterval: cgInterval, repeats: true) { [weak self] _ in
                self?.fetchCoinGecko()
            }
            RunLoop.main.add(coinGeckoTimer!, forMode: .common)
        case .gate:
            connectGate(coins: trackingCoins)
        }

        if config.carouselEnabled && carouselWatchlist.count > 2 {
            carouselTimer = Timer.scheduledTimer(withTimeInterval: config.carouselInterval, repeats: true) { [weak self] _ in
                self?.advanceCarousel()
            }
            RunLoop.main.add(carouselTimer!, forMode: .common)
        }
    }

    func stopTracking() {
        binanceCombinedTask?.cancel(with: .goingAway, reason: nil)
        binanceCombinedTask = nil
        okxTask?.cancel(with: .goingAway, reason: nil)
        okxTask = nil
        gateTask?.cancel(with: .goingAway, reason: nil)
        gateTask = nil
        coinGeckoTimer?.invalidate(); coinGeckoTimer = nil
        okxPingTimer?.invalidate();   okxPingTimer = nil
        gatePingTimer?.invalidate();  gatePingTimer = nil
        carouselTimer?.invalidate();  carouselTimer = nil
        cancellables.removeAll()  // Memory leak fix
    }

    // MARK: - Kline Fetch

    func fetchKlines(coin: CryptoCoin, timeframe: KlineTimeframe, completion: @escaping ([KlineBar]) -> Void) {
        guard let config else { return }
        switch config.dataSource {
        case .binance, .coingecko:
            fetchBinanceKlines(symbol: coin.binanceSymbol, timeframe: timeframe, completion: completion)
        case .okx:
            fetchOKXKlines(symbol: coin.okxSymbol, timeframe: timeframe, completion: completion)
        case .gate:
            fetchBinanceKlines(symbol: coin.binanceSymbol, timeframe: timeframe) { bars in
                if bars.isEmpty {
                    self.fetchOKXKlines(symbol: coin.okxSymbol, timeframe: timeframe, completion: completion)
                } else {
                    completion(bars)
                }
            }
        }
    }

    // MARK: - Carousel

    private func advanceCarousel() {
        let wl = carouselWatchlist
        guard wl.count > 2 else { return }
        let pairCount = (wl.count + 1) / 2
        carouselIdx = (carouselIdx + 1) % pairCount
        updateCarouselPair(animated: true)
    }

    private func updateCarouselPair(animated: Bool) {
        let wl = carouselWatchlist
        guard !wl.isEmpty else { return }
        let li = (carouselIdx * 2) % wl.count
        let ri = (carouselIdx * 2 + 1) % wl.count
        leftCoinId  = wl[li].id
        rightCoinId = wl[ri].id

        DispatchQueue.main.async {
            // Pull from cache; may be nil until first WS message arrives
            self.leftCoin  = self.allCoins[self.leftCoinId]
            self.rightCoin = self.allCoins[self.rightCoinId]
            self.leftPriceHistory.removeAll()
            self.rightPriceHistory.removeAll()
        }
    }

    // MARK: - Symbol Maps

    private func buildSymbolMaps(watchlist: [CryptoCoin]) {
        binanceSymToId.removeAll()
        okxInstToId.removeAll()
        gateSymToId.removeAll()
        for coin in watchlist {
            binanceSymToId[coin.binanceSymbol.uppercased()] = coin.id
            okxInstToId[coin.okxSymbol]   = coin.id
            gateSymToId[coin.gateSymbol]  = coin.id
        }
    }

    // MARK: - Binance Combined WebSocket

    private func connectBinanceCombined(coins: [CryptoCoin]) {
        let streams = coins.map { $0.binanceSymbol.lowercased() + "@ticker" }.joined(separator: "/")
        let host = binanceWsHosts[binanceWsIndex % binanceWsHosts.count]
        let urlStr = "wss://\(host)/stream?streams=\(streams)"
        guard let url = URL(string: urlStr) else { return }

        NSLog("CryptoIsland: Binance combined WS → \(urlStr)")
        let task = URLSession.shared.webSocketTask(with: url)
        binanceCombinedTask = task
        task.resume()
        receiveBinanceCombined(task: task, coins: coins)
    }

    private func receiveBinanceCombined(task: URLSessionWebSocketTask, coins: [CryptoCoin]) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                consecutiveBinanceFailures = 0
                if case .string(let text) = msg { parseBinanceCombined(text) }
                receiveBinanceCombined(task: task, coins: coins)

            case .failure(let error):
                let code = (error as NSError).code
                NSLog("CryptoIsland: Binance WS error code=\(code)")
                consecutiveBinanceFailures += 1

                if consecutiveBinanceFailures % 3 == 0 {
                    binanceWsIndex = (binanceWsIndex + 1) % binanceWsHosts.count
                }
                if consecutiveBinanceFailures >= 6 && !alreadyAutoSwitched {
                    alreadyAutoSwitched = true
                    NSLog("CryptoIsland: Binance连续失败\(consecutiveBinanceFailures)次，自动切换OKX")
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.errorMessage = "已自动切换至 OKX"
                        self.onAutoSwitchDataSource?(.okx)
                        self.connectOKX(coins: self.carouselWatchlist)
                        self.fetchOKXREST(coins: self.carouselWatchlist)
                    }
                    return
                }

                DispatchQueue.main.async { self.errorMessage = "Binance连接失败(\(code))" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, self.config?.dataSource == .binance else { return }
                    self.connectBinanceCombined(coins: coins)
                }
            }
        }
    }

    private func parseBinanceCombined(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ticker = json["data"] as? [String: Any],
              let priceStr = ticker["c"] as? String, let price = Double(priceStr),
              let changeStr = ticker["P"] as? String, let change = Double(changeStr),
              let symbol = ticker["s"] as? String else { return }

        let high   = (ticker["h"] as? String).flatMap { Double($0) }
        let low    = (ticker["l"] as? String).flatMap { Double($0) }
        let volume = (ticker["q"] as? String).flatMap { Double($0) }
        let coinId = binanceSymToId[symbol.uppercased()] ?? ""

        DispatchQueue.main.async {
            self.errorMessage = nil
            let coin = Coin(id: symbol,
                            symbol: symbol.replacingOccurrences(of: "USDT", with: ""),
                            price: price, priceChangePercent: change,
                            high24h: high, low24h: low, volume24h: volume, lastUpdate: Date())
            self.allCoins[coinId] = coin
            if coinId == self.leftCoinId  { self.leftCoin  = coin; self.appendHistory(price, isLeft: true)  }
            if coinId == self.rightCoinId { self.rightCoin = coin; self.appendHistory(price, isLeft: false) }
            self.checkAlerts(for: coin)
        }
    }

    // MARK: - Binance REST (initial snapshot for all tracked coins)

    private func fetchBinanceREST(coins: [CryptoCoin]) {
        for coin in coins {
            let host = binanceRestHosts[binanceRestIndex % binanceRestHosts.count]
            let urlStr = "https://\(host)/api/v3/ticker/24hr?symbol=\(coin.binanceSymbol.uppercased())"
            guard let url = URL(string: urlStr) else { continue }

            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData

            URLSession.shared.dataTaskPublisher(for: req)
                .map(\.data)
                .decode(type: BinanceTickerResponse.self, decoder: JSONDecoder())
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] c in
                    if case .failure = c { self?.binanceRestIndex += 1 }
                }, receiveValue: { [weak self] r in
                    guard let self else { return }
                    let newCoin = Coin(id: r.symbol,
                                      symbol: r.symbol.replacingOccurrences(of: "USDT", with: ""),
                                      price: Double(r.lastPrice) ?? 0,
                                      priceChangePercent: Double(r.priceChangePercent) ?? 0,
                                      high24h: Double(r.highPrice), low24h: Double(r.lowPrice),
                                      lastUpdate: Date())
                    let cid = self.binanceSymToId[r.symbol.uppercased()] ?? ""
                    self.allCoins[cid] = newCoin
                    if cid == self.leftCoinId  { self.leftCoin  = newCoin }
                    if cid == self.rightCoinId { self.rightCoin = newCoin }
                })
                .store(in: &cancellables)
        }
    }

    // MARK: - Binance Klines

    private func fetchBinanceKlines(symbol: String, timeframe: KlineTimeframe, completion: @escaping ([KlineBar]) -> Void) {
        let host = binanceRestHosts[binanceRestIndex % binanceRestHosts.count]
        let urlStr = "https://\(host)/api/v3/klines?symbol=\(symbol.uppercased())&interval=\(timeframe.binanceInterval)&limit=60"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let bars: [KlineBar] = arr.compactMap { row in
                guard row.count >= 6,
                      let ts = row[0] as? Double,
                      let o = Double(row[1] as? String ?? ""),
                      let h = Double(row[2] as? String ?? ""),
                      let l = Double(row[3] as? String ?? ""),
                      let c = Double(row[4] as? String ?? ""),
                      let v = Double(row[5] as? String ?? "") else { return nil }
                return KlineBar(open: o, high: h, low: l, close: c, volume: v,
                                time: Date(timeIntervalSince1970: ts / 1000))
            }
            DispatchQueue.main.async { completion(bars) }
        }.resume()
    }

    // MARK: - OKX WebSocket

    private func connectOKX(coins: [CryptoCoin]) {
        guard let url = URL(string: "wss://ws.okx.com:8443/ws/v5/public") else { return }
        NSLog("CryptoIsland: OKX WS → \(coins.map(\.okxSymbol).joined(separator: ","))")

        let task = URLSession.shared.webSocketTask(with: url)
        okxTask = task
        task.resume()

        let args = coins.map { "{\"channel\":\"tickers\",\"instId\":\"\($0.okxSymbol)\"}" }.joined(separator: ",")
        let sub = "{\"op\":\"subscribe\",\"args\":[\(args)]}"
        task.send(.string(sub)) { err in
            if let err { NSLog("CryptoIsland: OKX subscribe error: \(err)") }
        }

        receiveOKX(task: task)

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
                    guard let self, self.config?.dataSource == .okx else { return }
                    self.connectOKX(coins: self.carouselWatchlist)
                }
            }
        }
    }

    private func parseOKXTicker(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let t = dataArr.first,
              let instId   = t["instId"]  as? String,
              let lastStr  = t["last"]    as? String, let last   = Double(lastStr),
              let openStr  = t["open24h"] as? String, let open24 = Double(openStr),
              open24 > 0 else { return }

        let change = (last - open24) / open24 * 100
        let high   = (t["high24h"]   as? String).flatMap { Double($0) }
        let low    = (t["low24h"]    as? String).flatMap { Double($0) }
        let volume = (t["volCcy24h"] as? String).flatMap { Double($0) }
        let sym    = instId.components(separatedBy: "-").first ?? instId
        let coinId = okxInstToId[instId] ?? ""

        DispatchQueue.main.async {
            self.errorMessage = nil
            let coin = Coin(id: instId, symbol: sym, price: last,
                            priceChangePercent: change, high24h: high, low24h: low,
                            volume24h: volume, lastUpdate: Date())
            self.allCoins[coinId] = coin
            if coinId == self.leftCoinId  { self.leftCoin  = coin; self.appendHistory(last, isLeft: true)  }
            if coinId == self.rightCoinId { self.rightCoin = coin; self.appendHistory(last, isLeft: false) }
            self.checkAlerts(for: coin)
        }
    }

    private func fetchOKXREST(coins: [CryptoCoin]) {
        for coin in coins {
            let urlStr = "https://www.okx.com/api/v5/market/ticker?instId=\(coin.okxSymbol)"
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url); req.cachePolicy = .reloadIgnoringLocalCacheData

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
                    let volume = (t["volCcy24h"] as? String).flatMap { Double($0) }
                    let sym    = instId.components(separatedBy: "-").first ?? instId
                    return Coin(id: instId, symbol: sym, price: last, priceChangePercent: change,
                                high24h: high, low24h: low, volume24h: volume, lastUpdate: Date())
                }
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in },
                      receiveValue: { [weak self] newCoin in
                    guard let self else { return }
                    self.errorMessage = nil
                    let cid = self.okxInstToId[newCoin.id] ?? ""
                    self.allCoins[cid] = newCoin
                    if cid == self.leftCoinId  { self.leftCoin  = newCoin }
                    if cid == self.rightCoinId { self.rightCoin = newCoin }
                })
                .store(in: &cancellables)
        }
    }

    // MARK: - OKX Klines

    private func fetchOKXKlines(symbol: String, timeframe: KlineTimeframe, completion: @escaping ([KlineBar]) -> Void) {
        let urlStr = "https://www.okx.com/api/v5/market/candles?instId=\(symbol)&bar=\(timeframe.okxBar)&limit=60"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["data"] as? [[String]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let bars: [KlineBar] = arr.compactMap { row in
                guard row.count >= 6,
                      let ts = Double(row[0]),
                      let o = Double(row[1]),
                      let h = Double(row[2]),
                      let l = Double(row[3]),
                      let c = Double(row[4]),
                      let v = Double(row[5]) else { return nil }
                return KlineBar(open: o, high: h, low: l, close: c, volume: v,
                                time: Date(timeIntervalSince1970: ts / 1000))
            }.reversed() // OKX returns newest first
            DispatchQueue.main.async { completion(bars) }
        }.resume()
    }

    // MARK: - Gate.io WebSocket

    private func connectGate(coins: [CryptoCoin]) {
        guard let url = URL(string: "wss://api.gateio.ws/ws/v4/") else { return }
        NSLog("CryptoIsland: Gate.io WS → \(coins.map(\.gateSymbol).joined(separator: ","))")

        let task = URLSession.shared.webSocketTask(with: url)
        gateTask = task
        task.resume()

        let payload = coins.map { "\"\($0.gateSymbol)\"" }.joined(separator: ",")
        let ts = Int(Date().timeIntervalSince1970)
        let sub = "{\"time\":\(ts),\"channel\":\"spot.tickers\",\"event\":\"subscribe\",\"payload\":[\(payload)]}"
        task.send(.string(sub)) { err in
            if let err { NSLog("CryptoIsland: Gate.io subscribe error: \(err)") }
        }

        receiveGate(task: task)

        gatePingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            let t = Int(Date().timeIntervalSince1970)
            self?.gateTask?.send(.string("{\"time\":\(t),\"channel\":\"spot.ping\"}")) { _ in }
        }
        RunLoop.main.add(gatePingTimer!, forMode: .common)
    }

    private func receiveGate(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg { parseGateTicker(text) }
                receiveGate(task: task)
            case .failure(let error):
                let code = (error as NSError).code
                NSLog("CryptoIsland: Gate.io WS error code=\(code)")
                DispatchQueue.main.async { self.errorMessage = "Gate.io连接失败(\(code))" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, self.config?.dataSource == .gate else { return }
                    self.connectGate(coins: self.carouselWatchlist)
                }
            }
        }
    }

    private func parseGateTicker(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String, event == "update",
              let result = json["result"] as? [String: Any],
              let pair = result["currency_pair"] as? String,
              let lastStr = result["last"] as? String, let last = Double(lastStr),
              let changeStr = result["change_percentage"] as? String, let change = Double(changeStr)
        else { return }

        let high   = (result["high_24h"]    as? String).flatMap { Double($0) }
        let low    = (result["low_24h"]     as? String).flatMap { Double($0) }
        let volume = (result["quote_volume"] as? String).flatMap { Double($0) }
        let sym    = pair.components(separatedBy: "_").first ?? pair
        let coinId = gateSymToId[pair] ?? ""

        DispatchQueue.main.async {
            self.errorMessage = nil
            let coin = Coin(id: pair, symbol: sym, price: last, priceChangePercent: change,
                            high24h: high, low24h: low, volume24h: volume, lastUpdate: Date())
            self.allCoins[coinId] = coin
            if coinId == self.leftCoinId  { self.leftCoin  = coin; self.appendHistory(last, isLeft: true)  }
            if coinId == self.rightCoinId { self.rightCoin = coin; self.appendHistory(last, isLeft: false) }
            self.checkAlerts(for: coin)
        }
    }

    // MARK: - CoinGecko

    private func fetchCoinGecko() {
        guard !carouselWatchlist.isEmpty else { return }
        let ids = carouselWatchlist.map(\.coinGeckoId).joined(separator: ",")
        let urlStr = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=\(ids)&order=market_cap_desc&per_page=\(carouselWatchlist.count)&page=1&sparkline=false"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url); req.cachePolicy = .reloadIgnoringLocalCacheData

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
                    let coin = Coin(id: item.id,
                                   symbol: item.symbol.uppercased(),
                                   price: item.currentPrice,
                                   priceChangePercent: item.priceChangePercentage24h ?? 0,
                                   high24h: item.high24h, low24h: item.low24h,
                                   volume24h: item.totalVolume, lastUpdate: Date())
                    // Find matching CryptoCoin
                    if let cryptoCoin = self.carouselWatchlist.first(where: { $0.coinGeckoId == item.id }) {
                        self.allCoins[cryptoCoin.id] = coin
                        if cryptoCoin.id == self.leftCoinId  {
                            self.leftCoin = coin
                            self.appendHistory(item.currentPrice, isLeft: true)
                            self.checkAlerts(for: coin)
                        }
                        if cryptoCoin.id == self.rightCoinId {
                            self.rightCoin = coin
                            self.appendHistory(item.currentPrice, isLeft: false)
                            self.checkAlerts(for: coin)
                        }
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
            let hit = alert.alertType == .above ? coin.price >= alert.threshold : coin.price <= alert.threshold
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
        let req = UNNotificationRequest(identifier: "alert_\(alert.id)", content: content, trigger: nil)
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
        case high24h                  = "high_24h"
        case low24h                   = "low_24h"
        case totalVolume              = "total_volume"
    }
}
