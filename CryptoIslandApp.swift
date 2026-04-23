import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import Combine
import Carbon

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
    static var shared: AppDelegate?

    var overlayWindow:    IslandOverlayWindow?
    var leftClickWindow:  SingleClickWindow?
    var rightClickWindow: SingleClickWindow?
    var detailWindow:     CoinDetailWindow?
    var settingsWindow:   NSWindow?

    @Published var service       = BinanceService()
    @Published var config        = AppConfig()
    @Published var islandState   = IslandInteractionState()
    let marketService            = MarketService()
    
    private var globalShortcut: GlobalShortcut?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        loadConfig()
        requestNotificationPermission()
        setupServiceCallbacks()
        marketService.start()
        setupWindows()
        service.startTracking(config: config)
        setupStatusItem()
        observeScreenChanges()
        observePowerState()
        setupGlobalShortcut()
    }

    // MARK: - Windows Setup

    private var primaryScreen: NSScreen {
        NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
    }

    private func setupWindows() {
        let screen    = primaryScreen.frame
        let notchInfo = NotchDetector.shared.getNotchInfo()
        let notchRect = notchInfo.hasNotch
            ? notchInfo.rect
            : NSRect(x: (screen.width - 179) / 2, y: screen.height - 32, width: 179, height: 32)

        let tickerW = CoinDetailPanelView.tickerSideWidth
        let offset  = CoinDetailPanelView.tickerOffset
        let barH    = IslandOverlayWindow.overlayHeight

        // 主 overlay（穿透鼠标）
        let islandView  = IslandView(state: islandState, service: service)
        let hostingView = NSHostingView(rootView: islandView)
        hostingView.frame = NSRect(x: 0, y: 0, width: screen.width, height: barH)
        overlayWindow = IslandOverlayWindow(contentView: hostingView)
        overlayWindow?.orderFront(nil)

        // 左点击窗口
        let leftRect = NSRect(x: notchRect.minX - tickerW + offset,
                              y: screen.height - 32, width: tickerW, height: 32)
        leftClickWindow = SingleClickWindow(rect: leftRect, side: .left, state: islandState,
                                            service: service, onOpenSettings: { [weak self] in self?.openSettings() })
        leftClickWindow?.orderFront(nil)

        // 右点击窗口
        let rightRect = NSRect(x: notchRect.maxX - offset,
                               y: screen.height - 32, width: tickerW, height: 32)
        rightClickWindow = SingleClickWindow(rect: rightRect, side: .right, state: islandState,
                                             service: service, onOpenSettings: { [weak self] in self?.openSettings() })
        rightClickWindow?.orderFront(nil)

        // 展开详情面板
        detailWindow = CoinDetailWindow(state: islandState, service: service,
                                         market: marketService, holdings: config.holdings)
        detailWindow?.orderFront(nil)
    }

    private func repositionWindows() {
        let screen    = primaryScreen.frame
        let notchInfo = NotchDetector.shared.getNotchInfo()
        let notchRect = notchInfo.hasNotch
            ? notchInfo.rect
            : NSRect(x: (screen.width - 179) / 2, y: screen.height - 32, width: 179, height: 32)

        let tickerW = CoinDetailPanelView.tickerSideWidth
        let offset  = CoinDetailPanelView.tickerOffset
        let barH    = IslandOverlayWindow.overlayHeight

        overlayWindow?.setFrame(NSRect(x: 0, y: screen.height - barH, width: screen.width, height: barH),
                                display: true)

        let leftRect = NSRect(x: notchRect.minX - tickerW + offset,
                              y: screen.height - 32, width: tickerW, height: 32)
        leftClickWindow?.setFrame(leftRect, display: true)

        let rightRect = NSRect(x: notchRect.maxX - offset,
                               y: screen.height - 32, width: tickerW, height: 32)
        rightClickWindow?.setFrame(rightRect, display: true)

        // Recreate detail window to pick up new geometry
        recreateDetailWindow()
    }

    private func recreateDetailWindow() {
        detailWindow?.close()
        detailWindow = CoinDetailWindow(state: islandState, service: service,
                                         market: marketService, holdings: config.holdings)
        detailWindow?.orderFront(nil)
    }

    // MARK: - Screen Change Observer

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensDidChange() {
        NSLog("CryptoIsland: 屏幕布局变化，重新定位窗口")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.repositionWindows()
        }
    }

    // MARK: - Power State Observer

    private func observePowerState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        applyPowerState()
    }

    @objc private func powerStateDidChange() {
        applyPowerState()
    }

    private func applyPowerState() {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        NSLog("CryptoIsland: 省电模式 = \(isLowPower)")
        service.isLowPowerMode = isLowPower
        if isLowPower {
            marketService.stop()
        } else {
            marketService.start()
        }
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
    }

    // MARK: - Global Shortcut (Privacy Mode)

    private func setupGlobalShortcut() {
        // cmdKey and optionKey are from Carbon
        let modifiers = UInt32(cmdKey | optionKey)
        globalShortcut = GlobalShortcut(keyCode: 7, modifiers: modifiers) { [weak self] in
            self?.togglePrivacyMode()
        }
        NSLog("CryptoIsland: Global shortcut registered (⌘⌥X)")
    }


    private func togglePrivacyMode() {
        DispatchQueue.main.async {
            self.islandState.isPrivacyMode.toggle()
            if self.islandState.isPrivacyMode {
                self.islandState.expandedSide = .none
            }
            // Update menu checkmark if exists
            if let menu = self.statusItem?.menu, let item = menu.items.first {
                item.state = self.islandState.isPrivacyMode ? .on : .off
            }
            NSLog("CryptoIsland: Privacy Mode toggled to \(self.islandState.isPrivacyMode)")
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
        menu.addItem(NSMenuItem(title: "隐身模式 (⌘⌥X)", action: #selector(togglePrivacyModeFromMenu), keyEquivalent: "x"))
        if let item = menu.items.first { item.keyEquivalentModifierMask = [.command, .option] }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func togglePrivacyModeFromMenu() {
        togglePrivacyMode()
        // Update menu item checkmark
        if let menu = statusItem?.menu, let item = menu.items.first {
            item.state = islandState.isPrivacyMode ? .on : .off
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(config: config) { [weak self] newConfig in
                self?.updateConfig(newConfig: newConfig)
            }
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 200), // 初始高度设小点
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = "Crypto Island 设置"
            window.contentViewController = controller
            
            // 动态计算高度
            let fittingSize = controller.view.fittingSize
            window.setContentSize(NSSize(width: 420, height: fittingSize.height))
            
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
        islandState.expandedSide = .none
        service.startTracking(config: newConfig)
        recreateDetailWindow()
        if newConfig.launchAtLogin != oldLaunchAtLogin {
            setLaunchAtLogin(newConfig.launchAtLogin)
        }
    }

    private func loadConfig() {
        if let data    = UserDefaults.standard.data(forKey: "AppConfig"),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        }
    }

    func saveConfig() {
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
