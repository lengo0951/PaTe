import Foundation
import SwiftUI
import Combine
import ServiceManagement
import ImageIO

@MainActor
public class HistoryStore: ObservableObject {
    public static let shared = HistoryStore()
    
    @Published public var items: [ClipboardItem] = [] {
        didSet { invalidateFilterCache() }
    }
    @Published public var pinboards: [Pinboard] = [Pinboard.history, Pinboard.vault]
    @Published public var selectedPinboardID: String = "history" {
        didSet { invalidateFilterCache() }
    }
    @Published public var searchQuery: String = "" {
        didSet { invalidateFilterCache() }
    }
    @Published public var selectedContentType: ContentType? = nil {
        didSet { invalidateFilterCache() }
    }
    @Published public var isMonitoringPaused: Bool = false
    @Published public var selectedItemID: String? = nil
    @Published public var lastSelectionWasKeyboard: Bool = false
    @Published public var activeQuickLookItem: ClipboardItem? = nil
    @Published public var itemBeingRenamed: ClipboardItem? = nil
    @Published public var isCredentialModalPresented: Bool = false
    @Published public var credentialItemBeingEdited: ClipboardItem? = nil
    @Published public var itemConvertingToCredential: ClipboardItem? = nil
    
    @Published public var ignoredBundleIDs: [String] = [
        "com.agilebits.onepassword",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess"
    ]
    
    public var isAnyModalPresented: Bool {
        return activeQuickLookItem != nil
            || itemBeingRenamed != nil
            || isCredentialModalPresented
            || credentialItemBeingEdited != nil
            || itemConvertingToCredential != nil
    }
    
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
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    private let storageDirectory: URL
    private let imagesDirectory: URL
    private let historyFile: URL
    private let pinboardsFile: URL
    private var saveTask: Task<Void, Never>?
    
    // Memoized filter cache & O(1) checksum index
    private var cachedFiltered: [ClipboardItem] = []
    private var isFilterDirty: Bool = true
    private var checksumMap: [String: String] = [:] // checksum -> item.id
    
    public init() {
        imageCache.countLimit = 20
        thumbnailCache.countLimit = 80 // Lightweight 400px thumbnails (~25KB each)
        
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
    
    private func invalidateFilterCache() {
        isFilterDirty = true
    }
    
    private func rebuildChecksumMap() {
        checksumMap.removeAll(keepingCapacity: true)
        for item in items {
            checksumMap[item.checksum] = item.id
        }
    }
    
    public var filteredItems: [ClipboardItem] {
        if !isFilterDirty {
            return cachedFiltered
        }
        
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefaultHistory = (selectedPinboardID == "history")
        let isVaultTab = (selectedPinboardID == "vault")
        let hasNoTypeFilter = (selectedContentType == nil)
        let hasNoQuery = trimmedQuery.isEmpty
        
        if isDefaultHistory && hasNoTypeFilter && hasNoQuery {
            cachedFiltered = items
            isFilterDirty = false
            return items
        }
        
        let targetPinboard = isDefaultHistory ? nil : selectedPinboardID
        let targetType = selectedContentType
        
        let result = items.filter { item in
            if isVaultTab {
                if item.contentType != .credential && !item.pinboardIDs.contains("vault") {
                    return false
                }
            } else if let pb = targetPinboard, !item.pinboardIDs.contains(pb) {
                return false
            }
            
            if let type = targetType, item.contentType != type {
                return false
            }
            
            if !hasNoQuery {
                if let title = item.customTitle, title.localizedCaseInsensitiveContains(trimmedQuery) {
                    return true
                }
                if let user = item.credentialUsername, user.localizedCaseInsensitiveContains(trimmedQuery) {
                    return true
                }
                if let url = item.credentialURL, url.localizedCaseInsensitiveContains(trimmedQuery) {
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
        
        cachedFiltered = result
        isFilterDirty = false
        return result
    }
    
    public func addItem(_ item: ClipboardItem) {
        // O(1) hash lookup before touching array
        if let existingID = checksumMap[item.checksum],
           let existingIndex = items.firstIndex(where: { $0.id == existingID }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
        } else {
            checksumMap[item.checksum] = item.id
            items.insert(item, at: 0)
            if items.count > maxHistoryCount {
                var idx = items.count - 1
                while items.count > maxHistoryCount && idx >= 0 {
                    if !items[idx].isPinned {
                        let removed = items.remove(at: idx)
                        checksumMap.removeValue(forKey: removed.checksum)
                        cleanupItemFiles(removed)
                    }
                    idx -= 1
                }
            }
        }
        saveData()
    }
    
    // MARK: - Credential Vault Operations
    
    public func saveCredential(
        existingID: String? = nil,
        title: String,
        username: String,
        password: String,
        url: String? = nil
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? (cleanUser.isEmpty ? "Account" : cleanUser) : cleanTitle
        let finalURL = (cleanURL?.isEmpty == false) ? cleanURL : nil
        
        if let id = existingID, let index = items.firstIndex(where: { $0.id == id }) {
            items[index].contentType = .credential
            items[index].customTitle = finalTitle
            items[index].credentialUsername = cleanUser
            items[index].credentialURL = finalURL
            items[index].textValue = nil // Never keep plaintext secret in JSON
            items[index].rtfData = nil
            items[index].htmlData = nil
            items[index].hasVaultSecret = true
            if !items[index].pinboardIDs.contains("vault") {
                items[index].pinboardIDs.append("vault")
            }
            if !password.isEmpty {
                CredentialVault.shared.setSecret(password, for: id)
            }
            invalidateFilterCache()
            saveData()
        } else {
            let id = UUID().uuidString
            let checksum = "vault-\(id)"
            var pbIDs = ["vault"]
            if selectedPinboardID != "history" && selectedPinboardID != "vault" {
                pbIDs.append(selectedPinboardID)
            }
            let newItem = ClipboardItem(
                id: id,
                contentType: .credential,
                textValue: nil,
                appName: "Vault",
                checksum: checksum,
                pinboardIDs: pbIDs,
                customTitle: finalTitle,
                credentialUsername: cleanUser,
                credentialURL: finalURL,
                hasVaultSecret: true
            )
            CredentialVault.shared.setSecret(password, for: id)
            checksumMap[checksum] = id
            items.insert(newItem, at: 0)
            selectedItemID = id
            saveData()
        }
    }
    
    private func cleanupItemFiles(_ item: ClipboardItem) {
        if let imgName = item.imageFileName {
            let path = imagesDirectory.appendingPathComponent(imgName)
            try? fileManager.removeItem(at: path)
            imageCache.removeObject(forKey: imgName as NSString)
        }
        if let thumbName = item.thumbnailFileName {
            let path = imagesDirectory.appendingPathComponent(thumbName)
            try? fileManager.removeItem(at: path)
            thumbnailCache.removeObject(forKey: thumbName as NSString)
        }
        if item.contentType == .credential || item.hasVaultSecret == true {
            CredentialVault.shared.removeSecret(for: item.id)
        }
    }
    
    public func removeItem(id: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            let item = items.remove(at: index)
            checksumMap.removeValue(forKey: item.checksum)
            cleanupItemFiles(item)
            saveData()
        }
    }
    
    public func clearHistory() {
        let pinned = items.filter { $0.isPinned }
        let unpinned = items.filter { !$0.isPinned }
        for item in unpinned {
            cleanupItemFiles(item)
        }
        items = pinned
        rebuildChecksumMap()
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
        guard id != "history" && id != "vault" else { return }
        pinboards.removeAll { $0.id == id }
        for i in items.indices {
            items[i].pinboardIDs.removeAll { $0 == id }
        }
        if selectedPinboardID == id {
            selectedPinboardID = "history"
        }
        saveData()
    }
    
    // MARK: - High-Efficiency Image & Downscaled Thumbnail Pipeline
    
    public func saveImageWithThumbnail(data: Data) -> (fileName: String, thumbFileName: String?)? {
        let uuid = UUID().uuidString
        let fileName = "\(uuid).png"
        let thumbName = "\(uuid)_thumb.jpg"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        let thumbURL = imagesDirectory.appendingPathComponent(thumbName)
        
        do {
            try data.write(to: fileURL)
        } catch {
            print("Error saving image data: \(error)")
            return nil
        }
        
        // Generate lightweight 400px thumbnail via ImageIO without decoding full uncompressed RGBA
        var generatedThumb: String? = nil
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 400
            ]
            if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                let rep = NSBitmapImageRep(cgImage: cgThumb)
                if let jpgData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) {
                    try? jpgData.write(to: thumbURL)
                    generatedThumb = thumbName
                }
            }
        }
        
        return (fileName, generatedThumb)
    }
    
    public func loadThumbnail(for item: ClipboardItem) -> NSImage? {
        if let thumbName = item.thumbnailFileName {
            let key = thumbName as NSString
            if let cached = thumbnailCache.object(forKey: key) {
                return cached
            }
            let thumbURL = imagesDirectory.appendingPathComponent(thumbName)
            if let img = NSImage(contentsOf: thumbURL) {
                thumbnailCache.setObject(img, forKey: key)
                return img
            }
        }
        if let full = item.imageFileName {
            return loadImage(fileName: full)
        }
        return nil
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
            try? await Task.sleep(nanoseconds: 250_000_000)
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
            for i in saved.indices {
                saved[i].appIconData = nil
            }
            self.items = saved
            rebuildChecksumMap()
        }
        
        if fileManager.fileExists(atPath: pinboardsFile.path),
           let data = try? Data(contentsOf: pinboardsFile),
           var saved = try? decoder.decode([Pinboard].self, from: data) {
            if !saved.contains(where: { $0.id == "vault" }) {
                let insertIdx = min(1, saved.count)
                saved.insert(Pinboard.vault, at: insertIdx)
            }
            self.pinboards = saved
        } else {
            self.pinboards = [
                Pinboard.history,
                Pinboard.vault,
                Pinboard(id: "code", name: "Code Snippets", colorHex: "#30D158"),
                Pinboard(id: "links", name: "Links", colorHex: "#BF5AF2"),
                Pinboard(id: "colors", name: "Colors", colorHex: "#FF9F0A")
            ]
        }
    }
}
