import SwiftUI
import AppKit
import Carbon

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case shortcuts = "Shortcuts"
    case privacy = "Privacy"
    case about = "About"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .shortcuts: return "keyboard"
        case .privacy: return "hand.raised.shield"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var store: HistoryStore
    @Binding var isPresented: Bool
    
    @ObservedObject private var config = AppConfig.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var isAccessibilityGranted: Bool = PasteSimulator.shared.isAccessibilityGranted
    @State private var soundEnabled: Bool = SoundManager.shared.isSoundEnabled
    @State private var maxHistory: Int = HistoryStore.shared.maxHistoryCount
    @State private var isRecordingShortcut: Bool = false
    @State private var recordMonitor: Any? = nil
    @State private var newIgnoredBundleID: String = ""
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Tab Selector Header
            HStack {
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? config.accentTheme.color.opacity(0.18) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedTab == tab ? config.accentTheme.color.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                            .foregroundColor(selectedTab == tab ? config.accentTheme.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.03))
            
            Divider()
                .opacity(0.3)
            
            // MARK: - Tab Body
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalSection
                    case .appearance:
                        appearanceSection
                    case .shortcuts:
                        shortcutsSection
                    case .privacy:
                        privacySection
                    case .about:
                        aboutSection
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 520, height: 490)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(config.appearanceMode.colorScheme)
        .onAppear {
            isAccessibilityGranted = PasteSimulator.shared.isAccessibilityGranted
        }
    }
    
    // MARK: - 1. General Tab
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SYSTEM & STORAGE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at System Login", isOn: Binding(
                    get: { store.isLaunchAtLoginEnabled },
                    set: { store.isLaunchAtLoginEnabled = $0 }
                ))
                
                Toggle("Play Sound Effects on Copy and Paste", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { newValue in
                        SoundManager.shared.isSoundEnabled = newValue
                    }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            
            Text("HISTORY CAPACITY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Maximum Stored Clips")
                            .font(.system(size: 12, weight: .medium))
                        Text("Oldest clips are automatically pruned. Pinned items are always protected.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $maxHistory) {
                        Text("100 clips").tag(100)
                        Text("250 clips").tag(250)
                        Text("500 clips").tag(500)
                        Text("1,000 clips").tag(1000)
                    }
                    .frame(width: 120)
                    .onChange(of: maxHistory) { newValue in
                        store.maxHistoryCount = newValue
                    }
                }
                
                Divider().opacity(0.3)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clipboard Database")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(store.items.count) clips in history (\(store.items.filter { $0.isPinned }.count) pinned)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear History", role: .destructive) {
                        store.clearHistory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 2. Appearance Tab
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ACCENT COLOR THEME")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Select your preferred accent color for highlights, focus rings, and badges:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(AccentColorTheme.allCases) { theme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                config.accentTheme = theme
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 16, height: 16)
                                    .shadow(color: theme.color.opacity(0.4), radius: 3)
                                
                                Text(theme.rawValue)
                                    .font(.system(size: 11, weight: config.accentTheme == theme ? .bold : .regular))
                                    .lineLimit(1)
                                
                                Spacer(minLength: 0)
                                
                                if config.accentTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(theme.color)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(config.accentTheme == theme ? theme.color.opacity(0.12) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(config.accentTheme == theme ? theme.color : Color.white.opacity(0.08), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            
            Text("TRANSLUCENCY & BACKDROP")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Frosted Glass Material:")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $config.backdropMaterial) {
                        ForEach(BackdropMaterialType.allCases) { mat in
                            Text(mat.rawValue).tag(mat)
                        }
                    }
                    .frame(width: 200)
                }
                
                Divider().opacity(0.3)
                
                HStack {
                    Text("Appearance Mode:")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $config.appearanceMode) {
                        ForEach(AppearanceModeType.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(width: 200)
                }
                
                Divider().opacity(0.3)
                
                Toggle("Show Bottom Shortcut Hints Bar in HUD", isOn: $config.showShortcutHints)
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 3. Shortcuts Tab
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("GLOBAL ACTIVATION SHORTCUT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toggle PasteFlow Anywhere")
                            .font(.system(size: 12, weight: .bold))
                        Text("Current: \(config.toggleShortcut.displayString)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Interactive Recorder Button
                    Button {
                        if isRecordingShortcut {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isRecordingShortcut ? Color.red : config.accentTheme.color)
                                .frame(width: 8, height: 8)
                            Text(isRecordingShortcut ? "Press keys..." : "Record Shortcut")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isRecordingShortcut ? Color.red.opacity(0.15) : config.accentTheme.color.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider().opacity(0.3)
                
                Text("Or pick a popular preset:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(ShortcutConfig.presets, id: \.displayString) { preset in
                        Button {
                            _ = HotKeyManager.shared.updateHotKey(config: preset)
                        } label: {
                            Text(preset.displayString)
                                .font(.system(size: 11, weight: config.toggleShortcut == preset ? .bold : .medium, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(config.toggleShortcut == preset ? config.accentTheme.color.opacity(0.2) : Color.white.opacity(0.06))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(config.toggleShortcut == preset ? config.accentTheme.color : Color.clear, lineWidth: 1)
                                )
                                .foregroundColor(config.toggleShortcut == preset ? config.accentTheme.color : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            
            Text("IN-APP SHORTCUT BEHAVIOR")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Paste Plain Text by Default on Return (Strips formatting)", isOn: $config.pastePlainTextByDefault)
                
                Toggle("Require Command Key for 1–9 Quick Paste (⌘1 ... ⌘9)", isOn: $config.quickPasteWithCmd)
                
                Divider().opacity(0.3)
                
                VStack(spacing: 6) {
                    ShortcutRow(label: "Direct Paste to Target App", shortcut: config.pastePlainTextByDefault ? "⌥ Return" : "Return")
                    ShortcutRow(label: "Paste as Plain Text", shortcut: config.pastePlainTextByDefault ? "Return" : "⌥ Return")
                    ShortcutRow(label: "Quick Look Preview (Toggle Open/Close)", shortcut: "Space")
                    ShortcutRow(label: "Navigate Clips Left / Right", shortcut: "←  →")
                    ShortcutRow(label: "Pin / Unpin Selected Clip", shortcut: "⌘ P")
                    ShortcutRow(label: "Copy to Clipboard", shortcut: "⌘ C")
                    ShortcutRow(label: "Quick Paste (First 9 Cards)", shortcut: config.quickPasteWithCmd ? "⌘1 ... ⌘9" : "1 ... 9")
                    ShortcutRow(label: "Delete Selected Clip", shortcut: "⌫ / Delete")
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 4. Privacy Tab
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("DIRECT AUTO-PASTE ACCESSIBILITY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS Accessibility Status:")
                        .font(.system(size: 12, weight: .medium))
                    Text(isAccessibilityGranted ? "Granted. Direct paste into target apps is enabled." : "Missing. Grant Accessibility in macOS Settings to auto-paste.")
                        .font(.system(size: 11))
                        .foregroundColor(isAccessibilityGranted ? .green : .orange)
                }
                
                Spacer()
                
                if !isAccessibilityGranted {
                    Button("Grant in Settings") {
                        PasteSimulator.shared.promptAccessibilityAccess()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(config.accentTheme.color)
                    .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 18))
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            
            Text("IGNORED PASSWORD MANAGERS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Clips copied from these applications are never captured or saved to disk:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                ForEach(store.ignoredBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text(bundleID)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 5. About Tab
    private var aboutSection: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .cornerRadius(14)
                .shadow(radius: 6)
            
            VStack(spacing: 4) {
                Text("PasteFlow")
                    .font(.system(size: 20, weight: .bold))
                Text("Version 1.2.0 • Dual-Platform macOS & Windows")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Text("Engineered for speed, privacy, and minimalist elegance. 100% Native Swift 6 + SwiftUI + AppKit on macOS; 100% Native Rust 2024 + Win32 on Windows. Zero Electron or Webviews.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Divider().opacity(0.3)
            
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(config.accentTheme.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crafted by Quốc Ngô")
                        .font(.system(size: 13, weight: .bold))
                    Text("@lengo0951 / coolstar17")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("GitHub Repository") {
                    if let url = URL(string: "https://github.com/lengo0951/PasteFlow") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(config.accentTheme.color)
                .controlSize(.small)
            }
            .padding(14)
            .background(config.accentTheme.color.opacity(0.08))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(config.accentTheme.color.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(14)
    }
    
    // MARK: - Interactive Shortcut Recorder Engine
    private func startRecording() {
        isRecordingShortcut = true
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            
            // Require at least one modifier flag
            let flags = event.modifierFlags
            var carbonMods: UInt32 = 0
            var symbols = ""
            
            if flags.contains(.control) {
                carbonMods |= UInt32(controlKey)
                symbols += "⌃ "
            }
            if flags.contains(.option) {
                carbonMods |= UInt32(optionKey)
                symbols += "⌥ "
            }
            if flags.contains(.shift) {
                carbonMods |= UInt32(shiftKey)
                symbols += "⇧ "
            }
            if flags.contains(.command) {
                carbonMods |= UInt32(cmdKey)
                symbols += "⌘ "
            }
            
            // If at least one modifier was pressed and a valid key was struck
            if carbonMods != 0 {
                let keyStr = keyString(for: event.keyCode)
                let display = symbols + keyStr
                let newConfig = ShortcutConfig(
                    keyCode: UInt32(event.keyCode),
                    carbonModifiers: carbonMods,
                    displayString: display
                )
                
                _ = HotKeyManager.shared.updateHotKey(config: newConfig)
                stopRecording()
                return nil
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        isRecordingShortcut = false
        if let mon = recordMonitor {
            NSEvent.removeMonitor(mon)
            recordMonitor = nil
        }
    }
    
    private func keyString(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        case 50: return "~"
        default: return "Key \(keyCode)"
        }
    }
}

public struct ShortcutRow: View {
    let label: String
    let shortcut: String
    
    public var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
        }
    }
}
