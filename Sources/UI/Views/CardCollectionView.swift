import SwiftUI

public struct CardCollectionView: View {
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipboardItem, Bool, CredentialPasteMode) -> Void
    
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
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: store.selectedItemID) { newID in
                    // Only scroll automatically during keyboard arrow navigation!
                    // Never shift cards under the mouse cursor during clicks/double-clicks!
                    guard store.lastSelectionWasKeyboard, let id = newID else { return }
                    withAnimation(.easeOut(duration: 0.08)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}
