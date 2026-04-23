import AppKit
import SwiftUI

class IslandOverlayWindow: NSWindow {
    static let overlayHeight: CGFloat = 46  // 菜单栏高度 + H/L 副行

    init(contentView: NSView) {
        let screenRect = NSScreen.main?.frame ?? .zero
        let windowHeight: CGFloat = Self.overlayHeight
        let rect = NSRect(x: 0, y: screenRect.height - windowHeight, width: screenRect.width, height: windowHeight)
        
        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .statusBar // 确保在菜单栏之上
        self.ignoresMouseEvents = true // 关键：忽略鼠标点击，不干扰正常操作
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        self.contentView = contentView
    }
    
    // 允许窗口在没有标题栏的情况下移动或调整（虽然我们不需要移动它）
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}
