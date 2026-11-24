import Foundation
import AppKit

public struct ClipboardItem: Identifiable, Codable, Equatable {
    public let id: String
    public var contentType: ContentType
    public var textValue: String?
    public var rtfData: Data?
    public var htmlData: String?
    public var imageFileName: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var filePaths: [String]?
    public var appBundleID: String?
    public var appName: String?
    public var createdAt: Date
    public var checksum: String
    public var pinboardIDs: [String]
    public var customTitle: String?
    
    // Kept optional for backward compatibility during JSON decode if present
    public var appIconData: Data? = nil
    
    public init(
        id: String = UUID().uuidString,
        contentType: ContentType,
        textValue: String? = nil,
        rtfData: Data? = nil,
        htmlData: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        filePaths: [String]? = nil,
        appBundleID: String? = nil,
        appName: String? = nil,
        createdAt: Date = Date(),
        checksum: String,
        pinboardIDs: [String] = [],
        customTitle: String? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.textValue = textValue
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.filePaths = filePaths
        self.appBundleID = appBundleID
        self.appName = appName
        self.createdAt = createdAt
        self.checksum = checksum
        self.pinboardIDs = pinboardIDs
        self.customTitle = customTitle
        self.appIconData = nil
    }
    
    public var isPinned: Bool {
        return !pinboardIDs.isEmpty
    }
    
    public var characterCount: Int {
        return textValue?.count ?? 0
    }
    
    public var lineCount: Int {
        guard let text = textValue else { return 0 }
        return text.components(separatedBy: .newlines).count
    }
    
    public var formattedRelativeTime: String {
        let elapsed = Date().timeIntervalSince(createdAt)
        if elapsed < 60 {
            return "Just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes)m ago"
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(elapsed / 86400)
            return "\(days)d ago"
        }
    }
    
    public var displayTitle: String {
        if let custom = customTitle, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        switch contentType {
        case .color:
            return textValue?.uppercased() ?? "Color"
        case .link:
            if let text = textValue, let url = URL(string: text), let host = url.host {
                return host
            }
            return "Link"
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "\(w) × \(h)"
            }
            return "Image"
        case .file:
            if let paths = filePaths, !paths.isEmpty {
                if paths.count == 1 {
                    return URL(fileURLWithPath: paths[0]).lastPathComponent
                }
                return "\(paths.count) Files"
            }
            return "Files"
        case .code:
            return "Code Snippet"
        case .text:
            return "Text"
        }
    }
    
    public var displaySubtitle: String {
        switch contentType {
        case .color:
            return "Color Code"
        case .link:
            return textValue ?? ""
        case .image:
            return "PNG Image"
        case .file:
            if let paths = filePaths, paths.count > 1 {
                return paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            }
            return filePaths?.first ?? ""
        case .code:
            return "\(lineCount) lines, \(characterCount) chars"
        case .text:
            return "\(characterCount) characters"
        }
    }
}
