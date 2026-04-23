import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import Combine

@main
struct CryptoIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(config: appDelegate.config) { newConfig in
                appDelegate.updateConfig(newConfig: newConfig)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var overlayWindow:  IslandOverlayWindow?
    var leftClickWindow:  SingleClickWindow?
    var rightClickWindow: SingleClickWindow?
    var detailWindow:   CoinDetailWindow?
    var settingsWindow: NSWindow?

    @Published var service      = BinanceService()
    @Published var config       = AppConfig()
    @Published var islandState  = IslandInteractionState()

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfig()
        requestNotificationPermission()
        setupServiceCallbacks()

        let screenRect = NSScreen.main?.frame ?? .zero
        let notchInfo = NotchDetector.shared.getNotchInfo()
        let notchRect = notchInfo.hasNotch ? notchInfo.rect : NSRect(x: (screenRect.width - 179)/2, y: screenRect.height - 32, width: 179, height: 32)
        
        let tickerW = CoinDetailPanelView.tickerSideWidth
        let offset  = CoinDetailPanelView.tickerOffset
        let barH    = IslandOverlayWindow.overlayHeight

        // 主 overlay（只显示内容，穿透鼠标）
        let islandView = IslandView(service: service)
        let hostingView = NSHostingView(rootView: islandView)
        hostingView.frame = NSRect(x: 0, y: 0, width: screenRect.width, height: barH)
        overlayWindow = IslandOverlayWindow(contentView: hostingView)
        overlayWindow?.orderFront(nil)

        // 左点击捕获窗口
        let leftRect = NSRect(x: notchRect.minX - tickerW + offset, y: screenRect.height - 32, width: tickerW, height: 32)
        leftClickWindow = SingleClickWindow(rect: leftRect, side: .left, state: islandState)
        leftClickWindow?.orderFront(nil)

        // 右点击捕获窗口
        let rightRect = NSRect(x: notchRect.maxX - offset, y: screenRect.height - 32, width: tickerW, height: 32)
        rightClickWindow = SingleClickWindow(rect: rightRect, side: .right, state: islandState)
        rightClickWindow?.orderFront(nil)

        // 展开面板
        detailWindow = CoinDetailWindow(state: islandState, service: service)
        detailWindow?.orderFront(nil)

        service.startTracking(config: config)
        setupStatusItem()
    }

    // MARK: - Service Callbacks

    private func setupServiceCallbacks() {
        service.onAlertTriggered = { [weak self] alertId in
            guard let self else { return }
            config.priceAlerts = config.priceAlerts.map { a in
                var copy = a
                if copy.id == alertId { copy.isActive = false }
                return copy
            }
            saveConfig()
        }
        service.onAutoSwitchDataSource = { [weak self] newSource in
            guard let self else { return }
            config.dataSource = newSource
            saveConfig()
        }
    }

    // MARK: - Status Bar

    private var statusItem: NSStatusItem?

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bitcoinsign.circle",
                                   accessibilityDescription: "Crypto Island")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(config: config) { [weak self] newConfig in
                self?.updateConfig(newConfig: newConfig)
            }
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = "Crypto Island 设置"
            window.contentViewController = controller
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Config

    func updateConfig(newConfig: AppConfig) {
        let oldLaunchAtLogin = config.launchAtLogin
        config = newConfig
        saveConfig()
        // 切换数据源时收起展开面板
        islandState.expandedSide = .none
        service.startTracking(config: config)
        if newConfig.launchAtLogin != oldLaunchAtLogin {
            setLaunchAtLogin(newConfig.launchAtLogin)
        }
    }

    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: "AppConfig"),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        }
    }

    private func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "AppConfig")
        }
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else        { try SMAppService.mainApp.unregister() }
                return
            } catch {
                NSLog("CryptoIsland: SMAppService error: \(error)")
            }
        }
        appleScriptLaunchAtLogin(enabled)
    }

    private func appleScriptLaunchAtLogin(_ enabled: Bool) {
        let path = Bundle.main.bundlePath
        let script = enabled
            ? "tell application \"System Events\" to make login item at end with properties {path:\"\(path)\", hidden:false}"
            : "tell application \"System Events\" to delete login item \"CryptoIsland\""
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
