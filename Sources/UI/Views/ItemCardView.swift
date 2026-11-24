import SwiftUI
import AppKit

public struct ItemCardView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipboardItem, Bool) -> Void
    let onSelect: (ClipboardItem) -> Void
    
    @ObservedObject private var config = AppConfig.shared
    @State private var isHovered: Bool = false
    
    private var appIcon: NSImage? {
        return AppIconCache.shared.icon(for: item.appBundleID)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Card Header
            HStack(spacing: 8) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .cornerRadius(4)
                } else {
                    Image(systemName: item.contentType.iconName)
                        .font(.system(size: 12))
                        .foregroundColor(config.accentTheme.color)
                }
                
                Text(item.appName ?? item.contentType.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                
                Spacer()
                
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                
                Text(item.formattedRelativeTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            Divider()
                .opacity(0.4)
            
            // MARK: - Card Body
            Group {
                switch item.contentType {
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
                Text(item.displaySubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Shortcut Badge (1..9)
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
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onPaste(item, config.pastePlainTextByDefault)
        }
        .onTapGesture(count: 1) {
            onSelect(item)
        }
        .contextMenu {
            Button("Paste to Active App (Return)") {
                onPaste(item, false)
            }
            Button("Paste as Plain Text (⌥Return)") {
                onPaste(item, true)
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
            
            Button("Rename Clip... (R)") {
                store.itemBeingRenamed = item
            }
            
            Divider()
            
            Menu("Pin to Pinboard") {
                ForEach(store.pinboards.filter { !$0.isSystem }) { pinboard in
                    Button {
                        store.togglePin(itemID: item.id, pinboardID: pinboard.id)
                    } label: {
                        HStack {
                            Text(pinboard.name)
                            if item.pinboardIDs.contains(pinboard.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                store.removeItem(id: item.id)
            } label: {
                Label("Delete Item (⌫)", systemImage: "trash")
            }
        }
    }
}
