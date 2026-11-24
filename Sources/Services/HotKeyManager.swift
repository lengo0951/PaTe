import Carbon
import Cocoa

public class HotKeyManager {
    public static let shared = HotKeyManager()
    
    public var onHotKeyTriggered: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var isRegistered = false
    
    private init() {}
    
    public func registerDefaultHotKey() {
        guard !isRegistered else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        InstallEventHandler(
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
            nil
        )
        
        // HotKey: Cmd + Shift + V
        let hotKeyID = EventHotKeyID(signature: OSType(0x50535445), id: 1) // 'PSTE'
        let modifiers = UInt32(cmdKey | shiftKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            isRegistered = true
            print("PasteFlow: Global hotkey registered (Cmd + Shift + V)")
        } else {
            print("PasteFlow: Failed to register hotkey. Status: \(status)")
        }
    }
}
