import SwiftUI

public struct CardCollectionView: View {
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipboardItem, Bool, CredentialPasteMode) -> Void
    
    // Windowed rendering: even with 1,000+ clipboard items, SwiftUI AttributeGraph only tracks
    // the visible page (60 cards initially) and lazily expands as the user scrolls right!
    @State private var renderLimit: Int = 60
    
    public var body: some View {
        let items = store.filteredItems
        
        if items.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: store.selectedPinboardID == "vault" ? "lock.shield" : "clipboard")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                
                if store.selectedPinboardID == "vault" && store.searchQuery.isEmpty {
                    Text("No saved accounts yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        store.isCredentialModalPresented = true
                    } label: {
                        Label("Add Account & Password (⌘N)", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hexString: "#FF375F"))
                } else {
                    Text(store.searchQuery.isEmpty ? "No items in this pinboard" : "No results for \"\(store.searchQuery)\"")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Copy text, images, links, colors, or save accounts with ⌘N.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let visibleCount = min(items.count, renderLimit)
            let visibleSlice = items.prefix(visibleCount)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(visibleSlice.indices, id: \.self) { index in
                            let item = visibleSlice[index]
                            ItemCardView(
                                item: item,
                                index: index,
                                isSelected: store.selectedItemID == item.id,
                                store: store,
                                onPaste: onPaste,
                                onSelect: { selected in
                                    store.selectedItemID = selected.id
                                }
                            )
                            .id(item.id)
                            .onAppear {
                                // Auto-load next 60 cards smoothly when user scrolls near the tail
                                if index >= visibleCount - 8 && visibleCount < items.count {
                                    renderLimit = min(items.count, renderLimit + 60)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: store.selectedPinboardID) { _ in
                    renderLimit = 60
                }
                .onChange(of: store.searchQuery) { _ in
                    renderLimit = 60
                }
                .onChange(of: store.selectedItemID) { newID in
                    guard store.lastSelectionWasKeyboard, let id = newID else { return }
                    if let idx = items.firstIndex(where: { $0.id == id }), idx >= renderLimit {
                        renderLimit = min(items.count, idx + 30)
                    }
                    withAnimation(.easeOut(duration: 0.08)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}
