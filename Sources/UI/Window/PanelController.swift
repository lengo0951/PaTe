import AppKit
import SwiftUI

@MainActor
public class PanelController: NSObject {
    public static let shared = PanelController()
    
    private var panel: FloatingPanel?
    private var globalClickMonitor: Any?
    public private(set) var isVisible: Bool = false
    
    private override init() {
        super.init()
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
        
        // Host the SwiftUI MainContentView
        let contentView = MainContentView(
            store: HistoryStore.shared,
            onPaste: { [weak self] item, asPlainText in
                self?.paste(item: item, asPlainText: asPlainText)
            }
        )
        
        newPanel.contentView = NSHostingView(rootView: contentView)
        
        // Setup keyboard callbacks
        newPanel.onEscapePressed = { [weak self] in
            if HistoryStore.shared.activeQuickLookItem != nil {
                HistoryStore.shared.activeQuickLookItem = nil
            } else {
                self?.hide()
            }
        }
        
        newPanel.onQuickPastePressed = { [weak self] number in
            let items = HistoryStore.shared.filteredItems
            let index = number - 1
            if index >= 0 && index < items.count {
                self?.paste(item: items[index], asPlainText: AppConfig.shared.pastePlainTextByDefault)
            }
        }
        
        newPanel.onReturnPressed = { [weak self] in
            let items = HistoryStore.shared.filteredItems
            let defaultPlain = AppConfig.shared.pastePlainTextByDefault
            if let selectedID = HistoryStore.shared.selectedItemID,
               let item = items.first(where: { $0.id == selectedID }) {
                self?.paste(item: item, asPlainText: defaultPlain)
            } else if let first = items.first {
                self?.paste(item: first, asPlainText: defaultPlain)
            }
        }
        
        newPanel.onReturnPressedWithOption = { [weak self] _ in
            let items = HistoryStore.shared.filteredItems
            let asPlain = !AppConfig.shared.pastePlainTextByDefault
            if let selectedID = HistoryStore.shared.selectedItemID,
               let item = items.first(where: { $0.id == selectedID }) {
                self?.paste(item: item, asPlainText: asPlain)
            } else if let first = items.first {
                self?.paste(item: first, asPlainText: asPlain)
            }
        }
        
        newPanel.onSpacebarPressed = {
            if HistoryStore.shared.activeQuickLookItem != nil {
                HistoryStore.shared.activeQuickLookItem = nil
            } else {
                let items = HistoryStore.shared.filteredItems
                if let selectedID = HistoryStore.shared.selectedItemID,
                   let item = items.first(where: { $0.id == selectedID }) {
                    HistoryStore.shared.activeQuickLookItem = item
                } else if let first = items.first {
                    HistoryStore.shared.activeQuickLookItem = first
                }
            }
        }
        
        newPanel.onNavigateLeft = {
            let items = HistoryStore.shared.filteredItems
            guard !items.isEmpty else { return }
            if let currentID = HistoryStore.shared.selectedItemID,
               let currentIndex = items.firstIndex(where: { $0.id == currentID }),
               currentIndex > 0 {
                HistoryStore.shared.selectedItemID = items[currentIndex - 1].id
            } else {
                HistoryStore.shared.selectedItemID = items.first?.id
            }
        }
        
        newPanel.onNavigateRight = {
            let items = HistoryStore.shared.filteredItems
            guard !items.isEmpty else { return }
            if let currentID = HistoryStore.shared.selectedItemID,
               let currentIndex = items.firstIndex(where: { $0.id == currentID }),
               currentIndex < items.count - 1 {
                HistoryStore.shared.selectedItemID = items[currentIndex + 1].id
            } else {
                HistoryStore.shared.selectedItemID = items.first?.id
            }
        }
        
        newPanel.onDeletePressed = {
            if let currentID = HistoryStore.shared.selectedItemID {
                HistoryStore.shared.removeItem(id: currentID)
            }
        }
        
        newPanel.onPinPressed = {
            if let currentID = HistoryStore.shared.selectedItemID {
                let targetPinboard = HistoryStore.shared.selectedPinboardID != "history"
                    ? HistoryStore.shared.selectedPinboardID
                    : (HistoryStore.shared.pinboards.first(where: { !$0.isSystem })?.id ?? "pinned")
                HistoryStore.shared.togglePin(itemID: currentID, pinboardID: targetPinboard)
            }
        }
        
        newPanel.onCopyPressed = {
            if let currentID = HistoryStore.shared.selectedItemID,
               let item = HistoryStore.shared.items.first(where: { $0.id == currentID }) {
                NSPasteboard.general.clearContents()
                if let text = item.textValue {
                    NSPasteboard.general.setString(text, forType: .string)
                }
                SoundManager.shared.playCopy()
            }
        }
        
        newPanel.onRenamePressed = {
            let items = HistoryStore.shared.filteredItems
            if let selectedID = HistoryStore.shared.selectedItemID,
               let item = items.first(where: { $0.id == selectedID }) {
                HistoryStore.shared.itemBeingRenamed = item
            } else if let first = items.first {
                HistoryStore.shared.itemBeingRenamed = first
            }
        }
        
        self.panel = newPanel
    }
    
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    public func show() {
        setupPanel()
        guard let panel = panel else { return }
        
        // Save the current frontmost application so we can paste to it later!
        PasteSimulator.shared.lastFrontmostApplication = NSWorkspace.shared.frontmostApplication
        
        // Select first item by default
        if let first = HistoryStore.shared.filteredItems.first {
            HistoryStore.shared.selectedItemID = first.id
        }
        
        // Reposition to the active screen
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
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Slide-up animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                NSRect(x: rect.origin.x, y: targetY, width: panelWidth, height: panelHeight),
                display: true
            )
            panel.animator().alphaValue = 1.0
        }
        
        isVisible = true
        
        // Monitor clicks outside window to dismiss
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return }
            let clickLoc = NSEvent.mouseLocation
            if !NSPointInRect(clickLoc, panel.frame) {
                self.hide()
            }
        }
    }
    
    public func hide() {
        guard let panel = panel, isVisible else { return }
        
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        
        let currentFrame = panel.frame
        let hiddenY = currentFrame.minY - currentFrame.height
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(
                NSRect(x: currentFrame.origin.x, y: hiddenY, width: currentFrame.width, height: currentFrame.height),
                display: true
            )
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.isVisible = false
            }
        })
    }
    
    private func paste(item: ClipboardItem, asPlainText: Bool) {
        hide()
        PasteSimulator.shared.pasteItem(
            item,
            asPlainText: asPlainText,
            store: HistoryStore.shared
        )
    }
}
