import AppKit
import SwiftUI

@MainActor
public class PanelController: NSObject {
    public static let shared = PanelController()
    
    private var panel: FloatingPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    public private(set) var isVisible: Bool = false
    public var isSettingsSheetOpen: Bool = false
    public var isAddPinboardSheetOpen: Bool = false
    
    private override init() {
        super.init()
        // Ensure PasteSimulator starts observing active apps immediately
        _ = PasteSimulator.shared
    }
    
    private var currentPanelHeight: CGFloat {
        return AppConfig.shared.showShortcutHints ? 318 : 290
    }
    
    public func setupPanel() {
        guard panel == nil else { return }
        
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let panelWidth = min(screenFrame.width - 48, 1280)
        let panelHeight = currentPanelHeight
        
        let initialRect = NSRect(
            x: screenFrame.midX - (panelWidth / 2),
            y: screenFrame.minY + 16,
            width: panelWidth,
            height: panelHeight
        )
        
        let newPanel = FloatingPanel(contentRect: initialRect)
        
        let contentView = MainContentView(
            store: HistoryStore.shared,
            onPaste: { [weak self] item, asPlainText, credMode in
                self?.paste(item: item, asPlainText: asPlainText, credentialMode: credMode)
            }
        )
        
        newPanel.contentView = NSHostingView(rootView: contentView)
        self.panel = newPanel
    }
    
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    private func selectedOrFirstItem() -> ClipboardItem? {
        let items = HistoryStore.shared.filteredItems
        if let selectedID = HistoryStore.shared.selectedItemID,
           let item = items.first(where: { $0.id == selectedID }) {
            return item
        }
        return items.first
    }
    
    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            let store = HistoryStore.shared
            
            // Let modal sheets handle their own keyboard shortcuts cleanly
            if store.isAnyModalPresented || self.isSettingsSheetOpen || self.isAddPinboardSheetOpen {
                return event
            }
            
            let isTextFieldFocused = (self.panel?.firstResponder is NSTextView)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // 1. Escape (53): Clear search first if active, otherwise close HUD
            if event.keyCode == 53 {
                if !store.searchQuery.isEmpty {
                    store.searchQuery = ""
                    self.panel?.makeFirstResponder(self.panel)
                } else {
                    self.hide()
                }
                return nil
            }
            
            // 2. Return (36) OR Keypad Enter (76) -> ALWAYS PASTE SELECTED ITEM IMMEDIATELY!
            if event.keyCode == 36 || event.keyCode == 76 {
                if let item = self.selectedOrFirstItem() {
                    if item.contentType == .credential && flags.contains(.command) && flags.contains(.shift) {
                        self.paste(item: item, asPlainText: false, credentialMode: .autoFillTab)
                    } else {
                        let invertPlain = flags.contains(.option) || flags.contains(.shift)
                        let asPlain = invertPlain
                            ? !AppConfig.shared.pastePlainTextByDefault
                            : AppConfig.shared.pastePlainTextByDefault
                        self.paste(item: item, asPlainText: asPlain, credentialMode: .defaultSecret)
                    }
                }
                return nil
            }
            
            // 3. Cmd + U (32) -> Paste Username for Credential item
            if event.keyCode == 32 && flags.contains(.command) {
                if let item = self.selectedOrFirstItem(), item.contentType == .credential {
                    self.paste(item: item, asPlainText: true, credentialMode: .usernameOnly)
                    return nil
                }
            }
            
            // 4. Cmd + N (45) -> Open Add Account / Password modal
            if event.keyCode == 45 && flags.contains(.command) {
                NSApp.activate(ignoringOtherApps: true)
                store.isCredentialModalPresented = true
                return nil
            }
            
            // 5. Left Arrow (123) & Right Arrow (124) -> Navigate cards unless editing middle of search query
            if event.keyCode == 123 && (!isTextFieldFocused || store.searchQuery.isEmpty || flags.contains(.command)) {
                let items = store.filteredItems
                if !items.isEmpty {
                    store.lastSelectionWasKeyboard = true
                    if let currentID = store.selectedItemID,
                       let idx = items.firstIndex(where: { $0.id == currentID }),
                       idx > 0 {
                        store.selectedItemID = items[idx - 1].id
                    } else {
                        store.selectedItemID = items.first?.id
                    }
                }
                return nil
            }
            
            if event.keyCode == 124 && (!isTextFieldFocused || store.searchQuery.isEmpty || flags.contains(.command)) {
                let items = store.filteredItems
                if !items.isEmpty {
                    store.lastSelectionWasKeyboard = true
                    if let currentID = store.selectedItemID,
                       let idx = items.firstIndex(where: { $0.id == currentID }),
                       idx < items.count - 1 {
                        store.selectedItemID = items[idx + 1].id
                    } else {
                        store.selectedItemID = items.first?.id
                    }
                }
                return nil
            }
            
            // 6. Spacebar (49) -> Quick Look when not typing in search
            if event.keyCode == 49 && !isTextFieldFocused && store.searchQuery.isEmpty {
                if let item = self.selectedOrFirstItem() {
                    store.activeQuickLookItem = item
                }
                return nil
            }
            
            // 7. Delete / Backspace (51) -> Delete selected clip when not typing in search
            if event.keyCode == 51 && !isTextFieldFocused && store.searchQuery.isEmpty {
                if let currentID = store.selectedItemID {
                    store.removeItem(id: currentID)
                    store.selectedItemID = store.filteredItems.first?.id
                }
                return nil
            }
            
            // 8. Cmd + P or 'P' (35) -> Pin
            if event.keyCode == 35 && (flags.contains(.command) || (!isTextFieldFocused && store.searchQuery.isEmpty)) {
                if let currentID = store.selectedItemID {
                    let targetPinboard = (store.selectedPinboardID != "history" && store.selectedPinboardID != "vault")
                        ? store.selectedPinboardID
                        : (store.pinboards.first(where: { !$0.isSystem })?.id ?? "pinned")
                    store.togglePin(itemID: currentID, pinboardID: targetPinboard)
                }
                return nil
            }
            
            // 9. Cmd + C (8) -> Copy to clipboard without closing
            if event.keyCode == 8 && flags.contains(.command) && !isTextFieldFocused {
                if let item = self.selectedOrFirstItem() {
                    NSPasteboard.general.clearContents()
                    if item.contentType == .credential {
                        if let secret = CredentialVault.shared.getSecret(for: item.id) {
                            NSPasteboard.general.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                            NSPasteboard.general.setString(secret, forType: .string)
                        }
                    } else if let text = item.textValue {
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    SoundManager.shared.playCopy()
                }
                return nil
            }
            
            // 10. Cmd + R or 'R' (15) -> Rename / Edit Credential
            if event.keyCode == 15 && (flags.contains(.command) || (!isTextFieldFocused && store.searchQuery.isEmpty)) {
                if let item = self.selectedOrFirstItem() {
                    NSApp.activate(ignoringOtherApps: true)
                    if item.contentType == .credential {
                        store.credentialItemBeingEdited = item
                    } else {
                        store.itemBeingRenamed = item
                    }
                }
                return nil
            }
            
            // 11. Quick Paste 1..9
            let numberKeyCodes: [UInt16: Int] = [
                18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
            ]
            if let number = numberKeyCodes[event.keyCode] {
                let requiresCmd = AppConfig.shared.quickPasteWithCmd
                let canFire = requiresCmd
                    ? flags.contains(.command)
                    : (flags.contains(.command) || (!isTextFieldFocused && store.searchQuery.isEmpty))
                if canFire {
                    let items = store.filteredItems
                    let index = number - 1
                    if index >= 0 && index < items.count {
                        self.paste(
                            item: items[index],
                            asPlainText: AppConfig.shared.pastePlainTextByDefault,
                            credentialMode: .defaultSecret
                        )
                    }
                    return nil
                }
            }
            
            return event
        }
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
    
    public func show() {
        setupPanel()
        guard let panel = panel else { return }
        
        // Record external frontmost app only if it is not PasteFlow itself
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            PasteSimulator.shared.lastFrontmostApplication = frontApp
        }
        
        // Select first item by default
        HistoryStore.shared.lastSelectionWasKeyboard = false
        if let first = HistoryStore.shared.filteredItems.first {
            HistoryStore.shared.selectedItemID = first.id
        }
        
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens[0]
        let screenFrame = targetScreen.visibleFrame
        let panelWidth = min(screenFrame.width - 48, 1280)
        let panelHeight = currentPanelHeight
        
        let targetY = screenFrame.minY + 16
        let startY = screenFrame.minY - panelHeight
        
        let rect = NSRect(
            x: screenFrame.midX - (panelWidth / 2),
            y: startY,
            width: panelWidth,
            height: panelHeight
        )
        panel.setFrame(rect, display: true)
        panel.alphaValue = 0.0
        
        // True non-activating key panel: keeps target editor's cursor active while receiving input!
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                NSRect(x: rect.origin.x, y: targetY, width: panelWidth, height: panelHeight),
                display: true
            )
            panel.animator().alphaValue = 1.0
        }
        
        isVisible = true
        installKeyboardMonitor()
        
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }
            let clickLoc = NSEvent.mouseLocation
            if !NSPointInRect(clickLoc, panel.frame) && !HistoryStore.shared.isAnyModalPresented {
                self.hide()
            }
        }
    }
    
    public func hide() {
        guard let panel = panel, isVisible else { return }
        
        removeKeyboardMonitor()
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        
        let currentFrame = panel.frame
        let hiddenY = currentFrame.minY - currentFrame.height
        isVisible = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(
                NSRect(x: currentFrame.origin.x, y: hiddenY, width: currentFrame.width, height: currentFrame.height),
                display: true
            )
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        })
    }
    
    public func paste(
        item: ClipboardItem,
        asPlainText: Bool,
        credentialMode: CredentialPasteMode = .defaultSecret
    ) {
        removeKeyboardMonitor()
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let panel = panel {
            panel.orderOut(nil)
            isVisible = false
        }
        PasteSimulator.shared.pasteItem(
            item,
            asPlainText: asPlainText,
            credentialMode: credentialMode,
            store: HistoryStore.shared
        )
    }
}
