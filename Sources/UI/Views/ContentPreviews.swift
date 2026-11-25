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
    @ObservedObject private var config = AppConfig.shared
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Username Row (Click to paste Username directly)
            Button(action: onPasteUsername) {
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
                    
                    Text("⌘U")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(3)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .help("Click or press ⌘U to paste Username")
            
            // Password Row (Masked by default, Eye button to toggle reveal)
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
                        Text("••••••••••••")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 2)
                
                Button {
                    if !isRevealed {
                        revealedSecret = CredentialVault.shared.getSecret(for: item.id) ?? ""
                    } else {
                        revealedSecret = ""
                    }
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.07))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide Password" : "Reveal Password")
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
