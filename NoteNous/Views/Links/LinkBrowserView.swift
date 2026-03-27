import SwiftUI
import CoreData

struct LinkBrowserView: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState

    @State private var outgoingLinks: [NoteLinkEntity] = []
    @State private var incomingLinks: [NoteLinkEntity] = []
    @State private var suggestedLinks: [NoteLinkEntity] = []
    @State private var showLinkCreation = false
    @State private var linkToDelete: NoteLinkEntity?
    @State private var showDeleteConfirmation = false
    @State private var selectedSection: BrowserSection = .outgoing

    enum BrowserSection: String, CaseIterable {
        case outgoing = "Outgoing"
        case incoming = "Incoming"
        case suggested = "AI Suggested"

        var icon: String {
            switch self {
            case .outgoing: "arrow.up.right"
            case .incoming: "arrow.down.left"
            case .suggested: "brain"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            sectionPicker
            Divider()
            linksList
        }
        .onAppear { loadLinks() }
        .onChange(of: note.objectID) { loadLinks() }
        .sheet(isPresented: $showLinkCreation) {
            LinkCreationSheet(sourceNote: note)
                .environment(\.managedObjectContext, context)
                .onDisappear { loadLinks() }
        }
        .alert("Delete Link?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { linkToDelete = nil }
            Button("Delete", role: .destructive) { performDelete() }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Links")
                    .font(.headline)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showLinkCreation = true
            } label: {
                Label("New Link", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(BrowserSection.allCases, id: \.self) { section in
                let count = countFor(section)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: section.icon)
                        Text(section.rawValue)
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(selectedSection == section ? Color.accentColor.opacity(0.1) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Links List

    @ViewBuilder
    private var linksList: some View {
        let links = linksForSection(selectedSection)

        if links.isEmpty {
            emptySection
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(links, id: \.objectID) { link in
                        LinkBrowserRow(
                            link: link,
                            isOutgoing: selectedSection == .outgoing,
                            isSuggested: selectedSection == .suggested,
                            onNavigate: { navigateTo(link: link) },
                            onDelete: { requestDelete(link) },
                            onChangeType: { newType in changeType(link, to: newType) },
                            onConfirm: { confirmLink(link) },
                            onReject: { rejectLink(link) }
                        )

                        Divider()
                            .padding(.leading, 40)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptySection: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedSection.icon)
                .font(.title)
                .foregroundStyle(.quaternary)
            Text("No \(selectedSection.rawValue.lowercased()) links")
                .font(.callout)
                .foregroundStyle(.secondary)

            if selectedSection == .outgoing {
                Button("Create Link") {
                    showLinkCreation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private func countFor(_ section: BrowserSection) -> Int {
        switch section {
        case .outgoing: outgoingLinks.count
        case .incoming: incomingLinks.count
        case .suggested: suggestedLinks.count
        }
    }

    private func linksForSection(_ section: BrowserSection) -> [NoteLinkEntity] {
        switch section {
        case .outgoing: outgoingLinks
        case .incoming: incomingLinks
        case .suggested: suggestedLinks
        }
    }

    private func loadLinks() {
        let linkService = LinkService(context: context)
        outgoingLinks = note.outgoingLinksArray.filter { $0.isConfirmed }
        incomingLinks = linkService.backlinks(for: note)
        suggestedLinks = linkService.suggestedLinks(for: note)
    }

    private func navigateTo(link: NoteLinkEntity) {
        let target = selectedSection == .outgoing ? link.targetNote : link.sourceNote
        if let target {
            appState.selectedNote = target
        }
    }

    private func requestDelete(_ link: NoteLinkEntity) {
        linkToDelete = link
        showDeleteConfirmation = true
    }

    private func performDelete() {
        guard let link = linkToDelete else { return }
        context.delete(link)
        try? context.save()
        linkToDelete = nil
        loadLinks()
    }

    private func changeType(_ link: NoteLinkEntity, to newType: LinkType) {
        link.linkType = newType
        try? context.save()
        loadLinks()
    }

    private func confirmLink(_ link: NoteLinkEntity) {
        let linkService = LinkService(context: context)
        linkService.confirmLink(link)
        loadLinks()
    }

    private func rejectLink(_ link: NoteLinkEntity) {
        let linkService = LinkService(context: context)
        linkService.rejectLink(link)
        loadLinks()
    }
}

// MARK: - LinkBrowserRow

struct LinkBrowserRow: View {
    let link: NoteLinkEntity
    let isOutgoing: Bool
    let isSuggested: Bool
    var onNavigate: () -> Void
    var onDelete: () -> Void
    var onChangeType: (LinkType) -> Void
    var onConfirm: () -> Void
    var onReject: () -> Void

    @State private var isHovered = false

    private var displayNote: NoteEntity? {
        isOutgoing ? link.targetNote : link.sourceNote
    }

    var body: some View {
        HStack(spacing: 10) {
            // Direction indicator
            Image(systemName: isOutgoing ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                .foregroundStyle(isOutgoing ? .blue : .green)

            // Note info
            Button(action: onNavigate) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayNote?.title.isEmpty == false ? displayNote!.title : "Untitled")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let zettelId = displayNote?.zettelId {
                            Text(zettelId)
                                .font(.caption2)
                                .monospaced()
                                .foregroundStyle(.tertiary)
                        }

                        if let ctx = link.context, !ctx.isEmpty {
                            Text(ctx)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Link type picker
            if !isSuggested {
                Menu {
                    ForEach(LinkType.allCases) { type in
                        Button {
                            onChangeType(type)
                        } label: {
                            HStack {
                                Text(type.label)
                                if link.linkType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    LinkTypeBadge(type: link.linkType)
                }

                StrengthIndicator(strength: link.strength)
            }

            // Actions
            if isSuggested {
                HStack(spacing: 6) {
                    Button(action: onConfirm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Confirm link")

                    Button(action: onReject) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Reject link")
                }
            } else if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete link")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
