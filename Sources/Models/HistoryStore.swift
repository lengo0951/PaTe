import Foundation
import SwiftUI
import Combine
import ServiceManagement

@MainActor
public class HistoryStore: ObservableObject {
    public static let shared = HistoryStore()
    
    @Published public var items: [ClipboardItem] = []
    @Published public var pinboards: [Pinboard] = [Pinboard.history]
    @Published public var selectedPinboardID: String = "history"
    @Published public var searchQuery: String = ""
    @Published public var selectedContentType: ContentType? = nil
    @Published public var isMonitoringPaused: Bool = false
    @Published public var selectedItemID: String? = nil
    @Published public var activeQuickLookItem: ClipboardItem? = nil
    @Published public var itemBeingRenamed: ClipboardItem? = nil
    @Published public var ignoredBundleIDs: [String] = [
        "com.agilebits.onepassword",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess"
    ]
    
    public var isLaunchAtLoginEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    objectWillChange.send()
                } catch {
                    print("Error setting Launch at Login: \(error)")
                }
            }
        }
    }
    
    public var maxHistoryCount: Int = 500
    
    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, NSImage>()
    
    private let storageDirectory: URL
    private let imagesDirectory: URL
    private let historyFile: URL
    private let pinboardsFile: URL
    private var saveTask: Task<Void, Never>?
    
    public init() {
        imageCache.countLimit = 30 // Bound image memory cache
        
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent("PasteFlow", isDirectory: true)
        if !fileManager.fileExists(atPath: storeDir.path) {
            try? fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
        }
        self.storageDirectory = storeDir
        
        let imgDir = storeDir.appendingPathComponent("images", isDirectory: true)
        if !fileManager.fileExists(atPath: imgDir.path) {
            try? fileManager.createDirectory(at: imgDir, withIntermediateDirectories: true)
        }
        self.imagesDirectory = imgDir
        
        self.historyFile = storeDir.appendingPathComponent("history.json")
        self.pinboardsFile = storeDir.appendingPathComponent("pinboards.json")
        
        loadData()
    }
    
    public var filteredItems: [ClipboardItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefaultHistory = (selectedPinboardID == "history")
        let hasNoTypeFilter = (selectedContentType == nil)
        let hasNoQuery = trimmedQuery.isEmpty
        
        // Fast-path: O(1) return original array directly
        if isDefaultHistory && hasNoTypeFilter && hasNoQuery {
            return items
        }
        
        let targetPinboard = isDefaultHistory ? nil : selectedPinboardID
        let targetType = selectedContentType
        
        // Single-pass O(N) evaluation with zero intermediate array allocations
        return items.filter { item in
            if let pb = targetPinboard, !item.pinboardIDs.contains(pb) {
                return false
            }
            if let type = targetType, item.contentType != type {
                return false
            }
            if !hasNoQuery {
                if let title = item.customTitle, title.localizedCaseInsensitiveContains(trimmedQuery) {
                    return true
                }
                if let text = item.textValue, text.localizedCaseInsensitiveContains(trimmedQuery) {
                    return true
                }
                if let app = item.appName, app.localizedCaseInsensitiveContains(trimmedQuery) {
                    return true
                }
                if let files = item.filePaths, files.contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) }) {
                    return true
                }
                return false
            }
            return true
        }
    }
    
    public func addItem(_ item: ClipboardItem) {
        // If an item with the same checksum already exists, move it to the front
        if let existingIndex = items.firstIndex(where: { $0.checksum == item.checksum }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
            if items.count > maxHistoryCount {
                let toRemove = items.suffix(from: maxHistoryCount)
                for old in toRemove {
                    if !old.isPinned, let imgName = old.imageFileName {
                        let path = imagesDirectory.appendingPathComponent(imgName)
                        try? fileManager.removeItem(at: path)
                        imageCache.removeObject(forKey: imgName as NSString)
                    }
                }
                items = Array(items.prefix(maxHistoryCount))
            }
        }
        saveData()
    }
    
    public func removeItem(id: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            let item = items.remove(at: index)
            if let imgName = item.imageFileName {
                let path = imagesDirectory.appendingPathComponent(imgName)
                try? fileManager.removeItem(at: path)
                imageCache.removeObject(forKey: imgName as NSString)
            }
            saveData()
        }
    }
    
    public func clearHistory() {
        // Keep pinned items
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        for item in unpinned {
            if let imgName = item.imageFileName {
                let path = imagesDirectory.appendingPathComponent(imgName)
                try? fileManager.removeItem(at: path)
                imageCache.removeObject(forKey: imgName as NSString)
            }
        }
        items = pinned
        saveData()
    }
    
    public func togglePin(itemID: String, pinboardID: String) {
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            if items[index].pinboardIDs.contains(pinboardID) {
                items[index].pinboardIDs.removeAll { $0 == pinboardID }
            } else {
                items[index].pinboardIDs.append(pinboardID)
            }
            saveData()
        }
    }
    
    public func renameItem(id: String, newTitle: String?) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            let clean = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            items[index].customTitle = (clean?.isEmpty == false) ? clean : nil
            saveData()
        }
    }
    
    public func addPinboard(name: String, colorHex: String) {
        let pb = Pinboard(name: name, colorHex: colorHex)
        pinboards.append(pb)
        saveData()
    }
    
    public func removePinboard(id: String) {
        guard id != "history" else { return }
        pinboards.removeAll { $0.id == id }
        for i in items.indices {
            items[i].pinboardIDs.removeAll { $0 == id }
        }
        if selectedPinboardID == id {
            selectedPinboardID = "history"
        }
        saveData()
    }
    
    public func saveImage(data: Data) -> String? {
        let fileName = "\(UUID().uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            return fileName
        } catch {
            print("Error saving image data: \(error)")
            return nil
        }
    }
    
    public func loadImage(fileName: String) -> NSImage? {
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        if let image = NSImage(contentsOf: fileURL) {
            imageCache.setObject(image, forKey: key)
            return image
        }
        return nil
    }
    
    public func saveData(immediately: Bool = false) {
        if immediately {
            performSave()
            return
        }
        
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }
    
    private func performSave() {
        let itemsSnapshot = self.items
        let pinboardsSnapshot = self.pinboards
        let historyURL = self.historyFile
        let pinboardsURL = self.pinboardsFile
        
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                let itemsData = try encoder.encode(itemsSnapshot)
                try itemsData.write(to: historyURL, options: .atomic)
                
                let pbData = try encoder.encode(pinboardsSnapshot)
                try pbData.write(to: pinboardsURL, options: .atomic)
            } catch {
                print("Error saving PasteFlow data: \(error)")
            }
        }
    }
    
    public func loadData() {
        let decoder = JSONDecoder()
        if fileManager.fileExists(atPath: historyFile.path),
           let data = try? Data(contentsOf: historyFile),
           var saved = try? decoder.decode([ClipboardItem].self, from: data) {
            // Null out any leftover appIconData to reclaim memory
            for i in saved.indices {
                saved[i].appIconData = nil
            }
            self.items = saved
        }
        
        if fileManager.fileExists(atPath: pinboardsFile.path),
           let data = try? Data(contentsOf: pinboardsFile),
           let saved = try? decoder.decode([Pinboard].self, from: data) {
            self.pinboards = saved
        } else {
            self.pinboards = [
                Pinboard.history,
                Pinboard(id: "code", name: "Code Snippets", colorHex: "#30D158"),
                Pinboard(id: "links", name: "Links", colorHex: "#BF5AF2"),
                Pinboard(id: "colors", name: "Colors", colorHex: "#FF9F0A")
            ]
        }
    }
}
