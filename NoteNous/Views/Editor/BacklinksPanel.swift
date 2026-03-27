import SwiftUI
import CoreData

struct BacklinksPanel: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState

    @State private var isExpanded = true
    @State private var confirmedLinks: [NoteLinkEntity] = []
    @State private var suggestedLinks: [NoteLinkEntity] = []
    @State private var unlinkedMentions: [NoteEntity] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if isExpanded {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !confirmedLinks.isEmpty {
                            confirmedLinksSection
                        }

                        if !suggestedLinks.isEmpty {
                            suggestedLinksSection
                        }

                        if !unlinkedMentions.isEmpty {
                            unlinkedMentionsSection
                        }

                        if confirmedLinks.isEmpty && suggestedLinks.isEmpty && unlinkedMentions.isEmpty {
                            emptyState
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 300)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { loadBacklinks() }
        .onChange(of: note.objectID) { loadBacklinks() }
    }

    // MARK: - Header

    private var headerView: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                Text("Backlinks")
                    .font(.headline)

                let totalCount = confirmedLinks.count + suggestedLinks.count + unlinkedMentions.count
                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirmed Links Section

    private var confirmedLinksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Confirmed", count: confirmedLinks.count, icon: "checkmark.circle.fill", color: .green)

            ForEach(confirmedLinks, id: \.objectID) { link in
                BacklinkRow(
                    link: link,
                    isSourceView: false,
                    onNavigate: { navigateToSource(of: link) }
                )
            }
        }
    }

    // MARK: - Suggested Links Section

    private var suggestedLinksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("AI Suggested", count: suggestedLinks.count, icon: "brain", color: .purple)

            ForEach(suggestedLinks, id: \.objectID) { link in
                HStack {
                    BacklinkRow(
                        link: link,
                        isSourceView: false,
                        onNavigate: { navigateToSource(of: link) }
                    )

                    Spacer()

                    Button {
                        confirmLink(link)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Confirm this link")

                    Button {
                        rejectLink(link)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Reject this link")
                }
            }
        }
    }

    // MARK: - Unlinked Mentions Section

    private var unlinkedMentionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Unlinked Mentions", count: unlinkedMentions.count, icon: "text.magnifyingglass", color: .orange)

            ForEach(unlinkedMentions, id: \.objectID) { mentioningNote in
                Button {
                    appState.selectedNote = mentioningNote
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mentioningNote.title.isEmpty ? "Untitled" : mentioningNote.title)
                                .font(.callout)
                                .lineLimit(1)

                            if let zettelId = mentioningNote.zettelId {
                                Text(zettelId)
                                    .font(.caption2)
                                    .monospaced()
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(.quaternary)
            Text("No backlinks yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Other notes linking to this note will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.medium))
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadBacklinks() {
        let linkService = LinkService(context: context)
        confirmedLinks = linkService.backlinks(for: note)
        suggestedLinks = linkService.suggestedLinks(for: note)

        let parser = WikilinkParser(context: context)
        unlinkedMentions = parser.unlinkedMentions(for: note)
    }

    private func navigateToSource(of link: NoteLinkEntity) {
        guard let sourceNote = link.sourceNote else { return }
        appState.selectedNote = sourceNote
    }

    private func confirmLink(_ link: NoteLinkEntity) {
        let linkService = LinkService(context: context)
        linkService.confirmLink(link)
        loadBacklinks()
    }

    private func rejectLink(_ link: NoteLinkEntity) {
        let linkService = LinkService(context: context)
        linkService.rejectLink(link)
        loadBacklinks()
    }
}

// MARK: - BacklinkRow

struct BacklinkRow: View {
    let link: NoteLinkEntity
    let isSourceView: Bool
    var onNavigate: () -> Void

    private var displayNote: NoteEntity? {
        isSourceView ? link.targetNote : link.sourceNote
    }

    var body: some View {
        Button(action: onNavigate) {
            HStack(spacing: 8) {
                LinkTypeBadge(type: link.linkType)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayNote?.title.isEmpty == false ? displayNote!.title : "Untitled")
                        .font(.callout)
                        .lineLimit(1)

                    if let ctx = link.context, !ctx.isEmpty {
                        Text(ctx)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                StrengthIndicator(strength: link.strength)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LinkTypeBadge

struct LinkTypeBadge: View {
    let type: LinkType

    var body: some View {
        Text(type.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch type {
        case .reference: .gray.opacity(0.15)
        case .supports: .green.opacity(0.15)
        case .contradicts: .red.opacity(0.15)
        case .extends: .blue.opacity(0.15)
        case .example: .purple.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch type {
        case .reference: .gray
        case .supports: .green
        case .contradicts: .red
        case .extends: .blue
        case .example: .purple
        }
    }
}

// MARK: - StrengthIndicator

struct StrengthIndicator: View {
    let strength: Float

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index < filledDots ? .primary : .quaternary)
                    .frame(width: 4, height: 4)
            }
        }
        .help("Strength: \(Int(strength * 100))%")
    }

    private var filledDots: Int {
        Int((strength * 5).rounded())
    }
}
