import AppKit
import SwiftUI

public class FloatingPanel: NSPanel {
    public var onEscapePressed: (() -> Void)?
    public var onQuickPastePressed: ((Int) -> Void)?
    public var onReturnPressed: (() -> Void)?
    public var onReturnPressedWithOption: ((Bool) -> Void)?
    public var onSpacebarPressed: (() -> Void)?
    public var onNavigateLeft: (() -> Void)?
    public var onNavigateRight: (() -> Void)?
    public var onDeletePressed: (() -> Void)?
    
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
    
    public override func keyDown(with event: NSEvent) {
        // Escape = 53
        if event.keyCode == 53 {
            onEscapePressed?()
            return
        }
        
        // Return / Enter = 36
        if event.keyCode == 36 {
            let isPlainText = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift)
            if isPlainText {
                onReturnPressedWithOption?(true)
            } else {
                onReturnPressed?()
            }
            return
        }
        
        // Spacebar = 49 (Quick Look)
        if event.keyCode == 49 {
            if HistoryStore.shared.searchQuery.isEmpty {
                onSpacebarPressed?()
                return
            }
        }
        
        // Left Arrow = 123
        if event.keyCode == 123 {
            onNavigateLeft?()
            return
        }
        
        // Right Arrow = 124
        if event.keyCode == 124 {
            onNavigateRight?()
            return
        }
        
        // Delete / Backspace = 51
        if event.keyCode == 51 {
            onDeletePressed?()
            return
        }
        
        // Number keys 1-9 (keyCodes: 18=1, 19=2, 20=3, 21=4, 23=5, 22=6, 26=7, 28=8, 25=9)
        let numberKeyCodes: [UInt16: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
        ]
        if let number = numberKeyCodes[event.keyCode] {
            // Only trigger quick paste if search query is empty or cmd modifier is used
            if HistoryStore.shared.searchQuery.isEmpty || event.modifierFlags.contains(.command) {
                onQuickPastePressed?(number)
                return
            }
        }
        
        super.keyDown(with: event)
    }
}
