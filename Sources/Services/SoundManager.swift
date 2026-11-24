import AppKit

public class SoundManager {
    public static let shared = SoundManager()
    
    private var copySound: NSSound?
    private var pasteSound: NSSound?
    
    public var isSoundEnabled: Bool = true
    
    private init() {
        // Load sounds from bundle or fallback to system sounds
        if let copyURL = Bundle.main.url(forResource: "Copy", withExtension: "aiff") {
            copySound = NSSound(contentsOf: copyURL, byReference: true)
        }
        if let pasteURL = Bundle.main.url(forResource: "Paste", withExtension: "aiff") {
            pasteSound = NSSound(contentsOf: pasteURL, byReference: true)
        }
    }
    
    public func playCopy() {
        guard isSoundEnabled else { return }
        if let sound = copySound {
            sound.stop()
            sound.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }
    
    public func playPaste() {
        guard isSoundEnabled else { return }
        if let sound = pasteSound {
            sound.stop()
            sound.play()
        } else {
            NSSound(named: "Tink")?.play()
        }
    }
}
