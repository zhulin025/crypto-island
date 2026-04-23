import SwiftUI

struct SettingsView: View {
    // 数据源
    @State private var dataSource: DataSource

    // 左/右币种（保留兼容）
    @State private var leftPreset: CryptoCoin
    @State private var leftCustomText: String
    @State private var rightPreset: CryptoCoin
    @State private var rightCustomText: String

    // 观察列表
    @State private var watchlist: [CryptoCoin]
    @State private var watchlistCustomText: String = ""

    // 轮播
    @State private var carouselEnabled: Bool
    @State private var carouselInterval: Double

    // 持仓管理
    @State private var holdings: [PortfolioHolding]
    @State private var newHoldingSymbol   = ""
    @State private var newHoldingQty      = ""
    @State private var newHoldingCost     = ""

    // 价格提醒
    @State private var priceAlerts: [PriceAlert]
    @State private var newAlertSymbol    = ""
    @State private var newAlertThreshold = ""
    @State private var newAlertType: PriceAlert.AlertType = .above

    // 其他
    @State private var launchAtLogin: Bool

    // Tab
    @State private var selectedTab = 0

    var onSave: (AppConfig) -> Void

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        let lp = CryptoCoin.presets.first { $0.id == config.leftCoin.id }  ?? CryptoCoin.presets[0]
        let rp = CryptoCoin.presets.first { $0.id == config.rightCoin.id } ?? CryptoCoin.presets[1]
        _leftPreset      = State(initialValue: lp)
        _leftCustomText  = State(initialValue: config.leftCoin.isCustom ? config.leftCoin.displayName : "")
        _rightPreset     = State(initialValue: rp)
        _rightCustomText = State(initialValue: config.rightCoin.isCustom ? config.rightCoin.displayName : "")
        _dataSource      = State(initialValue: config.dataSource)
        _watchlist       = State(initialValue: config.watchlist)
        _carouselEnabled = State(initialValue: config.carouselEnabled)
        _carouselInterval = State(initialValue: config.carouselInterval)
        _holdings        = State(initialValue: config.holdings)
        _priceAlerts     = State(initialValue: config.priceAlerts)
        _launchAtLogin   = State(initialValue: config.launchAtLogin)
        self.onSave = onSave
    }

    var effectiveLeftCoin: CryptoCoin {
        leftCustomText.trimmingCharacters(in: .whitespaces).isEmpty ? leftPreset
            : CryptoCoin.custom(symbol: leftCustomText)
    }
    var effectiveRightCoin: CryptoCoin {
        rightCustomText.trimmingCharacters(in: .whitespaces).isEmpty ? rightPreset
            : CryptoCoin.custom(symbol: rightCustomText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab header
            HStack(spacing: 0) {
                tabButton(0, "行情")
                tabButton(1, "观察列表")
                tabButton(2, "持仓")
                tabButton(3, "提醒")
                tabButton(4, "设置")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedTab {
                    case 0: tabMarket()
                    case 1: tabWatchlist()
                    case 2: tabPortfolio()
                    case 3: tabAlerts()
                    default: tabOther()
                    }
                }
                .padding(16)
                .frame(width: 380)
            }
            .frame(maxHeight: 500)

            Divider()

            HStack {
                Spacer()
                Button("取消") {
                    NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                }
                Button("应用并保存") {
                    saveAndClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Tab Buttons

    @ViewBuilder
    private func tabButton(_ index: Int, _ title: String) -> some View {
        Button(action: { selectedTab = index }) {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == index ? .semibold : .regular))
                .foregroundColor(selectedTab == index ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selectedTab == index ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab: 行情（数据源 + 左右币种）

    @ViewBuilder
    private func tabMarket() -> some View {
        sectionHeader("数据源")
        Picker("", selection: $dataSource) {
            ForEach(DataSource.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
        }
        .pickerStyle(.menu).labelsHidden()

        Divider()

        sectionHeader("左侧币种")
        coinPicker(preset: $leftPreset, customText: $leftCustomText)

        sectionHeader("右侧币种")
        coinPicker(preset: $rightPreset, customText: $rightCustomText)
    }

    // MARK: - Tab: 观察列表 + 轮播

    @ViewBuilder
    private func tabWatchlist() -> some View {
        sectionHeader("观察列表（用于轮播）")

        if watchlist.isEmpty {
            Text("列表为空").font(.caption).foregroundColor(.secondary)
        } else {
            ForEach(watchlist) { coin in
                HStack {
                    Text(coin.displayName).font(.caption)
                    Spacer()
                    Button(action: { watchlist.removeAll { $0.id == coin.id } }) {
                        Image(systemName: "minus.circle.fill").foregroundColor(.red).font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }

        // 添加自定义币种到 watchlist
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { CryptoCoin.presets[0] },
                set: { coin in
                    if !watchlist.contains(coin) { watchlist.append(coin) }
                }
            )) {
                ForEach(CryptoCoin.presets.filter { p in !watchlist.contains(p) }) { coin in
                    Text(coin.displayName).tag(coin)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 180)

            TextField("自定义符号", text: $watchlistCustomText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)

            Button("添加") {
                let sym = watchlistCustomText.trimmingCharacters(in: .whitespaces)
                if !sym.isEmpty {
                    let coin = CryptoCoin.custom(symbol: sym)
                    if !watchlist.contains(coin) { watchlist.append(coin) }
                    watchlistCustomText = ""
                }
            }
            .disabled(watchlistCustomText.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        Divider()

        sectionHeader("轮播设置")
        Toggle("启用轮播", isOn: $carouselEnabled)
            .toggleStyle(.switch)

        if carouselEnabled {
            HStack {
                Text("切换间隔")
                    .font(.callout)
                Spacer()
                Stepper("\(Int(carouselInterval)) 秒", value: $carouselInterval, in: 3...60, step: 1)
                    .frame(width: 140)
            }
            Text("观察列表中的币种将按顺序每 \(Int(carouselInterval)) 秒自动切换显示")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Tab: 持仓管理

    @ViewBuilder
    private func tabPortfolio() -> some View {
        sectionHeader("投资组合")

        if holdings.isEmpty {
            Text("暂无持仓记录").font(.caption).foregroundColor(.secondary)
        } else {
            ForEach(holdings) { h in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(String(format: "%.4f", h.quantity)) 枚 @ $\(String(format: "%.2f", h.avgCostUSD))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { holdings.removeAll { $0.id == h.id } }) {
                        Image(systemName: "trash").foregroundColor(.secondary).font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 3)
            }
        }

        Divider()

        sectionHeader("添加持仓")
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("符号 (如 BTC)", text: $newHoldingSymbol)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("数量", text: $newHoldingQty)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                TextField("均价 USD", text: $newHoldingCost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("添加") {
                    addHolding()
                }
                .disabled(!canAddHolding)
            }
            Text("均价为购买时的 USDT 价格，用于计算盈亏")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var canAddHolding: Bool {
        !newHoldingSymbol.isEmpty &&
        Double(newHoldingQty) != nil &&
        Double(newHoldingCost) != nil
    }

    private func addHolding() {
        guard let qty = Double(newHoldingQty),
              let cost = Double(newHoldingCost),
              !newHoldingSymbol.isEmpty else { return }
        let sym = newHoldingSymbol.uppercased().trimmingCharacters(in: .whitespaces)
        let id  = CryptoCoin.presets.first { $0.id == sym.lowercased() }?.id ?? "custom_\(sym)"
        holdings.append(PortfolioHolding(coinId: id, symbol: sym, quantity: qty, avgCostUSD: cost))
        newHoldingSymbol = ""; newHoldingQty = ""; newHoldingCost = ""
    }

    // MARK: - Tab: 价格提醒

    @ViewBuilder
    private func tabAlerts() -> some View {
        sectionHeader("价格提醒")

        if priceAlerts.isEmpty {
            Text("暂无提醒").font(.caption).foregroundColor(.secondary)
        } else {
            ForEach(priceAlerts) { alert in
                alertRow(alert: alert)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("币种 (如 BTC)", text: $newAlertSymbol)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                Picker("", selection: $newAlertType) {
                    ForEach(PriceAlert.AlertType.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 60)
                TextField("价格", text: $newAlertThreshold)
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                Button("添加") {
                    guard let threshold = Double(newAlertThreshold), !newAlertSymbol.isEmpty else { return }
                    let sym = newAlertSymbol.uppercased().trimmingCharacters(in: .whitespaces)
                    priceAlerts.append(PriceAlert(coinSymbol: sym, threshold: threshold, alertType: newAlertType))
                    newAlertSymbol = ""; newAlertThreshold = ""
                }
                .disabled(newAlertSymbol.isEmpty || Double(newAlertThreshold) == nil)
            }
        }
    }

    @ViewBuilder
    private func alertRow(alert: PriceAlert) -> some View {
        HStack {
            Image(systemName: alert.alertType == .above ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(alert.alertType == .above ? .green : .red)
                .font(.system(size: 12))
            Text("\(alert.coinSymbol) \(alert.alertType.rawValue) $\(formatAlertPrice(alert.threshold))")
                .font(.caption)
            Spacer()
            if !alert.isActive { Text("已触发").font(.caption2).foregroundColor(.orange) }
            Button(action: { priceAlerts.removeAll { $0.id == alert.id } }) {
                Image(systemName: "trash").foregroundColor(.secondary).font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .opacity(alert.isActive ? 1.0 : 0.5)
    }

    // MARK: - Tab: 其他设置

    @ViewBuilder
    private func tabOther() -> some View {
        sectionHeader("系统")
        Toggle("开机自动启动", isOn: $launchAtLogin).toggleStyle(.switch)

        Divider()

        sectionHeader("关于")
        VStack(alignment: .leading, spacing: 4) {
            Text("CryptoIsland v0.2")
                .font(.caption).foregroundColor(.secondary)
            Text("将加密货币实时行情显示在 Mac 灵动岛区域")
                .font(.caption2).foregroundColor(.secondary)
            Text("数据来源：Binance · OKX · Gate.io · CoinGecko")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Shared Subviews

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
    }

    @ViewBuilder
    private func coinPicker(preset: Binding<CryptoCoin>, customText: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: preset) {
                ForEach(CryptoCoin.presets) { coin in Text(coin.displayName).tag(coin) }
            }
            .pickerStyle(.menu).labelsHidden()

            HStack(spacing: 4) {
                Text("或自定义:").font(.caption).foregroundColor(.secondary)
                TextField("输入符号 (如 SUI)", text: customText)
                    .textFieldStyle(.roundedBorder).font(.caption)
                if !customText.wrappedValue.isEmpty {
                    Button(action: { customText.wrappedValue = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !customText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("将追踪: \(customText.wrappedValue.uppercased())USDT (Binance) / \(customText.wrappedValue.uppercased())-USDT (OKX)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func saveAndClose() {
        var cfg = AppConfig()
        cfg.leftCoin         = effectiveLeftCoin
        cfg.rightCoin        = effectiveRightCoin
        cfg.watchlist        = watchlist.isEmpty ? [effectiveLeftCoin, effectiveRightCoin] : watchlist
        cfg.carouselEnabled  = carouselEnabled
        cfg.carouselInterval = carouselInterval
        cfg.dataSource       = dataSource
        cfg.priceAlerts      = priceAlerts
        cfg.launchAtLogin    = launchAtLogin
        cfg.holdings         = holdings
        onSave(cfg)
        NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
    }

    private func formatAlertPrice(_ price: Double) -> String {
        price >= 1 ? String(format: "%.2f", price) : String(format: "%.6f", price)
    }
}
