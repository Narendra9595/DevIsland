import Charts
import SwiftUI

/// Searchable history with a 14-day chart.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var source: String?
    @State private var results: [ActivityEvent] = []
    @State private var daily: [DailyCount] = []
    @State private var sources: [String] = []
    @State private var confirmingClear = false

    private struct LoadKey: Equatable {
        let query: String
        let source: String?
        let revision: Int
    }

    var body: some View {
        PageScaffold(title: "Activity", subtitle: "Everything DevIsland has seen, stored only on this Mac.") {
            HStack(spacing: 8) {
                Button { model.exportHistory() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.secondary)
                Button { confirmingClear = true } label: { Label("Clear", systemImage: "trash") }
                    .buttonStyle(.secondary)
                    .disabled(model.store.history.isEmpty)
            }
        } content: {
            chartCard
            HStack(spacing: 12) {
                SearchField(prompt: "Search events", text: $query)
                sourceMenu
            }
            timeline
        }
        .task(id: LoadKey(query: query, source: source, revision: model.store.revision)) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            load()
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { model.store.clearHistory() }
        } message: {
            Text("This permanently deletes every saved event from this Mac.")
        }
    }

    private var chartCard: some View {
        let names = Array(Set(daily.map(\.source))).sorted()
        let total = daily.reduce(0) { $0 + $1.count }
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Last 14 days", subtitle: "\(total) saved \(total == 1 ? "event" : "events")")
                if daily.isEmpty {
                    Text("No events yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart(daily) { item in
                        BarMark(x: .value("Day", item.day, unit: .day), y: .value("Events", item.count))
                            .foregroundStyle(by: .value("Source", SourceStyle.name(item.source)))
                            .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(domain: names.map(SourceStyle.name), range: names.map(SourceStyle.tint))
                    .chartXScale(domain: chartDomain)
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                    .frame(height: 200)
                }
            }
        }
    }

    private var chartDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let start = calendar.date(byAdding: .day, value: -14, to: end) ?? .now
        return start...end
    }

    private var sourceMenu: some View {
        Menu {
            Button("All sources") { source = nil }
            Divider()
            ForEach(sources, id: \.self) { item in
                Button(SourceStyle.name(item)) { source = item }
            }
        } label: {
            Label(source.map(SourceStyle.name) ?? "All sources", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 12.5))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    @ViewBuilder
    private var timeline: some View {
        if results.isEmpty {
            Card {
                EmptyStateView(symbol: query.isEmpty ? "clock" : "magnifyingglass",
                               title: query.isEmpty ? "No activity yet" : "No matches",
                               message: query.isEmpty
                                   ? "Started, finished and alert events are saved here as they happen."
                                   : "Try a different word or source.")
            }
        } else {
            let groups = Dictionary(grouping: results) { Calendar.current.startOfDay(for: $0.timestamp) }
                .sorted { $0.key > $1.key }
            ForEach(groups, id: \.key) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Format.dayTitle(group.key))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    CardList(items: group.value) { EventRow(event: $0) }
                }
            }
        }
    }

    private func load() {
        guard let database = model.store.database else {
            results = model.store.history
            return
        }
        results = database.search(text: query, source: source, limit: 500)
        daily = database.dailyCounts(days: 14)
        sources = database.sources()
    }
}
