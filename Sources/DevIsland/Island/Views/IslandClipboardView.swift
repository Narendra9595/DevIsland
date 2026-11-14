import SwiftUI

/// The island's Clipboard page: search, filter by type, click to paste into the app you were using.
struct IslandClipboardView: View {
    let model: IslandViewModel
    @State private var query = ""
    @State private var filter: ClipItem.Kind?
    @State private var pinnedOnly = false
    @Environment(\.highlight) private var highlight

    var body: some View {
        let clipboard = model.app.clipboard
        VStack(spacing: 7) {
            if !model.app.integrations.isEnabled(clipboard.id) {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 22))
                    Text("Clipboard history is off").font(.system(size: 12.5, weight: .semibold))
                    Text("Kept in memory only. Password-manager items are never saved.")
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                    Button("Turn On") { model.app.integrations.setEnabled(true, for: clipboard.id) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                list(clipboard)
                footer(clipboard)
            }
        }
        .padding(10)
        .islandPane()
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search copies or apps", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(.white.opacity(0.08), in: Capsule())

            chip(symbol: "pin.fill", help: "Pinned", on: pinnedOnly) { pinnedOnly.toggle() }
            ForEach([ClipItem.Kind.link, .code, .image, .color], id: \.self) { kind in
                chip(symbol: kind.symbol, help: kind.rawValue.capitalized, on: filter == kind) {
                    filter = filter == kind ? nil : kind
                }
            }
        }
    }

    private func chip(symbol: String, help: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(on ? .white : .white.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(on ? highlight : .white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func list(_ clipboard: ClipboardIntegration) -> some View {
        let items = clipboard.items.filter { item in
            (!pinnedOnly || item.isPinned) && (filter == nil || item.kind == filter)
                && (query.isEmpty || item.text.localizedCaseInsensitiveContains(query)
                    || (item.app?.localizedCaseInsensitiveContains(query) ?? false))
        }
        .sorted { $0.isPinned && !$1.isPinned }
        return ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(items) { item in
                    ClipRow(item: item, clipboard: clipboard) { model.paste(item) }
                }
            }
        }
        .scrollIndicators(.never)
        .overlay {
            if items.isEmpty {
                Text(clipboard.items.isEmpty ? "Copy something and it shows up here" : "Nothing matches")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func footer(_ clipboard: ClipboardIntegration) -> some View {
        HStack {
            if clipboard.canPaste {
                Text("Click to paste · ⌃⌥V opens this anywhere")
            } else {
                Text("Click to copy.")
                Button("Paste for me…") { clipboard.requestPastePermission() }
                    .buttonStyle(.plain)
                    .foregroundStyle(highlight)
                    .help("Lets DevIsland press ⌘V for you (Accessibility permission)")
            }
            Spacer()
            Button("Clear") { clipboard.clear() }.buttonStyle(.plain)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let clipboard: ClipboardIntegration
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            Text(item.preview)
                .font(item.kind == .code ? .system(size: 11, design: .monospaced) : .system(size: 11.5))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovering {
                Button { clipboard.togglePin(item) } label: { Image(systemName: item.isPinned ? "pin.slash" : "pin") }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "Unpin" : "Pin")
                Button { clipboard.delete(item) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("Delete")
            } else {
                if item.isPinned { Image(systemName: "pin.fill").foregroundStyle(.white.opacity(0.5)) }
                Text(item.app ?? "").foregroundStyle(.white.opacity(0.35))
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 7)
        .frame(height: 28)
        .background(.white.opacity(hovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .help(item.text.prefix(300))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.image, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if item.kind == .color, let color = Color(hex: item.text) {
            Circle().fill(color).frame(width: 16, height: 16).overlay(Circle().strokeBorder(.white.opacity(0.3)))
                .frame(width: 20)
        } else {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SourceStyle.tint("clipboard"))
                .frame(width: 20)
        }
    }
}
