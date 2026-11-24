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
    
    @State private var isAddingPinboard: Bool = false
    @State private var newPinboardName: String = ""
    @State private var newPinboardColor: String = "#0A84FF"
    @State private var isSettingsPresented: Bool = false
    
    let colorPalette = [
        "#0A84FF", "#30D158", "#FF9F0A", "#FF453A", "#BF5AF2", "#64D2FF", "#FF375F", "#FFD60A"
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
                    isSelected: store.selectedContentType == nil
                ) {
                    store.selectedContentType = nil
                }
                
                ForEach(ContentType.allCases, id: \.self) { type in
                    FilterPill(
                        title: type.displayName,
                        icon: type.iconName,
                        isSelected: store.selectedContentType == type
                    ) {
                        store.selectedContentType = (store.selectedContentType == type ? nil : type)
                    }
                }
                
                Spacer()
                
                Text("\(store.filteredItems.count) clips")
                    .font(.system(size: 11))
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
        }
        .frame(height: 290)
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
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
                    .fill(isSelected ? Color.blue : Color.white.opacity(0.08))
            )
            .foregroundColor(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}
