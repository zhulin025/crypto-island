import Foundation
import UserNotifications

final class BinanceService: ObservableObject {
    @Published var leftCoin: Coin?
    @Published var rightCoin: Coin?
    @Published var leftPriceHistory: [Double] = []
    @Published var rightPriceHistory: [Double] = []
    @Published var allCoins: [String: Coin] = [:]
    @Published var errorMessage: String?

    @Published private(set) var carouselWatchlist: [CryptoCoin] = []
    @Published private(set) var activeRealtimeSource: DataSource?
    @Published private(set) var activeSnapshotSource: DataSource?
    @Published private(set) var activeKlineSource: DataSource?
    @Published private(set) var sourceHealthMap: [DataSource: DataSourceHealth] = [:]

    var onAlertTriggered: ((UUID) -> Void)?

    private let session: URLSession
    private var config: AppConfig?
    private let maxHistory = 120

    private var carouselTimer: Timer?
    private var snapshotTimer: Timer?
    private var pingTimer: Timer?
    private var watchdogTimer: Timer?
    private var restoreTimer: Timer?
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?

    private var realtimeTask: URLSessionWebSocketTask?
    private var activeConnectionToken = UUID()

    private var carouselIdx = 0
    private var leftCoinId = ""
    private var rightCoinId = ""
    private var firedAlertIds = Set<UUID>()

    private var binanceSymToId: [String: String] = [:]
    private var okxInstToId: [String: String] = [:]
    private var gateSymToId: [String: String] = [:]
    private var coinbaseProductToId: [String: String] = [:]

    private let fallbackPriority: [DataSource] = [.okx, .coinbase, .binance, .gate, .coingecko]

    var isLowPowerMode = false {
        didSet {
            guard oldValue != isLowPowerMode else { return }
            if activeRealtimeSource == .coingecko || activeSnapshotSource == .coingecko {
                restartSnapshotPolling()
            }
        }
    }

    init(session: URLSession = .shared) {
        self.session = session
        for source in DataSource.allCases {
            sourceHealthMap[source] = DataSourceHealth(id: source)
        }
    }

    func startTracking(config: AppConfig) {
        stopTracking()

        self.config = config
        errorMessage = nil
        allCoins.removeAll()
        leftCoin = nil
        rightCoin = nil
        firedAlertIds.removeAll()

        carouselWatchlist = config.watchlist.isEmpty ? [config.leftCoin, config.rightCoin] : config.watchlist
        if !carouselWatchlist.contains(config.leftCoin) { carouselWatchlist.insert(config.leftCoin, at: 0) }
        if !carouselWatchlist.contains(config.rightCoin) { carouselWatchlist.insert(config.rightCoin, at: 1) }

        buildSymbolMaps(watchlist: carouselWatchlist)

        if config.carouselEnabled {
            let idx = (0..<carouselWatchlist.count).first(where: { carouselWatchlist[$0].id == leftCoinId }) ?? 0
            carouselIdx = idx / 2
            updateCarouselPair(animated: false)
        } else {
            leftCoinId = config.leftCoin.id
            rightCoinId = config.rightCoin.id
            carouselIdx = 0
            leftCoin = placeholderCoin(for: config.leftCoin)
            rightCoin = placeholderCoin(for: config.rightCoin)
            leftPriceHistory.removeAll()
            rightPriceHistory.removeAll()
        }

        if config.carouselEnabled && carouselWatchlist.count > 2 {
            let newTimer = Timer.scheduledTimer(withTimeInterval: config.carouselInterval, repeats: true) { [weak self] _ in
                self?.advanceCarousel()
            }
            carouselTimer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
        }

        bootstrapSources()
    }

    func stopTracking() {
        cancelRealtimeConnection()
        invalidateTimer(&carouselTimer)
        invalidateTimer(&snapshotTimer)
        invalidateTimer(&restoreTimer)
        activeRealtimeSource = nil
        activeSnapshotSource = nil
        activeKlineSource = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    func fetchKlines(coin: CryptoCoin, timeframe: KlineTimeframe, completion: @escaping ([KlineBar]) -> Void) {
        let source = pickKlineSource(preferred: activeRealtimeSource ?? config?.dataSource)
        activeKlineSource = source

        switch source {
        case .okx:
            fetchOKXKlines(symbol: coin.okxSymbol, timeframe: timeframe, completion: completion)
        case .coinbase:
            fetchCoinbaseKlines(productId: coin.coinbaseSymbol, timeframe: timeframe, completion: completion)
        case .gate:
            fetchBinanceKlines(symbol: coin.binanceSymbol, timeframe: timeframe) { [weak self] bars in
                if bars.isEmpty {
                    self?.fetchOKXKlines(symbol: coin.okxSymbol, timeframe: timeframe, completion: completion)
                } else {
                    completion(bars)
                }
            }
        case .binance, .coingecko:
            fetchBinanceKlines(symbol: coin.binanceSymbol, timeframe: timeframe, completion: completion)
        }
    }

    func health(for source: DataSource) -> DataSourceHealth {
        sourceHealthMap[source] ?? DataSourceHealth(id: source)
    }

    var sourceRoleSummary: [SourceRoleAssignment] {
        [
            SourceRoleAssignment(role: .realtime, source: activeRealtimeSource),
            SourceRoleAssignment(role: .snapshot, source: activeSnapshotSource),
            SourceRoleAssignment(role: .kline, source: activeKlineSource)
        ]
    }

    private func bootstrapSources() {
        guard let config else { return }

        let snapshotSource = config.dataSource == .coingecko ? DataSource.coingecko : config.dataSource
        seedSnapshot(from: snapshotSource)
        if snapshotSource != .coingecko {
            seedSnapshot(from: .coingecko)
        }

        let preferredRealtime = config.dataSource
        if preferredRealtime == .coingecko {
            activeRealtimeSource = .coingecko
            markState(.live, for: .coingecko, error: nil)
            restartSnapshotPolling()
        } else {
            connectRealtime(source: preferredRealtime, reason: "primary")
        }

        restartRestoreTimerIfNeeded()
    }

    private func buildSymbolMaps(watchlist: [CryptoCoin]) {
        binanceSymToId.removeAll()
        okxInstToId.removeAll()
        gateSymToId.removeAll()
        coinbaseProductToId.removeAll()
        for coin in watchlist {
            binanceSymToId[coin.binanceSymbol.uppercased()] = coin.id
            okxInstToId[coin.okxSymbol] = coin.id
            gateSymToId[coin.gateSymbol] = coin.id
            coinbaseProductToId[coin.coinbaseSymbol] = coin.id
        }
    }

    private func placeholderCoin(for cryptoCoin: CryptoCoin) -> Coin {
        Coin(
            id: cryptoCoin.id,
            symbol: cryptoCoin.baseSymbol,
            price: 0,
            priceChangePercent: 0,
            high24h: 0,
            low24h: 0,
            volume24h: 0,
            lastUpdate: Date()
        )
    }

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
        leftCoinId = wl[li].id
        rightCoinId = wl[ri].id
        leftCoin = allCoins[leftCoinId]
        rightCoin = allCoins[rightCoinId]
        leftPriceHistory.removeAll()
        rightPriceHistory.removeAll()
    }

    private func connectRealtime(source: DataSource, reason: String) {
        guard let config else { return }

        cancelRealtimeConnection()
        activeConnectionToken = UUID()
        activeRealtimeSource = source
        activeKlineSource = pickKlineSource(preferred: source)
        errorMessage = nil
        markState(.connecting, for: source, error: nil)

        if source == .coingecko {
            markMessage(for: .coingecko, latencyMs: nil)
            restartSnapshotPolling()
            return
        }

        let token = activeConnectionToken
        let watchlist = carouselWatchlist.isEmpty ? [config.leftCoin, config.rightCoin] : carouselWatchlist

        guard let url = websocketURL(for: source, watchlist: watchlist) else {
            failRealtime(source: source, token: token, message: "无效连接地址")
            return
        }

        let task = session.webSocketTask(with: url)
        realtimeTask = task
        task.resume()
        sendSubscribeIfNeeded(source: source, task: task, watchlist: watchlist)
        scheduleConnectTimeout(for: source, token: token)
        startPingIfNeeded(for: source)
        startWatchdog(for: source, token: token)
        receiveLoop(source: source, token: token, task: task)
        seedSnapshot(from: source)
    }

    private func websocketURL(for source: DataSource, watchlist: [CryptoCoin]) -> URL? {
        switch source {
        case .binance:
            let streams = watchlist.map { $0.binanceSymbol.lowercased() + "@ticker" }.joined(separator: "/")
            return URL(string: "wss://stream.binance.com:9443/stream?streams=\(streams)")
        case .okx:
            return URL(string: "wss://ws.okx.com:8443/ws/v5/public")
        case .gate:
            return URL(string: "wss://api.gateio.ws/ws/v4/")
        case .coinbase:
            return URL(string: "wss://advanced-trade-ws.coinbase.com")
        case .coingecko:
            return nil
        }
    }

    private func sendSubscribeIfNeeded(source: DataSource, task: URLSessionWebSocketTask, watchlist: [CryptoCoin]) {
        switch source {
        case .okx:
            let args = watchlist.map { "{\"channel\":\"tickers\",\"instId\":\"\($0.okxSymbol)\"}" }.joined(separator: ",")
            let sub = "{\"op\":\"subscribe\",\"args\":[\(args)]}"
            task.send(.string(sub)) { _ in }
        case .gate:
            let payload = watchlist.map { "\"\($0.gateSymbol)\"" }.joined(separator: ",")
            let ts = Int(Date().timeIntervalSince1970)
            let sub = "{\"time\":\(ts),\"channel\":\"spot.tickers\",\"event\":\"subscribe\",\"payload\":[\(payload)]}"
            task.send(.string(sub)) { _ in }
        case .coinbase:
            let productIds = watchlist.map(\.coinbaseSymbol)
            let heartbeat = coinbaseSubscribePayload(channel: "heartbeats", productIds: productIds)
            let ticker = coinbaseSubscribePayload(channel: "ticker", productIds: productIds)
            task.send(.string(heartbeat)) { _ in }
            task.send(.string(ticker)) { _ in }
        default:
            break
        }
    }

    private func coinbaseSubscribePayload(channel: String, productIds: [String]) -> String {
        let quoted = productIds.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"type\":\"subscribe\",\"product_ids\":[\(quoted)],\"channel\":\"\(channel)\"}"
    }

    private func receiveLoop(source: DataSource, token: UUID, task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            guard token == self.activeConnectionToken, source == self.activeRealtimeSource else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleRealtimeMessage(source: source, text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleRealtimeMessage(source: source, text: text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop(source: source, token: token, task: task)
            case .failure(let error):
                self.failRealtime(source: source, token: token, message: error.localizedDescription)
            }
        }
    }

    private func handleRealtimeMessage(source: DataSource, text: String) {
        switch source {
        case .binance:
            parseBinanceCombined(text)
        case .okx:
            if text != "pong" { parseOKXTicker(text) }
        case .gate:
            parseGateTicker(text)
        case .coinbase:
            parseCoinbaseTicker(text)
        case .coingecko:
            break
        }
    }

    private func parseBinanceCombined(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ticker = json["data"] as? [String: Any],
            let price = Double(ticker["c"] as? String ?? ""),
            let change = Double(ticker["P"] as? String ?? ""),
            let symbol = ticker["s"] as? String
        else { return }

        let high = (ticker["h"] as? String).flatMap(Double.init)
        let low = (ticker["l"] as? String).flatMap(Double.init)
        let volume = (ticker["q"] as? String).flatMap(Double.init)
        let coinId = binanceSymToId[symbol.uppercased()]
        markMessage(for: .binance, latencyMs: nil)
        updateCoin(
            coinId: coinId,
            coin: Coin(
                id: symbol,
                symbol: symbol.replacingOccurrences(of: "USDT", with: ""),
                price: price,
                priceChangePercent: change,
                high24h: high,
                low24h: low,
                volume24h: volume,
                lastUpdate: Date()
            )
        )
    }

    private func parseOKXTicker(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArr = json["data"] as? [[String: Any]],
            let ticker = dataArr.first,
            let instId = ticker["instId"] as? String,
            let last = Double(ticker["last"] as? String ?? ""),
            let open24 = Double(ticker["open24h"] as? String ?? ""),
            open24 > 0
        else { return }

        let change = (last - open24) / open24 * 100
        let high = (ticker["high24h"] as? String).flatMap(Double.init)
        let low = (ticker["low24h"] as? String).flatMap(Double.init)
        let volume = (ticker["volCcy24h"] as? String).flatMap(Double.init)
        let coinId = okxInstToId[instId]
        let symbol = instId.components(separatedBy: "-").first ?? instId
        markMessage(for: .okx, latencyMs: nil)
        updateCoin(
            coinId: coinId,
            coin: Coin(
                id: instId,
                symbol: symbol,
                price: last,
                priceChangePercent: change,
                high24h: high,
                low24h: low,
                volume24h: volume,
                lastUpdate: Date()
            )
        )
    }

    private func parseGateTicker(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = json["event"] as? String, event == "update",
            let result = json["result"] as? [String: Any],
            let pair = result["currency_pair"] as? String,
            let last = Double(result["last"] as? String ?? ""),
            let change = Double(result["change_percentage"] as? String ?? "")
        else { return }

        let high = (result["high_24h"] as? String).flatMap(Double.init)
        let low = (result["low_24h"] as? String).flatMap(Double.init)
        let volume = (result["quote_volume"] as? String).flatMap(Double.init)
        let coinId = gateSymToId[pair]
        let symbol = pair.components(separatedBy: "_").first ?? pair
        markMessage(for: .gate, latencyMs: nil)
        updateCoin(
            coinId: coinId,
            coin: Coin(
                id: pair,
                symbol: symbol,
                price: last,
                priceChangePercent: change,
                high24h: high,
                low24h: low,
                volume24h: volume,
                lastUpdate: Date()
            )
        )
    }

    private func parseCoinbaseTicker(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let channel = json["channel"] as? String
        else { return }

        if channel == "heartbeats" {
            markMessage(for: .coinbase, latencyMs: nil)
            return
        }

        guard channel == "ticker", let events = json["events"] as? [[String: Any]] else { return }
        for event in events {
            let tickers = event["tickers"] as? [[String: Any]] ?? []
            for ticker in tickers {
                guard
                    let productId = ticker["product_id"] as? String,
                    let price = Double(ticker["price"] as? String ?? "")
                else { continue }

                let open = Double(ticker["open_24_h"] as? String ?? "") ?? 0
                let change = open > 0 ? (price - open) / open * 100 : 0
                let high = (ticker["high_24_h"] as? String).flatMap(Double.init)
                let low = (ticker["low_24_h"] as? String).flatMap(Double.init)
                let volume = (ticker["volume_24_h"] as? String).flatMap(Double.init)
                let coinId = coinbaseProductToId[productId]
                let symbol = productId.components(separatedBy: "-").first ?? productId
                markMessage(for: .coinbase, latencyMs: nil)
                updateCoin(
                    coinId: coinId,
                    coin: Coin(
                        id: productId,
                        symbol: symbol,
                        price: price,
                        priceChangePercent: change,
                        high24h: high,
                        low24h: low,
                        volume24h: volume,
                        lastUpdate: Date()
                    )
                )
            }
        }
    }

    private func updateCoin(coinId: String?, coin: Coin) {
        guard let coinId else { return }
        DispatchQueue.main.async {
            self.errorMessage = nil
            self.allCoins[coinId] = coin
            if coinId == self.leftCoinId {
                self.leftCoin = coin
                self.appendHistory(coin.price, isLeft: true)
            }
            if coinId == self.rightCoinId {
                self.rightCoin = coin
                self.appendHistory(coin.price, isLeft: false)
            }
            self.checkAlerts(for: coin)
        }
    }

    private func seedSnapshot(from source: DataSource) {
        guard !carouselWatchlist.isEmpty else { return }
        activeSnapshotSource = source

        switch source {
        case .binance:
            fetchBinanceSnapshot()
        case .okx:
            fetchOKXSnapshot()
        case .coinbase:
            fetchCoinbaseSnapshot()
        case .gate:
            fetchGateSnapshot()
        case .coingecko:
            restartSnapshotPolling()
        }
    }

    private func restartSnapshotPolling() {
        invalidateTimer(&snapshotTimer)
        guard let config else { return }
        let interval = isLowPowerMode ? 10.0 : 3.0

        if activeRealtimeSource == .coingecko || config.dataSource == .coingecko {
            activeRealtimeSource = .coingecko
            activeSnapshotSource = .coingecko
        }

        fetchCoinGecko()
        let newTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchCoinGecko()
        }
        snapshotTimer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func fetchBinanceSnapshot() {
        for coin in carouselWatchlist {
            guard let url = URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbol=\(coin.binanceSymbol)") else { continue }
            session.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data else { return }
                guard let response = try? JSONDecoder().decode(BinanceTickerResponse.self, from: data) else { return }
                let coinId = self.binanceSymToId[response.symbol.uppercased()]
                self.markSnapshotSuccess(for: .binance)
                self.updateCoin(
                    coinId: coinId,
                    coin: Coin(
                        id: response.symbol,
                        symbol: response.symbol.replacingOccurrences(of: "USDT", with: ""),
                        price: Double(response.lastPrice) ?? 0,
                        priceChangePercent: Double(response.priceChangePercent) ?? 0,
                        high24h: Double(response.highPrice),
                        low24h: Double(response.lowPrice),
                        volume24h: Double(response.quoteVolume),
                        lastUpdate: Date()
                    )
                )
            }.resume()
        }
    }

    private func fetchOKXSnapshot() {
        for coin in carouselWatchlist {
            guard let url = URL(string: "https://www.okx.com/api/v5/market/ticker?instId=\(coin.okxSymbol)") else { continue }
            session.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data else { return }
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let arr = json["data"] as? [[String: Any]],
                    let ticker = arr.first,
                    let instId = ticker["instId"] as? String,
                    let last = Double(ticker["last"] as? String ?? ""),
                    let open = Double(ticker["open24h"] as? String ?? ""),
                    open > 0
                else { return }

                let symbol = instId.components(separatedBy: "-").first ?? instId
                let change = (last - open) / open * 100
                self.markSnapshotSuccess(for: .okx)
                self.updateCoin(
                    coinId: self.okxInstToId[instId],
                    coin: Coin(
                        id: instId,
                        symbol: symbol,
                        price: last,
                        priceChangePercent: change,
                        high24h: (ticker["high24h"] as? String).flatMap(Double.init),
                        low24h: (ticker["low24h"] as? String).flatMap(Double.init),
                        volume24h: (ticker["volCcy24h"] as? String).flatMap(Double.init),
                        lastUpdate: Date()
                    )
                )
            }.resume()
        }
    }

    private func fetchCoinbaseSnapshot() {
        for coin in carouselWatchlist {
            guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(coin.coinbaseSymbol)/stats") else { continue }
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            session.dataTask(with: req) { [weak self] data, _, _ in
                guard let self, let data else { return }
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let last = Double(json["last"] as? String ?? ""),
                    let open = Double(json["open"] as? String ?? ""),
                    open > 0
                else { return }

                let symbol = coin.baseSymbol
                let change = (last - open) / open * 100
                self.markSnapshotSuccess(for: .coinbase)
                self.updateCoin(
                    coinId: coin.id,
                    coin: Coin(
                        id: coin.coinbaseSymbol,
                        symbol: symbol,
                        price: last,
                        priceChangePercent: change,
                        high24h: (json["high"] as? String).flatMap(Double.init),
                        low24h: (json["low"] as? String).flatMap(Double.init),
                        volume24h: (json["volume"] as? String).flatMap(Double.init).map { $0 * last },
                        lastUpdate: Date()
                    )
                )
            }.resume()
        }
    }

    private func fetchGateSnapshot() {
        for coin in carouselWatchlist {
            guard let url = URL(string: "https://api.gateio.ws/api/v4/spot/tickers?currency_pair=\(coin.gateSymbol)") else { continue }
            session.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data else { return }
                guard
                    let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                    let ticker = arr.first,
                    let last = Double(ticker["last"] as? String ?? ""),
                    let change = Double(ticker["change_percentage"] as? String ?? "")
                else { return }

                self.markSnapshotSuccess(for: .gate)
                self.updateCoin(
                    coinId: coin.id,
                    coin: Coin(
                        id: coin.gateSymbol,
                        symbol: coin.baseSymbol,
                        price: last,
                        priceChangePercent: change,
                        high24h: (ticker["high_24h"] as? String).flatMap(Double.init),
                        low24h: (ticker["low_24h"] as? String).flatMap(Double.init),
                        volume24h: (ticker["quote_volume"] as? String).flatMap(Double.init),
                        lastUpdate: Date()
                    )
                )
            }.resume()
        }
    }

    private func fetchCoinGecko() {
        guard !carouselWatchlist.isEmpty else { return }
        let ids = carouselWatchlist.map(\.coinGeckoId).joined(separator: ",")
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=\(ids)&order=market_cap_desc&per_page=\(carouselWatchlist.count)&page=1&sparkline=false") else { return }

        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            guard let items = try? JSONDecoder().decode([CoinGeckoMarketItem].self, from: data) else {
                DispatchQueue.main.async {
                    self.errorMessage = "CoinGecko连接失败"
                    self.markFailure(for: .coingecko, error: "快照请求失败")
                }
                return
            }

            self.markSnapshotSuccess(for: .coingecko)
            for item in items {
                guard let cryptoCoin = self.carouselWatchlist.first(where: { $0.coinGeckoId == item.id }) else { continue }
                self.updateCoin(
                    coinId: cryptoCoin.id,
                    coin: Coin(
                        id: item.id,
                        symbol: item.symbol.uppercased(),
                        price: item.currentPrice,
                        priceChangePercent: item.priceChangePercentage24h ?? 0,
                        high24h: item.high24h,
                        low24h: item.low24h,
                        volume24h: item.totalVolume,
                        lastUpdate: Date()
                    )
                )
            }
        }.resume()
    }

    private func fetchBinanceKlines(symbol: String, timeframe: KlineTimeframe, completion: @escaping ([KlineBar]) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/klines?symbol=\(symbol.uppercased())&interval=\(timeframe.binanceInterval)&limit=60") else {
            completion([])
            return
        }

        session.dataTask(with: url) { data, _, _ in
            guard
                let data,
                let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]]
            else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let bars: [KlineBar] = arr.compactMap { row in
                guard
                    row.count >= 6,
                    let ts = row[0] as? Double,
                    let o = Double(row[1] as? String ?? ""),
                    let h = Double(row[2] as? String ?? ""),
                    let l = Double(row[3] as? String ?? ""),
                    let c = Double(row[4] as? String ?? ""),
                    let v = Double(row[5] as? String ?? "")
                else { return nil }
                return KlineBar(open: o, high: h, low: l, close: c, volume: v, time: Date(timeIntervalSince1970: ts / 1000))
            }
            DispatchQueue.main.async { completion(bars) }
        }.resume()
    }

    private func fetchOKXKlines(symbol: String, timeframe: KlineTimeframe, completion: @escaping ([KlineBar]) -> Void) {
        guard let url = URL(string: "https://www.okx.com/api/v5/market/candles?instId=\(symbol)&bar=\(timeframe.okxBar)&limit=60") else {
            completion([])
            return
        }

        session.dataTask(with: url) { data, _, _ in
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let arr = json["data"] as? [[String]]
            else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let bars = arr.compactMap { row -> KlineBar? in
                guard row.count >= 6,
                      let ts = Double(row[0]),
                      let o = Double(row[1]),
                      let h = Double(row[2]),
                      let l = Double(row[3]),
                      let c = Double(row[4]),
                      let v = Double(row[5]) else { return nil }
                return KlineBar(open: o, high: h, low: l, close: c, volume: v, time: Date(timeIntervalSince1970: ts / 1000))
            }.reversed()

            DispatchQueue.main.async { completion(Array(bars)) }
        }.resume()
    }

    private func fetchCoinbaseKlines(productId: String, timeframe: KlineTimeframe, completion: @escaping ([KlineBar]) -> Void) {
        let granularity: Int
        switch timeframe {
        case .m1: granularity = 60
        case .m15: granularity = 900
        case .h1: granularity = 3600
        case .h4: granularity = 14400
        case .d1: granularity = 86400
        }

        guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(productId)/candles?granularity=\(granularity)") else {
            completion([])
            return
        }

        session.dataTask(with: url) { data, _, _ in
            guard
                let data,
                let arr = try? JSONSerialization.jsonObject(with: data) as? [[Double]]
            else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let bars = arr.compactMap { row -> KlineBar? in
                guard row.count >= 6 else { return nil }
                return KlineBar(
                    open: row[3],
                    high: row[2],
                    low: row[1],
                    close: row[4],
                    volume: row[5],
                    time: Date(timeIntervalSince1970: row[0])
                )
            }.sorted { $0.time < $1.time }

            DispatchQueue.main.async { completion(bars) }
        }.resume()
    }

    private func scheduleConnectTimeout(for source: DataSource, token: UUID) {
        connectTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard token == self.activeConnectionToken, self.activeRealtimeSource == source else { return }
            let health = self.health(for: source)
            if health.lastMessageAt == nil {
                self.failRealtime(source: source, token: token, message: "连接超时")
            }
        }
        connectTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func startPingIfNeeded(for source: DataSource) {
        invalidateTimer(&pingTimer)
        let interval: TimeInterval
        switch source {
        case .okx: interval = 25
        case .gate: interval = 15
        default: return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let task = self.realtimeTask else { return }
            switch source {
            case .okx:
                task.send(.string("ping")) { _ in }
            case .gate:
                let ts = Int(Date().timeIntervalSince1970)
                task.send(.string("{\"time\":\(ts),\"channel\":\"spot.ping\"}")) { _ in }
            default:
                break
            }
        }
        pingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startWatchdog(for source: DataSource, token: UUID) {
        invalidateTimer(&watchdogTimer)
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard token == self.activeConnectionToken, self.activeRealtimeSource == source else { return }
            let health = self.health(for: source)
            guard let lastMessageAt = health.lastMessageAt else { return }
            let age = Date().timeIntervalSince(lastMessageAt)
            if age > 20 {
                self.failRealtime(source: source, token: token, message: "心跳超时")
            } else if age > 10 {
                self.markState(.degraded, for: source, error: "延迟升高")
            }
        }
        watchdogTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelRealtimeConnection() {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        realtimeTask?.cancel(with: .goingAway, reason: nil)
        realtimeTask = nil
        invalidateTimer(&pingTimer)
        invalidateTimer(&watchdogTimer)
    }

    private func failRealtime(source: DataSource, token: UUID, message: String) {
        guard token == activeConnectionToken else { return }

        DispatchQueue.main.async {
            self.errorMessage = "\(source.shortName)连接失败"
        }
        incrementDisconnect(for: source, error: message)

        if shouldFallback(from: source) {
            if let fallback = nextFallbackSource(after: source) {
                connectRealtime(source: fallback, reason: "fallback")
                return
            }
        }

        scheduleReconnect(source: source)
    }

    private func scheduleReconnect(source: DataSource) {
        let failures = max(1, health(for: source).consecutiveFailures)
        let delay = min(pow(2.0, Double(failures)), 30.0)
        let nextRetryAt = Date().addingTimeInterval(delay)
        var health = self.health(for: source)
        health.state = .backingOff
        health.nextRetryAt = nextRetryAt
        sourceHealthMap[source] = health

        reconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.activeRealtimeSource == source || self.activeRealtimeSource == nil else { return }
            self.connectRealtime(source: source, reason: "retry")
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func shouldFallback(from source: DataSource) -> Bool {
        guard let config else { return false }
        if config.lockPrimaryDataSource { return false }
        return source == config.dataSource || health(for: source).consecutiveFailures >= 2
    }

    private func nextFallbackSource(after source: DataSource) -> DataSource? {
        guard let config else { return nil }
        let preferred = [config.dataSource] + fallbackPriority
        for candidate in preferred {
            guard candidate != source else { continue }
            if candidate == .coingecko { return .coingecko }
            if candidate == .coinbase && carouselWatchlist.allSatisfy({ coinbaseProductToId[$0.coinbaseSymbol] != nil }) {
                return candidate
            }
            if candidate != .coinbase {
                return candidate
            }
        }
        return nil
    }

    private func restartRestoreTimerIfNeeded() {
        invalidateTimer(&restoreTimer)
        guard let config else { return }
        guard !config.lockPrimaryDataSource, config.autoRestorePrimarySource else { return }
        guard config.dataSource != .coingecko else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, let config = self.config else { return }
            guard self.activeRealtimeSource != config.dataSource else { return }
            self.connectRealtime(source: config.dataSource, reason: "restore-primary")
        }
        restoreTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pickKlineSource(preferred: DataSource?) -> DataSource {
        let source = preferred ?? .binance
        if source.supportsKlines { return source }
        return .binance
    }

    private func appendHistory(_ price: Double, isLeft: Bool) {
        if isLeft {
            leftPriceHistory.append(price)
            if leftPriceHistory.count > maxHistory {
                leftPriceHistory.removeFirst(leftPriceHistory.count - maxHistory)
            }
        } else {
            rightPriceHistory.append(price)
            if rightPriceHistory.count > maxHistory {
                rightPriceHistory.removeFirst(rightPriceHistory.count - maxHistory)
            }
        }
    }

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
        content.body = "\(coin.symbol) 当前 $\(coin.formattedPrice)，已\(alert.alertType.rawValue) $\(alert.threshold)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "alert_\(alert.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func markMessage(for source: DataSource, latencyMs: Double?) {
        DispatchQueue.main.async {
            var health = self.health(for: source)
            health.state = .live
            health.lastMessageAt = Date()
            health.lastSuccessAt = Date()
            health.nextRetryAt = nil
            health.consecutiveFailures = 0
            if let latencyMs {
                health.latencyMs = latencyMs
            }
            health.lastError = nil
            self.sourceHealthMap[source] = health
        }
    }

    private func markSnapshotSuccess(for source: DataSource) {
        DispatchQueue.main.async {
            var health = self.health(for: source)
            health.lastSuccessAt = Date()
            health.lastMessageAt = Date()
            health.consecutiveFailures = 0
            if health.state == .idle || health.state == .failed {
                health.state = source == .coingecko ? .live : health.state
            }
            health.lastError = nil
            self.sourceHealthMap[source] = health
        }
    }

    private func markFailure(for source: DataSource, error: String) {
        DispatchQueue.main.async {
            var health = self.health(for: source)
            health.consecutiveFailures += 1
            health.lastError = error
            health.state = .failed
            self.sourceHealthMap[source] = health
        }
    }

    private func incrementDisconnect(for source: DataSource, error: String) {
        DispatchQueue.main.async {
            var health = self.health(for: source)
            health.disconnectCount += 1
            health.consecutiveFailures += 1
            health.lastError = error
            health.state = .failed
            self.sourceHealthMap[source] = health
        }
    }

    private func markState(_ state: SourceConnectionState, for source: DataSource, error: String?) {
        DispatchQueue.main.async {
            var health = self.health(for: source)
            health.state = state
            if let error {
                health.lastError = error
            }
            if state == .connecting {
                health.nextRetryAt = nil
            }
            self.sourceHealthMap[source] = health
        }
    }

    private func invalidateTimer(_ timer: inout Timer?) {
        timer?.invalidate()
        timer = nil
    }
}

struct BinanceTickerResponse: Codable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String
    let highPrice: String
    let lowPrice: String
    let quoteVolume: String
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
        case currentPrice = "current_price"
        case priceChangePercentage24h = "price_change_percentage_24h"
        case high24h = "high_24h"
        case low24h = "low_24h"
        case totalVolume = "total_volume"
    }
}
