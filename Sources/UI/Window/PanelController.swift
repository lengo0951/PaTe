import AppKit
import SwiftUI

@MainActor
public class PanelController: NSObject {
    public static let shared = PanelController()
    
    private var panel: FloatingPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var idleReclaimWorkItem: DispatchWorkItem?
    public private(set) var isVisible: Bool = false
    public var isSettingsSheetOpen: Bool = false
    public var isAddPinboardSheetOpen: Bool = false
    
    private override init() {
        super.init()
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
        
        newPanel.contentView = FirstMouseHostingView(rootView: contentView)
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
    
    /// Checks if any text input (in panel or attached modal sheet) currently holds focus
    private func isAnyTextInputFocused() -> Bool {
        if let keyWin = NSApp.keyWindow, keyWin.firstResponder is NSText {
            return true
        }
        if let p = self.panel, p.firstResponder is NSText {
            return true
        }
        if let sheet = self.panel?.attachedSheet, sheet.firstResponder is NSText {
            return true
        }
        return false
    }
    
    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            let store = HistoryStore.shared
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isModalOpen = store.isAnyModalPresented || self.isSettingsSheetOpen || self.isAddPinboardSheetOpen
            let isTextFocused = self.isAnyTextInputFocused()
            
            // 0. Guarantee ⌘V (Paste), ⌘C (Copy), ⌘X (Cut), ⌘A (Select All), ⌘Z (Undo)
            // ALWAYS work inside any focused TextField or SecureField (including Add Account modal!)
            if isTextFocused && flags == .command {
                switch event.keyCode {
                case 9: // Cmd + V (Paste into TextField/SecureField)
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    return nil
                case 8: // Cmd + C (Copy from TextField)
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    return nil
                case 7: // Cmd + X (Cut from TextField)
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    return nil
                case 0: // Cmd + A (Select All in TextField)
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    return nil
                case 6: // Cmd + Z (Undo in TextField)
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    return nil
                default:
                    break
                }
            }
            
            // Let modal sheets handle all other keys (typing, Tab, Return to Save, Esc to Cancel)
            if isModalOpen {
                return event
            }
            
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
            
            // 2. Return (36) OR Keypad Enter (76) -> ALWAYS PASTE / SMART AUTO-FILL IMMEDIATELY!
            if event.keyCode == 36 || event.keyCode == 76 {
                if let item = self.selectedOrFirstItem() {
                    if item.contentType == .credential {
                        if flags.contains(.shift) {
                            self.paste(item: item, asPlainText: true, credentialMode: .smartAutoFillAndSubmit)
                        } else if flags.contains(.option) {
                            self.paste(item: item, asPlainText: true, credentialMode: .passwordOnly)
                        } else {
                            self.paste(item: item, asPlainText: true, credentialMode: .smartAutoFill)
                        }
                    } else {
                        let invertPlain = flags.contains(.option) || flags.contains(.shift)
                        let asPlain = invertPlain
                            ? !AppConfig.shared.pastePlainTextByDefault
                            : AppConfig.shared.pastePlainTextByDefault
                        self.paste(item: item, asPlainText: asPlain, credentialMode: .smartAutoFill)
                    }
                }
                return nil
            }
            
            // 3. Cmd + U (32) -> Type Username & Pre-load Password to Clipboard (for 2-Step Logins)
            if event.keyCode == 32 && flags.contains(.command) {
                if let item = self.selectedOrFirstItem(), item.contentType == .credential {
                    self.paste(item: item, asPlainText: true, credentialMode: .usernameOnlyAndPreloadSecret)
                    return nil
                }
            }
            
            // 4. Cmd + N (45) -> Open Add Account / Password modal
            if event.keyCode == 45 && flags.contains(.command) {
                NSApp.activate(ignoringOtherApps: true)
                store.isCredentialModalPresented = true
                return nil
            }
            
            // 5. Left Arrow (123) & Right Arrow (124) -> Navigate cards unless editing search query
            if event.keyCode == 123 && (!isTextFocused || store.searchQuery.isEmpty || flags.contains(.command)) {
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
            
            if event.keyCode == 124 && (!isTextFocused || store.searchQuery.isEmpty || flags.contains(.command)) {
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
            if event.keyCode == 49 && !isTextFocused && store.searchQuery.isEmpty {
                if let item = self.selectedOrFirstItem() {
                    store.activeQuickLookItem = item
                }
                return nil
            }
            
            // 7. Delete / Backspace (51) -> Delete selected clip when not typing in search
            if event.keyCode == 51 && !isTextFocused && store.searchQuery.isEmpty {
                if let currentID = store.selectedItemID {
                    store.removeItem(id: currentID)
                    store.selectedItemID = store.filteredItems.first?.id
                }
                return nil
            }
            
            // 8. Cmd + P or 'P' (35) -> Pin
            if event.keyCode == 35 && (flags.contains(.command) || (!isTextFocused && store.searchQuery.isEmpty)) {
                if let currentID = store.selectedItemID {
                    let targetPinboard = (store.selectedPinboardID != "history" && store.selectedPinboardID != "vault")
                        ? store.selectedPinboardID
                        : (store.pinboards.first(where: { !$0.isSystem })?.id ?? "pinned")
                    store.togglePin(itemID: currentID, pinboardID: targetPinboard)
                }
                return nil
            }
            
            // 9. Cmd + C (8) -> Copy selected clip or credential secret to clipboard
            if event.keyCode == 8 && flags.contains(.command) && !isTextFocused {
                if let item = self.selectedOrFirstItem() {
                    if item.contentType == .credential {
                        if flags.contains(.shift) {
                            PasteSimulator.shared.copyCredentialToClipboard(item, usernameOnly: true)
                        } else {
                            PasteSimulator.shared.copyCredentialToClipboard(item, usernameOnly: false)
                        }
                    } else if let text = item.textValue {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
                        NSPasteboard.general.setString(text, forType: .string)
                        SoundManager.shared.playCopy()
                    }
                }
                return nil
            }
            
            // 10. Cmd + R or 'R' (15) -> Rename / Edit Credential
            if event.keyCode == 15 && (flags.contains(.command) || (!isTextFocused && store.searchQuery.isEmpty)) {
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
                    : (flags.contains(.command) || (!isTextFocused && store.searchQuery.isEmpty))
                if canFire {
                    let items = store.filteredItems
                    let index = number - 1
                    if index >= 0 && index < items.count {
                        self.paste(
                            item: items[index],
                            asPlainText: AppConfig.shared.pastePlainTextByDefault,
                            credentialMode: .smartAutoFill
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
        idleReclaimWorkItem?.cancel()
        idleReclaimWorkItem = nil
        setupPanel()
        guard let panel = panel else { return }
        
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            PasteSimulator.shared.lastFrontmostApplication = frontApp
        }
        
        // Refresh live macOS Accessibility TCC status so HUD warns immediately if permission was reset
        HistoryStore.shared.isAccessibilityGranted = PasteSimulator.shared.isAccessibilityGranted
        
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
        
        // Activate PasteFlow + makeKeyAndOrderFront so Enter, Arrows, and Double-Click ALWAYS reach the HUD!
        NSApp.activate(ignoringOtherApps: true)
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
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.scheduleIdleMemoryReclamation()
            }
        })
    }
    
    /// Reclaims decoded image caches immediately on hide, and tears down the SwiftUI NSHostingView
    /// & CoreAnimation backing store after 20s idle so background RAM drops to ~15-22 MB!
    private func scheduleIdleMemoryReclamation() {
        HistoryStore.shared.purgeMemoryCaches()
        idleReclaimWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isVisible, !HistoryStore.shared.isAnyModalPresented else { return }
            self.panel?.contentView = nil
            self.panel?.close()
            self.panel = nil
            HistoryStore.shared.purgeMemoryCaches()
        }
        idleReclaimWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0, execute: work)
    }
    
    public func paste(
        item: ClipboardItem,
        asPlainText: Bool,
        credentialMode: CredentialPasteMode = .smartAutoFill
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
        NSApp.hide(nil)
        scheduleIdleMemoryReclamation()
        
        PasteSimulator.shared.pasteItem(
            item,
            asPlainText: asPlainText,
            credentialMode: credentialMode,
            store: HistoryStore.shared
        )
    }
}
