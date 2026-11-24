import Carbon
import Cocoa

@MainActor
public class HotKeyManager {
    public static let shared = HotKeyManager()
    
    public var onHotKeyTriggered: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isHandlerInstalled = false
    
    private init() {}
    
    public func start() {
        installHandlerIfNeeded()
        let config = AppConfig.shared.toggleShortcut
        register(keyCode: config.keyCode, modifiers: config.carbonModifiers)
    }
    
    public func registerDefaultHotKey() {
        start()
    }
    
    private func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    Task { @MainActor in
                        manager.onHotKeyTriggered?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status == noErr {
            isHandlerInstalled = true
        }
    }
    
    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        installHandlerIfNeeded()
        
        // Unregister existing hotkey first
        unregister()
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x50535445), id: 1) // 'PSTE'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("PasteFlow: Global hotkey registered (keyCode: \(keyCode), modifiers: \(modifiers))")
            return true
        } else {
            print("PasteFlow: Failed to register hotkey. Status: \(status)")
            return false
        }
    }
    
    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    @discardableResult
    public func updateHotKey(config: ShortcutConfig) -> Bool {
        let success = register(keyCode: config.keyCode, modifiers: config.carbonModifiers)
        if success {
            DispatchQueue.main.async {
                Task { @MainActor in
                    AppConfig.shared.toggleShortcut = config
                }
            }
        }
        return success
    }
}
