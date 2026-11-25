import AppKit

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        
        HotKeyManager.shared.onHotKeyTriggered = {
            PanelController.shared.toggle()
        }
        HotKeyManager.shared.registerDefaultHotKey()
        
        ClipboardMonitor.shared.startMonitoring()
        
        print("PasteFlow v1.2.0 initialized successfully.")
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
        menu.addItem(NSMenuItem(title: "Add Account / Password... (⌘N)", action: #selector(addAccount), keyEquivalent: "n"))
        menu.addItem(NSMenuItem.separator())
        
        let pauseTitle = HistoryStore.shared.isMonitoringPaused ? "Resume Tracking" : "Pause Tracking"
        menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem(title: "Clear History (Keep Pinned & Accounts)", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "About PasteFlow v1.2.0 (by Quốc Ngô)", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit PasteFlow", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc private func togglePanel() {
        PanelController.shared.toggle()
    }
    
    @objc private func addAccount() {
        if !PanelController.shared.isVisible {
            PanelController.shared.show()
        }
        NSApp.activate(ignoringOtherApps: true)
        HistoryStore.shared.isCredentialModalPresented = true
    }
    
    @objc private func togglePause() {
        HistoryStore.shared.isMonitoringPaused.toggle()
    }
    
    @objc private func clearHistory() {
        HistoryStore.shared.clearHistory()
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PasteFlow v1.2.0"
        alert.informativeText = "Next-Gen Native Clipboard & Credential Manager\n\nDeveloped with ❤️ by Quốc Ngô (@lengo0951)\nPowered by Swift 6, AES-256-GCM Vault & QuocNgoKit ⚡\n\nUltra-low memory, instant speed, privacy-first."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "GitHub")
        if alert.runModal() == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/lengo0951/PasteFlow") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
