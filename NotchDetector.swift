import AppKit

class NotchDetector {
    static let shared = NotchDetector()
    
    struct NotchInfo {
        let hasNotch: Bool
        let rect: NSRect
        let screenFrame: NSRect
    }
    
    func getNotchInfo() -> NotchInfo {
        guard let screen = NSScreen.main else {
            return NotchInfo(hasNotch: false, rect: .zero, screenFrame: .zero)
        }

        let screenFrame = screen.frame
        let safeArea = screen.safeAreaInsets

        if safeArea.top > 0 {
            let notchHeight = safeArea.top
            let notchY = screenFrame.height - notchHeight

            // 用 rect 坐标边界精确定位灵动岛
            if let leftRect  = screen.auxiliaryTopLeftArea,
               let rightRect = screen.auxiliaryTopRightArea {
                let notchX     = leftRect.maxX
                let notchWidth = rightRect.minX - leftRect.maxX

                return NotchInfo(
                    hasNotch: true,
                    rect: NSRect(x: notchX, y: notchY, width: max(notchWidth, 60), height: notchHeight),
                    screenFrame: screenFrame
                )
            }

            // 兜底：居中估算
            let notchWidth: CGFloat = 82
            return NotchInfo(
                hasNotch: true,
                rect: NSRect(x: (screenFrame.width - notchWidth) / 2,
                             y: notchY, width: notchWidth, height: notchHeight),
                screenFrame: screenFrame
            )
        }

        return NotchInfo(hasNotch: false, rect: .zero, screenFrame: screenFrame)
    }
}
