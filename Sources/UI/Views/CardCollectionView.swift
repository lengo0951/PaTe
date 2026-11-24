import SwiftUI

public struct CardCollectionView: View {
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipboardItem, Bool) -> Void
    
    public var body: some View {
        let items = store.filteredItems
        
        if items.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "clipboard")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                
                Text(store.searchQuery.isEmpty ? "No items in this pinboard" : "No results for \"\(store.searchQuery)\"")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Copy text, images, links, or colors to see them here.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
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
                    if let id = newID {
                        withAnimation(.easeOut(duration: 0.08)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
