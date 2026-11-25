import AppKit

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Install standard MainMenu with Edit shortcuts (⌘V Paste, ⌘C Copy, ⌘X Cut, ⌘A Select All, ⌘Z Undo)
        // Required for LSUIElement / accessory apps so TextFields & SecureFields accept ⌘V paste!
        setupMainMenu()
        
        // 2. Setup status item in system menu bar
        setupStatusItem()
        
        // 3. Setup hotkey manager for Cmd+Shift+V
        HotKeyManager.shared.onHotKeyTriggered = {
            PanelController.shared.toggle()
        }
        HotKeyManager.shared.registerDefaultHotKey()
        
        // 4. Start monitoring system clipboard
        ClipboardMonitor.shared.startMonitoring()
        
        print("PATE v1.2.0 initialized successfully.")
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // Application Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About PATE", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit PATE", action: #selector(quitApp), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
        // Edit Menu (Enables standard ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z in all TextFields and SecureFields)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "PATE")
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
        
        menu.addItem(NSMenuItem(title: "Toggle PATE (⌘⇧V)", action: #selector(togglePanel), keyEquivalent: "V"))
        menu.addItem(NSMenuItem(title: "Add Account / Password... (⌘N)", action: #selector(addAccount), keyEquivalent: "n"))
        menu.addItem(NSMenuItem.separator())
        
        let pauseTitle = HistoryStore.shared.isMonitoringPaused ? "Resume Tracking" : "Pause Tracking"
        menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem(title: "Clear History (Keep Pinned & Accounts)", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "About PATE v1.2.0 (by Quốc Ngô)", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit PATE", action: #selector(quitApp), keyEquivalent: "q"))
        
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
        alert.messageText = "PATE v1.2.0"
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
