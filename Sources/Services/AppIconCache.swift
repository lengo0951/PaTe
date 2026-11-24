import AppKit

@MainActor
public class AppIconCache {
    public static let shared = AppIconCache()
    
    private let cache = NSCache<NSString, NSImage>()
    private var failedBundleIDs = Set<String>()
    
    private init() {
        cache.countLimit = 64
    }
    
    public func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return nil }
        if failedBundleIDs.contains(bundleID) { return nil }
        
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let originalIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            
            // Create a small 32x32 icon representation to keep RAM minuscule
            let targetSize = NSSize(width: 32, height: 32)
            let resizedIcon = NSImage(size: targetSize)
            resizedIcon.lockFocus()
            originalIcon.draw(
                in: NSRect(origin: .zero, size: targetSize),
                from: NSRect(origin: .zero, size: originalIcon.size),
                operation: .copy,
                fraction: 1.0
            )
            resizedIcon.unlockFocus()
            
            cache.setObject(resizedIcon, forKey: key)
            return resizedIcon
        }
        
        failedBundleIDs.insert(bundleID)
        return nil
    }
}
