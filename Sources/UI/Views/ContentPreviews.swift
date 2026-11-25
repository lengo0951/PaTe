import SwiftUI
import AppKit

public struct TextContentView: View {
    let item: ClipboardItem
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.textValue ?? "")
                .font(item.contentType == .code ? .system(.caption, design: .monospaced) : .system(size: 13, weight: .regular))
                .foregroundColor(Color.primary.opacity(0.9))
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
    }
}

public struct CredentialContentView: View {
    let item: ClipboardItem
    let onPasteUsername: () -> Void
    let onPastePassword: () -> Void
    
    @State private var isRevealed: Bool = false
    @State private var revealedSecret: String = ""
    @State private var copiedUserFeedback: Bool = false
    @State private var copiedPassFeedback: Bool = false
    @ObservedObject private var config = AppConfig.shared
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Username Row (Does not swallow double-clicks on card background; dedicated Copy & Paste buttons on right)
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(config.accentTheme.color)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("USERNAME")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(item.credentialUsername?.isEmpty == false ? item.credentialUsername! : "—")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer(minLength: 2)
                
                // Copy Username to Clipboard button
                Button {
                    PasteSimulator.shared.copyCredentialToClipboard(item, usernameOnly: true)
                    copiedUserFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        copiedUserFeedback = false
                    }
                } label: {
                    Image(systemName: copiedUserFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(copiedUserFeedback ? .green : .secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Copy Username to Clipboard (⌘⇧C)")
                
                // Paste Username directly to active app
                Button(action: onPasteUsername) {
                    Text("⌘U")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(config.accentTheme.color)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 2.5)
                        .background(config.accentTheme.color.opacity(0.14))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Paste Username to Active App (⌘U)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(7)
            
            // Password Row (Masked by default, with Eye reveal, Copy to Clipboard, and Paste buttons)
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("PASSWORD")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    if isRevealed {
                        Text(revealedSecret.isEmpty ? "(empty)" : revealedSecret)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("••••••••••")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 2)
                
                // Eye Reveal / Hide
                Button {
                    if !isRevealed {
                        revealedSecret = CredentialVault.shared.getSecret(for: item.id) ?? item.textValue ?? ""
                    } else {
                        revealedSecret = ""
                    }
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide Password" : "Reveal Password")
                
                // Copy Password to Clipboard
                Button {
                    PasteSimulator.shared.copyCredentialToClipboard(item, usernameOnly: false)
                    copiedPassFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        copiedPassFeedback = false
                    }
                } label: {
                    Image(systemName: copiedPassFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(copiedPassFeedback ? .green : .secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Copy Password to Clipboard (⌘C)")
                
                // Paste Password directly to active app
                Button(action: onPastePassword) {
                    Text("⏎")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .frame(width: 20, height: 20)
                        .background(Color.orange.opacity(0.16))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Paste Password to Active App (Return / Double-Click)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.07))
            .cornerRadius(7)
            
            if let url = item.credentialURL, !url.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(url)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(9)
    }
}

public struct ImageContentView: View {
    let item: ClipboardItem
    @ObservedObject var store: HistoryStore
    
    public var body: some View {
        ZStack {
            Color.black.opacity(0.15)
            
            if let nsImage = store.loadThumbnail(for: item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

public struct LinkContentView: View {
    let item: ClipboardItem
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "safari.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("Website Link")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(item.textValue ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(12)
    }
}

public struct ColorContentView: View {
    let item: ClipboardItem
    
    private var color: Color {
        guard let hex = item.textValue else { return .gray }
        return Color(hexString: hex)
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: 68, height: 68)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
            
            VStack(spacing: 4) {
                Text(item.textValue?.uppercased() ?? "")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text("Color Swatch")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
    }
}

public struct FileContentView: View {
    let item: ClipboardItem
    
    private var fileIcon: NSImage {
        if let first = item.filePaths?.first {
            return NSWorkspace.shared.icon(forFile: first)
        }
        return NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: fileIcon)
                    .resizable()
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    if let count = item.filePaths?.count, count > 1 {
                        Text("\(count) items")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else if let path = item.filePaths?.first {
                        let size = getFileSize(path: path)
                        Text(size)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let paths = item.filePaths {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(paths.prefix(3), id: \.self) { path in
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
    }
    
    private func getFileSize(path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "File"
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }
}

extension Color {
    init(hexString: String) {
        var cleanHex = hexString.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if cleanHex.count == 3 {
            cleanHex = cleanHex.map { "\($0)\($0)" }.joined()
        }
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        
        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
