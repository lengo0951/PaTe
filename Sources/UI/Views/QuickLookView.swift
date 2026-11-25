import SwiftUI
import AppKit

public struct QuickLookView: View {
    let item: ClipboardItem
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipboardItem, Bool, CredentialPasteMode) -> Void
    let onClose: () -> Void
    
    @State private var localKeyMonitor: Any?
    @State private var copyFeedback: Bool = false
    @State private var revealSecret: Bool = false
    
    private func navigatePrevious() {
        let items = store.filteredItems
        guard !items.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let prevIdx = idx > 0 ? idx - 1 : items.count - 1
            store.activeQuickLookItem = items[prevIdx]
            store.selectedItemID = items[prevIdx].id
        }
    }
    
    private func navigateNext() {
        let items = store.filteredItems
        guard !items.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let nextIdx = idx < items.count - 1 ? idx + 1 : 0
            store.activeQuickLookItem = items[nextIdx]
            store.selectedItemID = items[nextIdx].id
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        if item.contentType == .credential {
            if let secret = CredentialVault.shared.getSecret(for: item.id) {
                NSPasteboard.general.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                NSPasteboard.general.setString(secret, forType: .string)
            }
        } else if let text = item.textValue {
            NSPasteboard.general.setString(text, forType: .string)
        }
        SoundManager.shared.playCopy()
        withAnimation(.easeInOut(duration: 0.2)) {
            copyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                copyFeedback = false
            }
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                if item.contentType == .credential {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hexString: "#FF375F"))
                } else if let icon = AppIconCache.shared.icon(for: item.appBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                        .cornerRadius(5)
                } else {
                    Image(systemName: item.contentType.iconName)
                        .font(.system(size: 16))
                        .foregroundColor(AppConfig.shared.accentTheme.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.customTitle ?? item.appName ?? item.contentType.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(item.customTitle != nil ? AppConfig.shared.accentTheme.color : .primary)
                        .lineLimit(1)
                    
                    Text("\(item.appName ?? item.contentType.displayName) • \(item.formattedRelativeTime)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    if item.contentType == .credential {
                        store.credentialItemBeingEdited = item
                    } else {
                        store.itemBeingRenamed = item
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text(item.contentType == .credential ? "Edit" : (item.customTitle != nil ? "Edit Name" : "Name"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 4) {
                    Button(action: navigatePrevious) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: navigateNext) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))
            
            Divider()
                .opacity(0.3)
            
            // Content Body
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch item.contentType {
                    case .credential:
                        let secret = CredentialVault.shared.getSecret(for: item.id) ?? ""
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("USERNAME")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Text(item.credentialUsername ?? "—")
                                        .font(.system(size: 14, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Button("Type User & Pre-load Pass (⌘U)") {
                                    onPaste(item, true, .usernameOnlyAndPreloadSecret)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("PASSWORD / SECRET")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Text(revealSecret ? secret : "••••••••••••••••")
                                        .font(.system(size: 14, design: .monospaced))
                                }
                                Spacer()
                                Button(revealSecret ? "Hide" : "Reveal") {
                                    revealSecret.toggle()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                            
                            if let urlStr = item.credentialURL, !urlStr.isEmpty {
                                Text("URL: \(urlStr)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                    case .text, .code:
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.textValue ?? "")
                                .font(item.contentType == .code ? .system(size: 13, design: .monospaced) : .system(size: 14))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(8)
                            
                            HStack(spacing: 12) {
                                Label("\(item.lineCount) lines", systemImage: "text.alignleft")
                                Label("\(item.characterCount) chars", systemImage: "character")
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                        
                    case .image:
                        if let fileName = item.imageFileName,
                           let nsImage = store.loadImage(fileName: fileName) {
                            VStack(spacing: 10) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 320)
                                    .cornerRadius(8)
                                    .shadow(radius: 6)
                                    
                                if let w = item.imageWidth, let h = item.imageHeight {
                                    Text("Resolution: \(w) × \(h) px")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                    case .color:
                        let colorHex = item.textValue ?? "#FFFFFF"
                        let color = Color(hexString: colorHex)
                        VStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(color)
                                .frame(width: 140, height: 140)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                )
                                .shadow(color: color.opacity(0.5), radius: 16, x: 0, y: 8)
                            
                            Text(colorHex.uppercased())
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        
                    case .link:
                        VStack(alignment: .leading, spacing: 14) {
                            Text(item.textValue ?? "")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(AppConfig.shared.accentTheme.color)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(AppConfig.shared.accentTheme.color.opacity(0.1))
                                .cornerRadius(8)
                            
                            if let urlStr = item.textValue, let url = URL(string: urlStr) {
                                Button("Open in Browser") {
                                    NSWorkspace.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppConfig.shared.accentTheme.color)
                            }
                        }
                        
                    case .file:
                        VStack(alignment: .leading, spacing: 12) {
                            if let paths = item.filePaths {
                                ForEach(paths, id: \.self) { path in
                                    HStack(spacing: 8) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Button("Reveal") {
                                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(8)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: 380)
            
            Divider()
                .opacity(0.3)
            
            // Footer Actions
            HStack(spacing: 12) {
                if item.contentType == .credential {
                    Button("Auto-Fill User ⇥ Pass (⏎)") {
                        onPaste(item, true, .smartAutoFill)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hexString: "#FF375F"))
                    
                    Button("Paste Password Only (⌥⏎)") {
                        onPaste(item, true, .passwordOnly)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Paste (Return)") {
                        onPaste(item, false, .smartAutoFill)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppConfig.shared.accentTheme.color)
                    
                    Button("Paste Plain Text (⌥Return)") {
                        onPaste(item, true, .smartAutoFill)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                        Text(copyFeedback ? "Copied!" : "Copy (⌘C)")
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text("Space / Esc to close")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))
        }
        .frame(width: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(radius: 20)
        .onAppear {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49 || event.keyCode == 53 {
                    onClose()
                    return nil
                }
                if event.keyCode == 123 {
                    navigatePrevious()
                    return nil
                }
                if event.keyCode == 124 {
                    navigateNext()
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 {
                    if item.contentType == .credential {
                        if event.modifierFlags.contains(.shift) {
                            onPaste(item, true, .smartAutoFillAndSubmit)
                        } else if event.modifierFlags.contains(.option) {
                            onPaste(item, true, .passwordOnly)
                        } else {
                            onPaste(item, true, .smartAutoFill)
                        }
                    } else {
                        let isPlainText = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift)
                        onPaste(item, isPlainText, .smartAutoFill)
                    }
                    return nil
                }
                if event.keyCode == 32 && event.modifierFlags.contains(.command) && item.contentType == .credential {
                    onPaste(item, true, .usernameOnlyAndPreloadSecret)
                    return nil
                }
                if event.keyCode == 8 && event.modifierFlags.contains(.command) {
                    copyToClipboard()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = localKeyMonitor {
                NSEvent.removeMonitor(monitor)
                localKeyMonitor = nil
            }
        }
    }
}
