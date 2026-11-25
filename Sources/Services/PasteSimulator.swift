import AppKit
import ApplicationServices
import Carbon

public enum CredentialPasteMode {
    /// Default on Enter / Double-Click:
    /// Auto-detects if cursor is already in a Password field (`AXSecureTextField`).
    /// - If in Username/Text field: Pre-loads Password to Clipboard, types Username via Unicode HID stream -> Tab -> Cmd+V Password.
    /// - If already in Password field (or no Username exists): Pastes Password only.
    case smartAutoFill
    /// Shift + Enter: Fills Username -> Tab -> Password -> Enter (submits login form).
    case smartAutoFillAndSubmit
    /// Cmd + U or "User" button: Types Username into current field AND pre-loads Password onto Clipboard for 2-step login pages.
    case usernameOnlyAndPreloadSecret
    /// Option + Enter or "Pass" button: Pastes Password only.
    case passwordOnly
}

@MainActor
public class PasteSimulator {
    public static let shared = PasteSimulator()
    
    public var lastFrontmostApplication: NSRunningApplication?
    private var secretCleanupWorkItem: DispatchWorkItem?
    
    private init() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastFrontmostApplication = front
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  app.activationPolicy == .regular else {
                return
            }
            Task { @MainActor in
                self?.lastFrontmostApplication = app
            }
        }
    }
    
    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    public func promptAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    public func openAccessibilitySettings() {
        promptAccessibilityAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Copies a credential's Username or Password directly to the system clipboard
    public func copyCredentialToClipboard(_ item: ClipboardItem, usernameOnly: Bool) {
        let value: String
        if usernameOnly {
            value = item.credentialUsername ?? ""
        } else {
            value = CredentialVault.shared.getSecret(for: item.id) ?? item.textValue ?? ""
        }
        guard !value.isEmpty else { return }
        let count = writeStringToPasteboard(value)
        SoundManager.shared.playCopy()
        if !usernameOnly {
            scheduleClipboardAutoClear(expectedChangeCount: count, delay: 60.0)
        }
    }
    
    /// Inspects the target application's currently focused Accessibility element in < 0.4ms
    /// to detect if the user's cursor is already inside an `<input type="password">` (`AXSecureTextField`).
    private func isTargetFocusedFieldSecurePassword(pid: pid_t) -> Bool {
        guard isAccessibilityGranted else { return false }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard err == .success, let focusedObj = focusedRef else { return false }
        let focusedElement = focusedObj as! AXUIElement
        
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }
        
        var roleDescRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXRoleDescriptionAttribute as CFString, &roleDescRef) == .success,
           let roleDesc = roleDescRef as? String,
           roleDesc.localizedCaseInsensitiveContains("secure") || roleDesc.localizedCaseInsensitiveContains("password") {
            return true
        }
        return false
    }
    
    public func pasteItem(
        _ item: ClipboardItem,
        asPlainText: Bool = false,
        credentialMode: CredentialPasteMode = .smartAutoFill,
        store: HistoryStore,
        completion: (() -> Void)? = nil
    ) {
        // MARK: - 1. Smart Hybrid Auto-Fill for Credential Vault Items
        if item.contentType == .credential {
            let username = (item.credentialUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = CredentialVault.shared.getSecret(for: item.id) ?? item.textValue ?? ""
            
            SoundManager.shared.playPaste()
            completion?()
            
            switch credentialMode {
            case .passwordOnly:
                let toPaste = secret.isEmpty ? username : secret
                let expectedCount = writeStringToPasteboard(toPaste)
                scheduleClipboardAutoClear(expectedChangeCount: expectedCount, delay: 60.0)
                deliverFocusToTargetApp { [weak self] _ in
                    self?.simulateCmdV()
                }
                
            case .usernameOnlyAndPreloadSecret:
                // 2-Step Login Magic: Pre-load Password onto Clipboard right now so on Page 2 user just hits Cmd+V!
                if !secret.isEmpty {
                    let expectedCount = writeStringToPasteboard(secret)
                    scheduleClipboardAutoClear(expectedChangeCount: expectedCount, delay: 60.0)
                } else if !username.isEmpty {
                    writeStringToPasteboard(username)
                }
                
                deliverFocusToTargetApp { [weak self] _ in
                    guard let self = self else { return }
                    if !username.isEmpty {
                        if !secret.isEmpty {
                            // Type username directly via Unicode HID so Clipboard stays pre-loaded with Password!
                            self.typeUnicodeString(username)
                        } else {
                            self.simulateCmdV()
                        }
                    }
                }
                
            case .smartAutoFill, .smartAutoFillAndSubmit:
                let shouldSubmit = (credentialMode == .smartAutoFillAndSubmit)
                // Always pre-load Password onto Clipboard upfront (ZERO clipboard swap race during auto-fill!)
                let clipboardValue = secret.isEmpty ? username : secret
                let expectedCount = writeStringToPasteboard(clipboardValue)
                scheduleClipboardAutoClear(expectedChangeCount: expectedCount, delay: 60.0)
                
                deliverFocusToTargetApp { [weak self] targetPID in
                    guard let self = self else { return }
                    
                    // If account has no username, or user's cursor is ALREADY inside a Password input box:
                    let alreadyInPasswordField = (targetPID != nil) && self.isTargetFocusedFieldSecurePassword(pid: targetPID!)
                    if username.isEmpty || alreadyInPasswordField {
                        self.simulateCmdV()
                        if shouldSubmit {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.050) { [weak self] in
                                self?.simulateKey(keyCode: 0x24, flags: []) // kVK_Return
                            }
                        }
                        return
                    }
                    
                    // Full 1-Shot Hybrid Auto-Fill:
                    // Step 1: Type Username directly via Unicode HID stream (does not touch Clipboard!)
                    self.typeUnicodeString(username)
                    
                    guard !secret.isEmpty else {
                        if shouldSubmit {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
                                self?.simulateKey(keyCode: 0x24, flags: [])
                            }
                        }
                        return
                    }
                    
                    // Step 2: After DOM input settles (40ms), press Tab (with cleared modifier flags) to focus Password field
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.040) { [weak self] in
                        guard let self = self else { return }
                        self.simulateKey(keyCode: 0x30, flags: []) // kVK_Tab
                        
                        // Step 3: After focus lands in Password field (45ms), paste pre-loaded Password via Cmd+V!
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
                            guard let self = self else { return }
                            self.simulateCmdV()
                            
                            if shouldSubmit {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.050) { [weak self] in
                                    self?.simulateKey(keyCode: 0x24, flags: []) // kVK_Return
                                }
                            }
                        }
                    }
                }
            }
            return
        }
        
        // MARK: - 2. Standard Clipboard Item Paste
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        
        switch item.contentType {
        case .image:
            if let imgName = item.imageFileName,
               let image = store.loadImage(fileName: imgName),
               let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            
        case .file:
            if let paths = item.filePaths {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSPasteboardWriting }
                pasteboard.writeObjects(urls)
            }
            
        default:
            if asPlainText || item.rtfData == nil {
                if let text = item.textValue {
                    pasteboard.setString(text, forType: .string)
                }
            } else {
                if let rtf = item.rtfData {
                    pasteboard.setData(rtf, forType: .rtf)
                }
                if let text = item.textValue {
                    pasteboard.setString(text, forType: .string)
                }
            }
        }
        
        SoundManager.shared.playPaste()
        completion?()
        
        deliverFocusToTargetApp { [weak self] _ in
            self?.simulateCmdV()
        }
    }
    
    @discardableResult
    private func writeStringToPasteboard(_ value: String) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        pb.setString(value, forType: .string)
        return pb.changeCount
    }
    
    private func scheduleClipboardAutoClear(expectedChangeCount: Int, delay: TimeInterval = 60.0) {
        secretCleanupWorkItem?.cancel()
        let work = DispatchWorkItem {
            if NSPasteboard.general.changeCount == expectedChangeCount {
                NSPasteboard.general.clearContents()
            }
        }
        secretCleanupWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    private func deliverFocusToTargetApp(ready: @escaping @MainActor (pid_t?) -> Void) {
        if self.lastFrontmostApplication == nil || self.lastFrontmostApplication?.isTerminated == true {
            self.lastFrontmostApplication = NSWorkspace.shared.runningApplications.first(where: {
                $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !$0.isTerminated
            })
        }
        
        guard let targetApp = self.lastFrontmostApplication, !targetApp.isTerminated else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                ready(nil)
            }
            return
        }
        
        let pid = targetApp.processIdentifier
        if targetApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && !NSApp.isActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                ready(pid)
            }
            return
        }
        
        if NSApp.isActive {
            NSApp.deactivate()
        }
        targetApp.activate(options: [.activateIgnoringOtherApps])
        waitForTargetAppActivation(targetApp: targetApp, attemptsRemaining: 20, ready: ready)
    }
    
    private func waitForTargetAppActivation(
        targetApp: NSRunningApplication,
        attemptsRemaining: Int,
        ready: @escaping @MainActor (pid_t?) -> Void
    ) {
        let pid = targetApp.processIdentifier
        if (targetApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid) || attemptsRemaining <= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                ready(pid)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.010) { [weak self] in
            self?.waitForTargetAppActivation(
                targetApp: targetApp,
                attemptsRemaining: attemptsRemaining - 1,
                ready: ready
            )
        }
    }
    
    private static let eventSource = CGEventSource(stateID: .combinedSessionState)
    
    /// Synthesizes arbitrary UTF-16 text directly into the target application's focused input field
    /// via `CGEvent.keyboardSetUnicodeString`, completely bypassing `NSPasteboard` so no clipboard race can ever occur.
    private func typeUnicodeString(_ string: String) {
        let utf16Chars = Array(string.utf16)
        guard !utf16Chars.isEmpty else { return }
        
        let src = Self.eventSource ?? CGEventSource(stateID: .combinedSessionState)
        let chunkSize = 16
        var offset = 0
        while offset < utf16Chars.count {
            let end = min(offset + chunkSize, utf16Chars.count)
            var slice = Array(utf16Chars[offset..<end])
            let count = slice.count
            
            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                keyDown.flags = []
                keyUp.flags = []
                keyDown.keyboardSetUnicodeString(stringLength: count, unicodeString: &slice)
                keyUp.keyboardSetUnicodeString(stringLength: count, unicodeString: &slice)
                keyDown.post(tap: .cghidEventTap)
                usleep(4_000)
                keyUp.post(tap: .cghidEventTap)
                usleep(4_000)
            }
            offset = end
        }
    }
    
    private func simulateCmdV() {
        let cmdKeyCode: CGKeyCode = 0x37 // kVK_Command
        let vKeyCode: CGKeyCode = 0x09   // kVK_ANSI_V
        let src = Self.eventSource ?? CGEventSource(stateID: .combinedSessionState)
        
        guard let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: false) else {
            return
        }
        
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []
        
        cmdDown.post(tap: .cghidEventTap)
        usleep(8_000)
        vDown.post(tap: .cghidEventTap)
        usleep(8_000)
        vUp.post(tap: .cghidEventTap)
        usleep(8_000)
        cmdUp.post(tap: .cghidEventTap)
    }
    
    private func simulateKey(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let src = Self.eventSource ?? CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        usleep(6_000)
        keyUp.post(tap: .cghidEventTap)
    }
}
