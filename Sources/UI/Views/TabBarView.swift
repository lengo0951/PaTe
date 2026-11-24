import SwiftUI

public struct TabBarView: View {
    @ObservedObject var store: HistoryStore
    @Binding var isAddingPinboard: Bool
    @Binding var isSettingsPresented: Bool
    
    @ObservedObject private var config = AppConfig.shared
    
    public var body: some View {
        HStack(spacing: 12) {
            // Pinboards Tab List
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.pinboards) { pinboard in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                store.selectedPinboardID = pinboard.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hexString: pinboard.colorHex))
                                    .frame(width: 8, height: 8)
                                
                                Text(pinboard.name)
                                    .font(.system(size: 12, weight: store.selectedPinboardID == pinboard.id ? .semibold : .regular))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(store.selectedPinboardID == pinboard.id ? config.accentTheme.color.opacity(0.2) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(store.selectedPinboardID == pinboard.id ? config.accentTheme.color.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !pinboard.isSystem {
                                Button(role: .destructive) {
                                    store.removePinboard(id: pinboard.id)
                                } label: {
                                    Label("Delete Pinboard", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    // Add Pinboard Button
                    Button {
                        isAddingPinboard = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Create new Pinboard")
                }
            }
            
            Spacer()
            
            // Search Input Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(store.searchQuery.isEmpty ? .secondary : config.accentTheme.color)
                
                TextField("Search history... (⌘F)", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 150)
                
                if !store.searchQuery.isEmpty {
                    Button {
                        store.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.22))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(store.searchQuery.isEmpty ? Color.white.opacity(0.1) : config.accentTheme.color.opacity(0.5), lineWidth: 1)
            )
            
            // Pause / Resume Toggle
            Button {
                store.isMonitoringPaused.toggle()
            } label: {
                Image(systemName: store.isMonitoringPaused ? "pause.circle.fill" : "record.circle")
                    .font(.system(size: 14))
                    .foregroundColor(store.isMonitoringPaused ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(store.isMonitoringPaused ? "Resume tracking clipboard" : "Pause tracking clipboard")
            
            // Settings Button
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Preferences (Themes, Shortcuts, Privacy)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
