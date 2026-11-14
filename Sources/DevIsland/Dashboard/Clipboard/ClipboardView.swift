import SwiftUI

/// Clipboard history: search, pin, copy again. Kept in memory only.
struct ClipboardView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let clipboard = model.clipboard
        let enabled = model.integrations.isEnabled(clipboard.id)
        PageScaffold(title: "Clipboard", subtitle: "Recent copies, kept in memory only and never written to disk.") {
            Toggle("History", isOn: Binding(
                get: { enabled },
                set: { model.integrations.setEnabled($0, for: clipboard.id) }))
                .toggleStyle(.switch)
        } content: {
            if !enabled {
                Card {
                    EmptyStateView(symbol: "doc.on.clipboard", title: "Clipboard history is off",
                                   message: "Turn it on to keep your last 50 copied texts. Items from password managers are always skipped.") {
                        Button("Turn On") { model.integrations.setEnabled(true, for: clipboard.id) }
                            .buttonStyle(.primary)
                    }
                }
            } else if clipboard.items.isEmpty {
                Card {
                    EmptyStateView(symbol: "doc.on.clipboard", title: "Nothing copied yet",
                                   message: "Copy some text anywhere and it shows up here.")
                }
            } else {
                HStack(spacing: 12) {
                    SearchField(prompt: "Search clipboard", text: $query)
                    Button("Clear") { clipboard.clear() }
                        .buttonStyle(.secondary)
                        .help("Removes everything except pinned items")
                }
                let filtered = clipboard.items.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
                let pinned = filtered.filter(\.isPinned)
                let recent = filtered.filter { !$0.isPinned }
                if !pinned.isEmpty {
                    section("Pinned", pinned)
                }
                if !recent.isEmpty {
                    section("Recent", recent)
                } else if pinned.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section(_ title: String, _ items: [ClipItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            CardList(items: items, dividerInset: 56) { ClipRow(item: $0) }
        }
    }
}

private struct ClipRow: View {
    @Environment(AppModel.self) private var model
    let item: ClipItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: item.isLink ? "link" : "text.alignleft",
                      tint: item.isLink ? SourceStyle.tint("clipboard") : Color(white: 0.55), size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .lineLimit(2)
                Text(item.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                if let url = item.url {
                    rowButton("arrow.up.right.square", "Open link") { NSWorkspace.shared.open(url) }
                }
                rowButton(item.isPinned ? "pin.slash" : "pin", item.isPinned ? "Unpin" : "Pin") {
                    model.clipboard.togglePin(item)
                }
                rowButton("trash", "Delete") { model.clipboard.delete(item) }
            }
            .opacity(hovering || item.isPinned ? 1 : 0)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            model.clipboard.copy(item)
            model.showToast("Copied to clipboard")
        }
        .help("Click to copy")
    }

    private func rowButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}
