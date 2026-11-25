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
    let onPaste: (ClipboardItem, Bool, CredentialPasteMode) -> Void
    
    @ObservedObject private var config = AppConfig.shared
    @State private var isAddingPinboard: Bool = false
    @State private var newPinboardName: String = ""
    @State private var newPinboardColor: String = "#0A84FF"
    @State private var isSettingsPresented: Bool = false
    
    let colorPalette = [
        "#0A84FF", "#30D158", "#FF9F0A", "#FF453A", "#BF5AF2", "#64D2FF", "#FF375F", "#8E8E93"
    ]
    
    private var selectedItem: ClipboardItem? {
        guard let id = store.selectedItemID else { return store.filteredItems.first }
        return store.filteredItems.first(where: { $0.id == id })
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top TabBar & Pinboards
            TabBarView(
                store: store,
                isAddingPinboard: $isAddingPinboard,
                isSettingsPresented: $isSettingsPresented,
                onSubmitSearch: {
                    if let target = selectedItem {
                        onPaste(target, config.pastePlainTextByDefault, .defaultSecret)
                    }
                }
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
                        accentColor: type == .credential ? Color(hexString: "#FF375F") : config.accentTheme.color
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
            
            // MARK: - Bottom Shortcut Hint Bar (Context-Aware Ergonomic Footer)
            if config.showShortcutHints {
                Divider()
                    .opacity(0.2)
                
                HStack(spacing: 12) {
                    if selectedItem?.contentType == .credential {
                        HintPill(key: "⏎ / 2xClick", label: "Paste Pass")
                        HintPill(key: "⌘U", label: "Paste User")
                        HintPill(key: "⌘⇧⏎", label: "Auto-Fill Tab")
                        HintPill(key: "R", label: "Edit Account")
                        HintPill(key: "⌘N", label: "New Account")
                    } else {
                        HintPill(key: "⏎ / 2xClick", label: "Paste")
                        HintPill(key: "⌥⏎", label: "Plain Text")
                        HintPill(key: "Space", label: "Preview")
                        HintPill(key: "← →", label: "Browse")
                        HintPill(key: "1..9", label: "Quick Paste")
                        HintPill(key: "R", label: "Rename")
                        HintPill(key: "⌘N", label: "Add Account")
                    }
                    
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
        .onChange(of: isAddingPinboard) { val in
            PanelController.shared.isAddPinboardSheetOpen = val
        }
        .onChange(of: isSettingsPresented) { val in
            PanelController.shared.isSettingsSheetOpen = val
        }
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
                onPaste: { it, asPlain, credMode in
                    store.activeQuickLookItem = nil
                    onPaste(it, asPlain, credMode)
                },
                onClose: {
                    store.activeQuickLookItem = nil
                }
            )
        }
        // Rename Sheet (R)
        .sheet(item: $store.itemBeingRenamed) { item in
            RenameModalView(item: item, store: store)
        }
        // Add New Credential Sheet (⌘N or + Account)
        .sheet(isPresented: $store.isCredentialModalPresented) {
            CredentialModalView(mode: .createNew, store: store)
        }
        // Edit Existing Credential Sheet
        .sheet(item: $store.credentialItemBeingEdited) { item in
            CredentialModalView(mode: .editExisting(item), store: store)
        }
        // Convert Existing Text Clip to Encrypted Credential
        .sheet(item: $store.itemConvertingToCredential) { item in
            CredentialModalView(mode: .convertClip(item), store: store)
        }
    }
}

public enum CredentialModalMode {
    case createNew
    case editExisting(ClipboardItem)
    case convertClip(ClipboardItem)
}

public struct CredentialModalView: View {
    let mode: CredentialModalMode
    @ObservedObject var store: HistoryStore
    
    @State private var title: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var url: String = ""
    @State private var showPassword: Bool = false
    
    public init(mode: CredentialModalMode, store: HistoryStore) {
        self.mode = mode
        self.store = store
        switch mode {
        case .createNew:
            _title = State(initialValue: "")
            _username = State(initialValue: "")
            _password = State(initialValue: "")
            _url = State(initialValue: "")
        case .editExisting(let item):
            _title = State(initialValue: item.customTitle ?? "")
            _username = State(initialValue: item.credentialUsername ?? "")
            _password = State(initialValue: CredentialVault.shared.getSecret(for: item.id) ?? "")
            _url = State(initialValue: item.credentialURL ?? "")
        case .convertClip(let item):
            _title = State(initialValue: item.customTitle ?? "")
            _username = State(initialValue: "")
            _password = State(initialValue: item.textValue ?? "")
            _url = State(initialValue: "")
        }
    }
    
    private func dismissModal() {
        store.isCredentialModalPresented = false
        store.credentialItemBeingEdited = nil
        store.itemConvertingToCredential = nil
    }
    
    private func save() {
        let existingID: String? = {
            switch mode {
            case .createNew: return nil
            case .editExisting(let item): return item.id
            case .convertClip(let item): return item.id
            }
        }()
        store.saveCredential(
            existingID: existingID,
            title: title,
            username: username,
            password: password,
            url: url
        )
        dismissModal()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hexString: "#FF375F"))
                VStack(alignment: .leading, spacing: 1) {
                    Text({
                        switch mode {
                        case .createNew: return "Save Account & Password"
                        case .editExisting: return "Edit Saved Account"
                        case .convertClip: return "Encrypt Clip into Vault"
                        }
                    }())
                    .font(.system(size: 15, weight: .bold))
                    Text("Encrypted with AES-256-GCM & macOS Keychain")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: dismissModal) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Name / Service")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. dgcb sso prod, AWS Production, GitHub...", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username / Email")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. quoc.ngo@company.vn", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password / Secret Token")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        if showPassword {
                            TextField("Password or token", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12.5, design: .monospaced))
                        } else {
                            SecureField("Password or token", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Website URL (Optional)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("e.g. https://sso.cnsc.com.vn", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel", action: dismissModal)
                    .keyboardShortcut(.cancelAction)
                
                Button("Save to Vault", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hexString: "#FF375F"))
                    .disabled(password.isEmpty && username.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 400)
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

public struct RenameModalView: View {
    let item: ClipboardItem
    @ObservedObject var store: HistoryStore
    
    @State private var name: String
    @ObservedObject private var config = AppConfig.shared
    
    public init(item: ClipboardItem, store: HistoryStore) {
        self.item = item
        self.store = store
        self._name = State(initialValue: item.customTitle ?? "")
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 16))
                    .foregroundColor(config.accentTheme.color)
                Text(item.customTitle != nil ? "Edit Clip Title" : "Rename Clip")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    store.itemBeingRenamed = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.contentType.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(config.accentTheme.color)
                Text(item.textValue != nil ? String(item.textValue!.prefix(100)) : item.displayTitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            
            TextField("e.g. WiFi Password, GitLab Token, SSH Key...", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
            
            HStack(spacing: 10) {
                if item.customTitle != nil {
                    Button("Remove Name", role: .destructive) {
                        store.renameItem(id: item.id, newTitle: nil)
                        store.itemBeingRenamed = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Spacer()
                
                Button("Cancel") {
                    store.itemBeingRenamed = nil
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
                
                Button("Save Name") {
                    store.renameItem(id: item.id, newTitle: name)
                    store.itemBeingRenamed = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(config.accentTheme.color)
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}
