import SwiftUI

struct SettingsView: View {
    // 币种选择
    @State private var leftPreset: CryptoCoin
    @State private var leftCustomText: String
    @State private var rightPreset: CryptoCoin
    @State private var rightCustomText: String
    @State private var dataSource: DataSource

    // 价格提醒
    @State private var priceAlerts: [PriceAlert]
    @State private var newAlertSymbol: String = ""
    @State private var newAlertThreshold: String = ""
    @State private var newAlertType: PriceAlert.AlertType = .above

    // 其他
    @State private var launchAtLogin: Bool

    var onSave: (AppConfig) -> Void

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        let lp = CryptoCoin.presets.first { $0.id == config.leftCoin.id } ?? CryptoCoin.presets[0]
        let rp = CryptoCoin.presets.first { $0.id == config.rightCoin.id } ?? CryptoCoin.presets[1]
        _leftPreset      = State(initialValue: lp)
        _leftCustomText  = State(initialValue: config.leftCoin.isCustom ? config.leftCoin.displayName : "")
        _rightPreset     = State(initialValue: rp)
        _rightCustomText = State(initialValue: config.rightCoin.isCustom ? config.rightCoin.displayName : "")
        _dataSource      = State(initialValue: config.dataSource)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // MARK: 标题
                Text("灵动岛加密货币设置")
                    .font(.headline)
                    .padding(.bottom, 2)

                // MARK: 数据源
                sectionHeader("数据源")
                Picker("", selection: $dataSource) {
                    ForEach(DataSource.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Divider()

                // MARK: 左侧币种
                sectionHeader("左侧币种")
                coinPicker(preset: $leftPreset, customText: $leftCustomText)

                // MARK: 右侧币种
                sectionHeader("右侧币种")
                coinPicker(preset: $rightPreset, customText: $rightCustomText)

                Divider()

                // MARK: 价格提醒
                sectionHeader("价格提醒")
                if priceAlerts.isEmpty {
                    Text("暂无提醒").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(priceAlerts) { alert in
                        alertRow(alert: alert)
                    }
                }

                // 添加提醒
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("币种 (如 BTC)", text: $newAlertSymbol)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        Picker("", selection: $newAlertType) {
                            ForEach(PriceAlert.AlertType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 60)

                        TextField("价格", text: $newAlertThreshold)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)

                        Button("添加") {
                            addAlert()
                        }
                        .disabled(newAlertSymbol.isEmpty || Double(newAlertThreshold) == nil)
                    }
                }

                Divider()

                // MARK: 其他设置
                sectionHeader("其他设置")
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .toggleStyle(.switch)

                Divider()

                // MARK: 按钮行
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
            }
            .padding(16)
            .frame(width: 380)
        }
        .frame(width: 400, height: 560)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
    }

    @ViewBuilder
    private func coinPicker(preset: Binding<CryptoCoin>, customText: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: preset) {
                ForEach(CryptoCoin.presets) { coin in
                    Text(coin.displayName).tag(coin)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            HStack(spacing: 4) {
                Text("或自定义:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("输入符号 (如 SUI)", text: customText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: customText.wrappedValue) { _ in
                        // 有自定义输入时清空，界面显示自定义
                    }
                if !customText.wrappedValue.isEmpty {
                    Button(action: { customText.wrappedValue = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !customText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("将追踪: \(customText.wrappedValue.uppercased())USDT (Binance) / \(customText.wrappedValue.uppercased())-USDT (OKX)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func alertRow(alert: PriceAlert) -> some View {
        HStack {
            Image(systemName: alert.alertType == .above ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(alert.alertType == .above ? .green : .red)
                .font(.system(size: 12))
            Text("\(alert.coinSymbol) \(alert.alertType.rawValue) \(formatAlertPrice(alert.threshold))")
                .font(.caption)
            Spacer()
            if !alert.isActive {
                Text("已触发")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Button(action: { deleteAlert(id: alert.id) }) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .opacity(alert.isActive ? 1.0 : 0.5)
    }

    // MARK: - Actions

    private func addAlert() {
        guard let threshold = Double(newAlertThreshold), !newAlertSymbol.isEmpty else { return }
        let alert = PriceAlert(coinSymbol: newAlertSymbol.uppercased().trimmingCharacters(in: .whitespaces),
                               threshold: threshold, alertType: newAlertType)
        priceAlerts.append(alert)
        newAlertSymbol = ""
        newAlertThreshold = ""
    }

    private func deleteAlert(id: UUID) {
        priceAlerts.removeAll { $0.id == id }
    }

    private func saveAndClose() {
        var cfg = AppConfig()
        cfg.leftCoin     = effectiveLeftCoin
        cfg.rightCoin    = effectiveRightCoin
        cfg.dataSource   = dataSource
        cfg.priceAlerts  = priceAlerts
        cfg.launchAtLogin = launchAtLogin
        onSave(cfg)
        NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
    }

    private func formatAlertPrice(_ price: Double) -> String {
        if price >= 1 { return String(format: "$%.2f", price) }
        return String(format: "$%.6f", price)
    }
}
