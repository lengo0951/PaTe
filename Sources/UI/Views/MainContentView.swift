import SwiftUI
import AppKit

public struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

public struct MainContentView: View {
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipboardItem, Bool) -> Void
    
    @ObservedObject private var config = AppConfig.shared
    @State private var isAddingPinboard: Bool = false
    @State private var newPinboardName: String = ""
    @State private var newPinboardColor: String = "#0A84FF"
    @State private var isSettingsPresented: Bool = false
    
    let colorPalette = [
        "#0A84FF", "#30D158", "#FF9F0A", "#FF453A", "#BF5AF2", "#64D2FF", "#FF375F", "#8E8E93"
    ]
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top TabBar & Pinboards
            TabBarView(
                store: store,
                isAddingPinboard: $isAddingPinboard,
                isSettingsPresented: $isSettingsPresented
            )
            
            // MARK: - Content Type Filters
            HStack(spacing: 6) {
                FilterPill(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: store.selectedContentType == nil,
                    accentColor: config.accentTheme.color
                ) {
                    store.selectedContentType = nil
                }
                
                ForEach(ContentType.allCases, id: \.self) { type in
                    FilterPill(
                        title: type.displayName,
                        icon: type.iconName,
                        isSelected: store.selectedContentType == type,
                        accentColor: config.accentTheme.color
                    ) {
                        store.selectedContentType = (store.selectedContentType == type ? nil : type)
                    }
                }
                
                Spacer()
                
                Text("\(store.filteredItems.count) clips")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            
            Divider()
                .opacity(0.3)
            
            // MARK: - Card Scroll View
            CardCollectionView(
                store: store,
                onPaste: onPaste
            )
            .frame(maxHeight: .infinity)
            
            // MARK: - Bottom Shortcut Hint Bar (Ergonomic Footer)
            if config.showShortcutHints {
                Divider()
                    .opacity(0.2)
                
                HStack(spacing: 12) {
                    HintPill(key: "⏎", label: "Paste")
                    HintPill(key: "⌥⏎", label: "Plain Text")
                    HintPill(key: "Space", label: "Preview")
                    HintPill(key: "← →", label: "Browse")
                    HintPill(key: "1..9", label: "Quick Paste")
                    HintPill(key: "⌘P", label: "Pin")
                    HintPill(key: "⌘C", label: "Copy")
                    HintPill(key: "⌫", label: "Delete")
                    
                    Spacer()
                    
                    HintPill(key: "Esc", label: "Close")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.15))
            }
        }
        .frame(height: config.showShortcutHints ? 318 : 290)
        .background(VisualEffectBackground(material: config.backdropMaterial.material, blendingMode: .behindWindow))
        .preferredColorScheme(config.appearanceMode.colorScheme)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        // Add Pinboard Sheet
        .sheet(isPresented: $isAddingPinboard) {
            VStack(spacing: 16) {
                Text("Create New Pinboard")
                    .font(.system(size: 15, weight: .bold))
                
                TextField("Pinboard Name (e.g. Snippets)", text: $newPinboardName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                
                HStack(spacing: 8) {
                    ForEach(colorPalette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hexString: hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: newPinboardColor == hex ? 2 : 0)
                            )
                            .onTapGesture {
                                newPinboardColor = hex
                            }
                    }
                }
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isAddingPinboard = false
                        newPinboardName = ""
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Create") {
                        if !newPinboardName.trimmingCharacters(in: .whitespaces).isEmpty {
                            store.addPinboard(name: newPinboardName, colorHex: newPinboardColor)
                            newPinboardName = ""
                            isAddingPinboard = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(config.accentTheme.color)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
        // Settings Sheet
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(store: store, isPresented: $isSettingsPresented)
        }
        // Quick Look Sheet (Spacebar)
        .sheet(item: $store.activeQuickLookItem) { item in
            QuickLookView(
                item: item,
                store: store,
                onPaste: { it, asPlain in
                    store.activeQuickLookItem = nil
                    onPaste(it, asPlain)
                },
                onClose: {
                    store.activeQuickLookItem = nil
                }
            )
        }
    }
}

public struct FilterPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor : Color.white.opacity(0.08))
            )
            .foregroundColor(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}

public struct HintPill: View {
    let key: String
    let label: String
    
    public var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.12))
                .cornerRadius(3)
                .foregroundColor(.primary)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
