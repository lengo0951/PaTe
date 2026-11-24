import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var store: HistoryStore
    @Binding var isPresented: Bool
    
    @State private var isAccessibilityGranted: Bool = PasteSimulator.shared.isAccessibilityGranted
    @State private var soundEnabled: Bool = SoundManager.shared.isSoundEnabled
    @State private var maxHistory: Int = HistoryStore.shared.maxHistoryCount
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Header
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("PasteFlow Preferences")
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)
                
                Divider()
                
                // Section 1: Hotkey & Shortcuts
                VStack(alignment: .leading, spacing: 10) {
                    Text("SHORTCUTS & PERMISSIONS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 6) {
                        ShortcutRow(label: "Toggle PasteFlow", shortcut: "⌘ ⇧ V")
                        ShortcutRow(label: "Paste to Target App", shortcut: "Return")
                        ShortcutRow(label: "Paste as Plain Text", shortcut: "⌥ Return")
                        ShortcutRow(label: "Quick Look Preview", shortcut: "Space")
                        ShortcutRow(label: "Quick Paste (Cards 1–9)", shortcut: "1 ... 9")
                    }
                    
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Direct Auto-Paste Permission:")
                                .font(.system(size: 12, weight: .medium))
                            Text(isAccessibilityGranted ? "Granted. Direct paste into target apps is enabled." : "Missing. Grant Accessibility to auto-paste with Cmd+V.")
                                .font(.system(size: 10))
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
                            .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 16))
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
                
                Divider()
                
                // Section 2: General Options
                VStack(alignment: .leading, spacing: 10) {
                    Text("GENERAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Toggle("Sound Effects (Copy & Paste sounds)", isOn: $soundEnabled)
                        .onChange(of: soundEnabled) { newValue in
                            SoundManager.shared.isSoundEnabled = newValue
                        }
                    
                    Toggle("Launch at System Login", isOn: Binding(
                        get: { store.isLaunchAtLoginEnabled },
                        set: { store.isLaunchAtLoginEnabled = $0 }
                    ))
                    
                    HStack {
                        Text("History Retention Capacity:")
                        Spacer()
                        Picker("", selection: $maxHistory) {
                            Text("100 items").tag(100)
                            Text("250 items").tag(250)
                            Text("500 items").tag(500)
                            Text("1,000 items").tag(1000)
                        }
                        .frame(width: 130)
                        .onChange(of: maxHistory) { newValue in
                            store.maxHistoryCount = newValue
                        }
                    }
                }
                
                Divider()
                
                // Section 3: Data Management
                VStack(alignment: .leading, spacing: 10) {
                    Text("DATA MANAGEMENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clipboard History")
                                .font(.system(size: 12, weight: .medium))
                            Text("\(store.items.count) items stored (\(store.items.filter { $0.isPinned }.count) pinned)")
                                .font(.system(size: 10))
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
                
                Divider()
                
                // Section 4: About & Author (Quốc Ngô)
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.yellow)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PasteFlow v1.1.0")
                                .font(.system(size: 13, weight: .bold))
                            Text("Developed with ❤️ by Quốc Ngô (@lengo0951)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("GitHub") {
                            if let url = URL(string: "https://github.com/lengo0951/quocngokit") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 490)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            isAccessibilityGranted = PasteSimulator.shared.isAccessibilityGranted
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
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(5)
        }
    }
}
