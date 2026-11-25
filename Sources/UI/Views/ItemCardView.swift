import SwiftUI
import AppKit

public struct ItemCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipboardItem, Bool, CredentialPasteMode) -> Void
    let onSelect: (ClipboardItem) -> Void
    
    @ObservedObject private var config = AppConfig.shared
    @State private var isHovered: Bool = false
    @State private var lastClickUptime: TimeInterval = 0
    
    private var appIcon: NSImage? {
        if item.contentType == .credential { return nil }
        return AppIconCache.shared.icon(for: item.appBundleID)
    }
    
    private var footerSubtitle: String {
        let time = item.formattedRelativeTime
        switch item.contentType {
        case .credential:
            return "🔒 Vault • \(time)"
        case .text:
            return "\(item.characterCount) chars • \(time)"
        case .code:
            return "\(item.characterCount) chars • \(time)"
        case .image:
            return "\(item.displaySubtitle) • \(time)"
        case .color:
            return "\(item.displaySubtitle) • \(time)"
        case .file:
            return "\(item.displaySubtitle) • \(time)"
        case .link:
            if let text = item.textValue, let url = URL(string: text), let host = url.host {
                return "\(host) • \(time)"
            }
            return "Link • \(time)"
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Card Header
            HStack(spacing: 6) {
                if item.contentType == .credential {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hexString: "#FF375F"))
                } else if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(3.5)
                } else {
                    Image(systemName: item.contentType.iconName)
                        .font(.system(size: 11))
                        .foregroundColor(config.accentTheme.color)
                }
                
                Text(item.customTitle ?? item.appName ?? item.contentType.displayName)
                    .font(.system(size: 11, weight: (item.customTitle != nil || item.contentType == .credential) ? .bold : .medium))
                    .foregroundColor(
                        item.contentType == .credential
                            ? Color(hexString: "#FF375F")
                            : (item.customTitle != nil ? config.accentTheme.color : .primary.opacity(0.85))
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer(minLength: 4)
                
                if item.isPinned {
                    Image(systemName: item.contentType == .credential ? "key.fill" : "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(item.contentType == .credential ? Color(hexString: "#FF375F") : .orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background((item.contentType == .credential ? Color(hexString: "#FF375F") : Color.orange).opacity(0.12))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Card Body
            Group {
                switch item.contentType {
                case .credential:
                    CredentialContentView(
                        item: item,
                        onPasteUsername: {
                            onPaste(item, true, .usernameOnlyAndPreloadSecret)
                        },
                        onPastePassword: {
                            onPaste(item, true, .passwordOnly)
                        }
                    )
                case .text, .code:
                    TextContentView(item: item)
                case .image:
                    ImageContentView(item: item, store: store)
                case .link:
                    LinkContentView(item: item)
                case .color:
                    ColorContentView(item: item)
                case .file:
                    FileContentView(item: item)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Card Footer
            HStack {
                Text(footerSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? config.accentTheme.color : Color.primary.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .background(isSelected ? config.accentTheme.color.opacity(0.15) : Color.primary.opacity(0.08))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? config.accentTheme.color.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 200, height: 210)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected ? config.accentTheme.color : (isHovered ? Color.white.opacity(0.35) : Color.white.opacity(0.12)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: isSelected ? config.accentTheme.color.opacity(0.35) : Color.black.opacity(0.18),
            radius: isSelected ? 8 : 4,
            x: 0,
            y: 2
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.08), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        // Deterministic, zero-lag monotonic click / double-click handler
        .onTapGesture {
            let now = ProcessInfo.processInfo.systemUptime
            let threshold = max(NSEvent.doubleClickInterval, 0.32)
            if now - lastClickUptime <= threshold {
                lastClickUptime = 0
                onPaste(item, config.pastePlainTextByDefault, .smartAutoFill)
            } else {
                lastClickUptime = now
                store.lastSelectionWasKeyboard = false
                onSelect(item)
            }
        }
        .contextMenu {
            if item.contentType == .credential {
                Button("⚡ Auto-Fill Login: User ⇥ Pass (Return / Double-Click)") {
                    onPaste(item, true, .smartAutoFill)
                }
                Button("🚀 Auto-Fill & Submit Login (⇧Return)") {
                    onPaste(item, true, .smartAutoFillAndSubmit)
                }
                Divider()
                Button("👤 Type Username & Pre-load Pass (⌘U)") {
                    onPaste(item, true, .usernameOnlyAndPreloadSecret)
                }
                Button("🔑 Paste Password Only (⌥Return)") {
                    onPaste(item, true, .passwordOnly)
                }
                Divider()
                Button("Copy Password to Clipboard (⌘C)") {
                    PasteSimulator.shared.copyCredentialToClipboard(item, usernameOnly: false)
                }
                Button("Copy Username to Clipboard (⌘⇧C)") {
                    PasteSimulator.shared.copyCredentialToClipboard(item, usernameOnly: true)
                }
                Divider()
                Button("Edit Account / Password... (R)") {
                    NSApp.activate(ignoringOtherApps: true)
                    store.credentialItemBeingEdited = item
                }
            } else {
                Button("Paste to Active App (Return / Double-Click)") {
                    onPaste(item, false, .smartAutoFill)
                }
                Button("Paste as Plain Text (⌥Return)") {
                    onPaste(item, true, .smartAutoFill)
                }
                Button("Quick Look Preview (Space)") {
                    store.activeQuickLookItem = item
                }
                Button("Copy to Clipboard (⌘C)") {
                    NSPasteboard.general.clearContents()
                    if let text = item.textValue {
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    SoundManager.shared.playCopy()
                }
                
                Divider()
                
                Button(item.customTitle != nil ? "Edit Clip Name (R)" : "Rename Clip (R)") {
                    NSApp.activate(ignoringOtherApps: true)
                    store.itemBeingRenamed = item
                }
                
                if item.textValue != nil {
                    Button("🔒 Save as Account / Password...") {
                        NSApp.activate(ignoringOtherApps: true)
                        store.itemConvertingToCredential = item
                    }
                }
            }
            
            Divider()
            
            let customPinboards = store.pinboards.filter { !$0.isSystem }
            if !customPinboards.isEmpty {
                Menu("Pin to Pinboard") {
                    ForEach(customPinboards) { pb in
                        Button {
                            store.togglePin(itemID: item.id, pinboardID: pb.id)
                        } label: {
                            HStack {
                                Text(pb.name)
                                if item.pinboardIDs.contains(pb.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
            }
            
            Button(role: .destructive) {
                store.removeItem(id: item.id)
            } label: {
                Text("Delete")
            }
        }
    }
}
