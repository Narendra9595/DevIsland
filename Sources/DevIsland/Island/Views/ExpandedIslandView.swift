import SwiftUI

/// The expanded island: date, time and quick icons beside the notch, the page, then labelled tabs.
struct ExpandedIslandView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(model: model)
                .frame(height: model.geometry.topHeight)

            Group {
                switch model.page {
                case .activity:
                    if let activity = model.current {
                        // The activity sits on a glass pane, tinted with its own color.
                        IslandActivityView(activity: activity)
                            .islandPane(tint: activity.event.tint.opacity(0.22))
                            .id(activity.key)
                    }
                case .home:
                    IslandHomeView(model: model)
                case .music:
                    if let music = model.music {
                        NowPlayingView(model: model, activity: music)
                            .islandPane(tint: music.event.tint.opacity(0.18))
                    }
                case .files:
                    IslandFilesView()
                case .tools:
                    IslandToolsView(model: model)
                case .clipboard:
                    IslandClipboardView(model: model)
                case .camera:
                    IslandCameraView()
                case .ask:
                    AskClaudeView(model: model)
                case .notes:
                    IslandNotesView()
                case .usage:
                    IslandUsageView()
                }
            }
            .frame(height: model.expandedContentHeight, alignment: .top)

            IslandTabBar(model: model)
                .frame(height: IslandMetrics.tabBarHeight, alignment: .top)
            .transition(.blurReplace)
        }
    }
}

extension View {
    /// A page's content on a rounded glass pane inside the island.
    func islandPane(tint: Color? = nil) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), tint: tint, fallback: .white.opacity(0.06))
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 10)
    }
}

/// Left of the notch: page tabs. Right: agent state / switcher on the activity page, otherwise time and quick icons.
struct IslandHeader: View {
    let model: IslandViewModel

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if model.isToolSubpage {
                    // Back to Tools from Clipboard, Notes, Mirror or Usage.
                    Button { model.show(.tools) } label: {
                        Label("Tools", systemImage: "chevron.left")
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: model.geometry.centerWidth)
            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.7))
    }

    @ViewBuilder
    private var trailing: some View {
        let store = model.app.store
        if model.page == .activity, store.live.count > 1 {
            HStack(spacing: 5) {
                ForEach(store.live) { activity in
                    let selected = activity.key == store.current?.key
                    PageTab(selected: selected, help: SourceStyle.name(activity.event.source),
                            source: activity.event.source, symbol: activity.event.displaySymbol) {
                        model.showActivity(activity.key)
                    }
                }
            }
        } else if model.page == .activity, let event = model.current?.event, case .agent(let state) = ActivityPresentation(event) {
            AgentStateChip(state: state)
        } else {
            HStack(spacing: 8) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                }
                PageTab(selected: false, help: "Dashboard", symbol: "macwindow") { model.app.windows?.showDashboard(nil) }
                PageTab(selected: false, help: model.app.updates.available == nil ? "Settings" : "Update available",
                        symbol: "gearshape.fill") {
                    model.app.windows?.showSettings(tab: model.app.updates.available == nil ? nil : "About")
                }
                .overlay(alignment: .topTrailing) {
                    if model.app.updates.available != nil {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7).offset(x: 1, y: -1)
                    }
                }
            }
        }
    }
}

/// Labelled page tabs along the bottom: what each page is, and which one you're on.
struct IslandTabBar: View {
    let model: IslandViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabPages, id: \.self) { page in
                tab(page)
            }
        }
        .padding(3)
        .background(.white.opacity(0.06), in: Capsule())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tab(_ page: IslandPage) -> some View {
        let event = model.current?.event
        switch page {
        case .activity:
            TabButton(title: event.map { SourceStyle.name($0.source) } ?? "Now", symbol: event?.displaySymbol ?? "bolt.fill",
                      tint: event?.tint ?? .white, claude: event?.source == "claude", selected: model.page == .activity) {
                model.show(.activity)
            }
        case .home:
            TabButton(title: "Home", symbol: "house.fill", selected: model.page == .home) { model.show(.home) }
        case .music:
            TabButton(title: "Music", symbol: "music.note", tint: SourceStyle.tint("media"), selected: model.page == .music) {
                model.show(.music)
            }
        case .files:
            TabButton(title: "Files", symbol: "tray.full.fill", badge: model.app.shelf.files.count, selected: model.page == .files) {
                model.show(.files)
            }
        case .tools:
            TabButton(title: "Tools", symbol: "square.grid.2x2.fill",
                      selected: [.tools, .usage, .clipboard, .camera, .notes].contains(model.page)) { model.show(.tools) }
        default:
            EmptyView()
        }
    }
}

private struct TabButton: View {
    let title: String
    let symbol: String
    var tint: Color = .white
    var claude = false
    var badge = 0
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.highlight) private var highlight

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if claude {
                    ClaudeMark(size: 13, color: selected ? .white : SourceStyle.tint("claude"))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(selected ? .white : tint.opacity(0.9))
                }
                if selected || hovering {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minHeight: 14)
                        .background(selected ? .white.opacity(0.25) : highlight, in: Capsule())
                }
            }
            .lineLimit(1)
            .padding(.horizontal, selected || hovering ? 10 : 8)
            .frame(height: 24)
            .background(selected ? highlight.opacity(0.85) : .white.opacity(hovering ? 0.1 : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.2), value: hovering)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: selected)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small round glass button: white when selected, optional count badge.
private struct PageTab: View {
    let selected: Bool
    let help: String
    var tint: Color = .white.opacity(0.85)
    var source: String?
    let symbol: String
    var badge = 0
    let action: () -> Void
    @Environment(\.highlight) private var highlight

    var body: some View {
        Button(action: action) {
            Group {
                if source == "claude" {
                    ClaudeMark(size: 13, color: selected ? .white : SourceStyle.tint("claude"))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(selected ? .white : tint)
                }
            }
            .frame(width: 22, height: 22)
            .glass(in: Circle(), tint: selected ? highlight : nil, interactive: true,
                   fallback: selected ? highlight : .white.opacity(0.14))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 11, minHeight: 11)
                        .background(selected ? .black.opacity(0.6) : highlight, in: Capsule())
                        .offset(x: 3, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The island's Usage page: Claude Code's 5-hour and weekly limits as rings.
struct IslandUsageView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let usage = app.currentClaudeUsage
        HStack(spacing: 28) {
            UsageRing(source: "claude", title: "5-hour", window: usage?.fiveHour, size: 62, dark: true)
            UsageRing(source: "claude", title: "Weekly", window: usage?.sevenDay, size: 62, dark: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(usage == nil
                     ? "Limits show up after your next Claude Code message (Pro, Max and Ultra plans)."
                     : "\(Format.duration(app.today.agentActiveTime)) of agent time today · \(app.today.agentTurns) turns")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Agents") { app.windows?.showDashboard(.agents) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .islandPane()
    }
}

// MARK: - Files page

/// Files dropped on the island: drag out, double-click to open, right-click for developer actions.
struct IslandFilesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let shelf = app.shelf
        VStack(alignment: .leading, spacing: 8) {
            if shelf.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 20, weight: .medium))
                    Text("Drop files on the island to keep them here")
                        .font(.system(size: 12, weight: .medium))
                    Text("They stay until you remove them, even after a restart.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(shelf.files.prefix(8), id: \.self) { url in
                        FileCard(url: url, shelf: shelf)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(summary(shelf.files))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Button("Clear All") { shelf.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(10)
        .islandPane()
    }

    private func summary(_ files: [URL]) -> String {
        let bytes = files.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let more = files.count > 8 ? " · \(files.count - 8) more in the Dashboard" : ""
        return "\(files.count) \(files.count == 1 ? "file" : "files") · \(Format.bytes(bytes))\(more)"
    }
}

private struct FileCard: View {
    let url: URL
    let shelf: FileShelf
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
            Text(url.lastPathComponent)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(.white.opacity(hovering ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .padding(3)
                .help("Remove from Shelf")
            }
        }
        .onHover { hovering = $0 }
        .help(url.path)
        .draggable(url)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Button("Open in Terminal") { openInTerminal() }
            ShareLink(item: url) { Text("Share…") }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
    }

    /// Opens Terminal in the folder (or the file's folder).
    private func openInTerminal() {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let folder = isFolder ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.open([folder], withApplicationAt: URL(filePath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
