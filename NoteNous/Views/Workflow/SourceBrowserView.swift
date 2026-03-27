import SwiftUI

/// Browse and manage all sources (books, articles, videos, etc.).
/// Implements Ryan Holiday's card system with waiting period tracking.
struct SourceBrowserView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var sourceService: SourceService

    @State private var sortOrder: SortOrder = .dateConsumed
    @State private var showAddSheet = false
    @State private var selectedSource: Source?
    @State private var showDetailSheet = false
    @State private var searchText = ""

    enum SortOrder: String, CaseIterable {
        case dateConsumed = "Date Consumed"
        case cardsGenerated = "Cards Generated"
        case waitingPeriod = "Waiting Period"
        case title = "Title"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            if sourceService.sources.isEmpty {
                emptyState
            } else {
                sourceList
            }
        }
        .sheet(isPresented: $showAddSheet) {
            SourceDetailSheet(sourceService: sourceService, source: nil)
        }
        .sheet(isPresented: $showDetailSheet) {
            if let source = selectedSource {
                SourceDetailSheet(sourceService: sourceService, source: source)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            TextField("Search sources...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)

            Spacer()

            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 180)

            Button {
                showAddSheet = true
            } label: {
                Label("Add Source", systemImage: "plus")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Source List

    private var sourceList: some View {
        List {
            // Header
            HStack {
                Text("Title")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Author")
                    .frame(width: 120, alignment: .leading)
                Text("Type")
                    .frame(width: 80)
                Text("Consumed")
                    .frame(width: 100)
                Text("Cards")
                    .frame(width: 50)
                Text("Status")
                    .frame(width: 100)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)

            ForEach(sortedAndFilteredSources) { source in
                SourceRow(source: source)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSource = source
                        showDetailSheet = true
                    }
                    .contextMenu {
                        Button("Edit") {
                            selectedSource = source
                            showDetailSheet = true
                        }
                        if source.dateCarded == nil && source.dateConsumed != nil {
                            Button("Start Carding") {
                                sourceService.startCarding(id: source.id)
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            sourceService.deleteSource(id: source.id)
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Sources Yet")
                .font(.title2.weight(.semibold))
            Text("Add books, articles, and videos you consume.\nTrack the waiting period before making cards.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add First Source") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed

    private var sortedAndFilteredSources: [Source] {
        var result = sourceService.sources

        // Filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                ($0.author?.lowercased().contains(query) ?? false)
            }
        }

        // Sort
        switch sortOrder {
        case .dateConsumed:
            result.sort { ($0.dateConsumed ?? .distantPast) > ($1.dateConsumed ?? .distantPast) }
        case .cardsGenerated:
            result.sort { $0.cardsGenerated > $1.cardsGenerated }
        case .waitingPeriod:
            result.sort { ($0.waitingPeriodDays ?? -1) > ($1.waitingPeriodDays ?? -1) }
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        }

        return result
    }
}

// MARK: - Source Row

struct SourceRow: View {
    let source: Source

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: source.sourceType.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(source.title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(source.author ?? "-")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            Text(source.sourceType.label)
                .font(.caption)
                .frame(width: 80)

            Group {
                if let date = source.dateConsumed {
                    Text(date, style: .date)
                } else {
                    Text("-")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 100)

            Text("\(source.cardsGenerated)")
                .font(.callout.monospacedDigit())
                .frame(width: 50)

            statusBadge
                .frame(width: 100)
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        let status = source.waitingStatus
        return HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(statusLabel(status))
                .font(.caption)
        }
    }

    private func statusColor(_ status: Source.WaitingStatus) -> Color {
        switch status {
        case .notConsumed: return .gray
        case .waiting: return .yellow
        case .readyToCard: return .green
        case .carded: return .blue
        }
    }

    private func statusLabel(_ status: Source.WaitingStatus) -> String {
        switch status {
        case .notConsumed: return "Not Read"
        case .waiting:
            if let days = source.waitingPeriodDays {
                return "Wait \(14 - days)d"
            }
            return "Waiting"
        case .readyToCard: return "Ready"
        case .carded: return "Carded"
        }
    }
}
