import Foundation

public enum ContentType: String, Codable, CaseIterable {
    case text
    case code
    case link
    case color
    case image
    case file
    
    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .code: return "Code"
        case .link: return "Links"
        case .color: return "Colors"
        case .image: return "Images"
        case .file: return "Files"
        }
    }
    
    public var iconName: String {
        switch self {
        case .text: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "folder"
        }
    }
}
