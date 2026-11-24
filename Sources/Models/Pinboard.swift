import Foundation

public struct Pinboard: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var colorHex: String
    public var createdAt: Date
    public var isSystem: Bool // e.g. "Clipboard History" tab is system
    
    public init(id: String = UUID().uuidString, name: String, colorHex: String = "#0A84FF", createdAt: Date = Date(), isSystem: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.isSystem = isSystem
    }
    
    public static let history = Pinboard(
        id: "history",
        name: "Clipboard History",
        colorHex: "#0A84FF",
        isSystem: true
    )
}
