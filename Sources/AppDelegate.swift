import AppKit

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup status item in system menu bar
        setupStatusItem()
        
        // Setup hotkey manager for Cmd+Shift+V
        HotKeyManager.shared.onHotKeyTriggered = {
            PanelController.shared.toggle()
        }
        HotKeyManager.shared.registerDefaultHotKey()
        
        // Start monitoring system clipboard
        ClipboardMonitor.shared.startMonitoring()
        
        print("PasteFlow initialized successfully.")
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "PasteFlow")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            PanelController.shared.toggle()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Toggle PasteFlow (⌘⇧V)", action: #selector(togglePanel), keyEquivalent: "V"))
        menu.addItem(NSMenuItem.separator())
        
        let pauseTitle = HistoryStore.shared.isMonitoringPaused ? "Resume Tracking" : "Pause Tracking"
        menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "About PasteFlow (by Quốc Ngô)", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit PasteFlow", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // Reset so left click toggles directly
    }
    
    @objc private func togglePanel() {
        PanelController.shared.toggle()
    }
    
    @objc private func togglePause() {
        HistoryStore.shared.isMonitoringPaused.toggle()
    }
    
    @objc private func clearHistory() {
        HistoryStore.shared.clearHistory()
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PasteFlow v1.1.0"
        alert.informativeText = "Next-Gen Native macOS Clipboard Manager\n\nDeveloped with ❤️ by Quốc Ngô (@lengo0951)\nPowered by Swift 6 & QuocNgoKit ⚡\n\nUltra-low memory, instant speed, privacy-first."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "GitHub")
        if alert.runModal() == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/lengo0951/quocngokit") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
