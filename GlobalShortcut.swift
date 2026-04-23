import Carbon
import AppKit

class GlobalShortcut {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback
        
        // 注册热键
        let hotKeyID = EventHotKeyID(signature: 0x43524953, id: 1001) // 'CRIS' in hex
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status != noErr {
            NSLog("CryptoIsland: RegisterEventHotKey failed with status \(status)")
        }
        self.hotKeyRef = hotKeyRef
        
        // 注册事件处理器
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handlerCallback: EventHandlerUPP = { _, _, userInfo in
            guard let userInfo = userInfo else { return noErr }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userInfo).takeUnretainedValue()
            shortcut.callback()
            return noErr
        }
        
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), handlerCallback, 1, &eventType, selfPtr, &eventHandler)
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}
