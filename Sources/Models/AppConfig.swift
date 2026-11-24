import Foundation
import SwiftUI
import Combine
import Carbon

public enum AccentColorTheme: String, CaseIterable, Identifiable, Codable {
    case blue = "Electric Blue"
    case purple = "Neon Purple"
    case pink = "Sunset Pink"
    case red = "Crimson Red"
    case orange = "Amber Orange"
    case green = "Emerald Green"
    case cyan = "Cyan Sky"
    case graphite = "Graphite Slate"
    
    public var id: String { rawValue }
    
    public var hex: String {
        switch self {
        case .blue: return "#0A84FF"
        case .purple: return "#BF5AF2"
        case .pink: return "#FF375F"
        case .red: return "#FF453A"
        case .orange: return "#FF9F0A"
        case .green: return "#30D158"
        case .cyan: return "#64D2FF"
        case .graphite: return "#8E8E93"
        }
    }
    
    public var color: Color {
        return Color(hexString: hex)
    }
}

public enum BackdropMaterialType: String, CaseIterable, Identifiable, Codable {
    case popover = "Frosted Glass (Popover)"
    case hud = "HUD Window (Vibrant)"
    case fullScreenUI = "Ultra-Thin Acrylic"
    case underWindow = "Subtle Blur"
    
    public var id: String { rawValue }
    
    public var material: NSVisualEffectView.Material {
        switch self {
        case .popover: return .popover
        case .hud: return .hudWindow
        case .fullScreenUI: return .fullScreenUI
        case .underWindow: return .underWindowBackground
        }
    }
}

public enum AppearanceModeType: String, CaseIterable, Identifiable, Codable {
    case system = "Match System"
    case dark = "Always Dark"
    case light = "Always Light"
    
    public var id: String { rawValue }
    
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

public struct ShortcutConfig: Codable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var displayString: String
    
    public init(keyCode: UInt32, carbonModifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.displayString = displayString
    }
    
    public static let defaultToggle = ShortcutConfig(
        keyCode: 9, // kVK_ANSI_V
        carbonModifiers: UInt32(cmdKey | shiftKey),
        displayString: "⌘ ⇧ V"
    )
    
    public static let optionSpace = ShortcutConfig(
        keyCode: 49, // kVK_Space
        carbonModifiers: UInt32(optionKey),
        displayString: "⌥ Space"
    )
    
    public static let cmdOptionV = ShortcutConfig(
        keyCode: 9, // kVK_ANSI_V
        carbonModifiers: UInt32(cmdKey | optionKey),
        displayString: "⌘ ⌥ V"
    )
    
    public static let ctrlOptionV = ShortcutConfig(
        keyCode: 9, // kVK_ANSI_V
        carbonModifiers: UInt32(controlKey | optionKey),
        displayString: "⌃ ⌥ V"
    )
    
    public static let cmdTilde = ShortcutConfig(
        keyCode: 50, // kVK_ANSI_Grave (~)
        carbonModifiers: UInt32(cmdKey),
        displayString: "⌘ ~"
    )
    
    public static let presets: [ShortcutConfig] = [
        defaultToggle,
        optionSpace,
        cmdOptionV,
        ctrlOptionV,
        cmdTilde
    ]
}

@MainActor
public class AppConfig: ObservableObject {
    public static let shared = AppConfig()
    
    @Published public var accentTheme: AccentColorTheme = .blue {
        didSet { save() }
    }
    
    @Published public var backdropMaterial: BackdropMaterialType = .popover {
        didSet { save() }
    }
    
    @Published public var appearanceMode: AppearanceModeType = .system {
        didSet { save() }
    }
    
    @Published public var toggleShortcut: ShortcutConfig = .defaultToggle {
        didSet { save() }
    }
    
    @Published public var pastePlainTextByDefault: Bool = false {
        didSet { save() }
    }
    
    @Published public var showShortcutHints: Bool = true {
        didSet { save() }
    }
    
    @Published public var quickPasteWithCmd: Bool = false {
        didSet { save() }
    }
    
    private var configFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PasteFlow", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("config.json")
    }
    
    private struct ConfigData: Codable {
        var accentTheme: AccentColorTheme
        var backdropMaterial: BackdropMaterialType
        var appearanceMode: AppearanceModeType
        var toggleShortcut: ShortcutConfig
        var pastePlainTextByDefault: Bool
        var showShortcutHints: Bool
        var quickPasteWithCmd: Bool
    }
    
    public init() {
        load()
    }
    
    public func save() {
        let data = ConfigData(
            accentTheme: accentTheme,
            backdropMaterial: backdropMaterial,
            appearanceMode: appearanceMode,
            toggleShortcut: toggleShortcut,
            pastePlainTextByDefault: pastePlainTextByDefault,
            showShortcutHints: showShortcutHints,
            quickPasteWithCmd: quickPasteWithCmd
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(data)
            try encoded.write(to: configFile, options: .atomic)
        } catch {
            print("PasteFlow: Failed to save config: \(error)")
        }
    }
    
    public func load() {
        guard FileManager.default.fileExists(atPath: configFile.path),
              let data = try? Data(contentsOf: configFile),
              let decoded = try? JSONDecoder().decode(ConfigData.self, from: data) else {
            return
        }
        
        self.accentTheme = decoded.accentTheme
        self.backdropMaterial = decoded.backdropMaterial
        self.appearanceMode = decoded.appearanceMode
        self.toggleShortcut = decoded.toggleShortcut
        self.pastePlainTextByDefault = decoded.pastePlainTextByDefault
        self.showShortcutHints = decoded.showShortcutHints
        self.quickPasteWithCmd = decoded.quickPasteWithCmd
    }
}
