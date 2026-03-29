import SwiftUI
import CoreData

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @StateObject private var sidebarSourceService = SourceService()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TagEntity.usageCount, ascending: false)],
        animation: .default
    ) private var tags: FetchedResults<TagEntity>

    // Persisted collapsed/expanded state — TYPE, PIPELINE, TOOLS, TAGS start collapsed
    @AppStorage("sidebarTypeExpanded") private var typeExpanded = false
    @AppStorage("sidebarPipelineExpanded") private var pipelineExpanded = false
    @AppStorage("sidebarToolsExpanded") private var toolsExpanded = false
    @AppStorage("sidebarTagsExpanded") private var tagsExpanded = false

    var body: some View {
        List {
            // Search
            TextField("Search...", text: $appState.searchQuery)
                .textFieldStyle(.plain)
                .padding(6)
                .background(Moros.limit02, in: Rectangle())
                .foregroundStyle(Moros.textMain)
                .padding(.bottom, 4)

            // Daily Note Button
            DailyNoteButton()
                .padding(.bottom, 4)

            // New Zettel Button
            Button(action: { appState.isZettelCreationVisible = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Moros.oracle)
                    Text("New Zettel")
                        .foregroundStyle(Moros.oracle)
                }
            }
            .buttonStyle(.plain)
            .pressEffect()
            .padding(.bottom, 8)

            // ── NOTES (PARA) ── Primary section, always expanded
            Section {
                ForEach(PARACategory.allCases) { category in
                    SidebarPARARow(category: category, isSelected: appState.selectedPARAFilter == category)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if appState.selectedPARAFilter == category {
                                appState.selectedPARAFilter = nil
                            } else {
                                appState.selectedPARAFilter = category
                                appState.selectedNoteTypeFilter = nil
                                appState.selectedCODEFilter = nil
                            }
                            appState.selectedView = .stack
                        }
                }

                // All Notes — clears all filters
                Button(action: {
                    appState.selectedPARAFilter = nil
                    appState.selectedNoteTypeFilter = nil
                    appState.selectedCODEFilter = nil
                    appState.selectedView = .stack
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(Moros.textDim)
                            .frame(width: 20)
                        Text("All Notes")
                            .foregroundStyle(Moros.textSub)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .pressEffect()
            } header: {
                sectionHeader("NOTES")
            }

            // ▸ TYPE — collapsible, starts collapsed
            CollapsibleSection(title: "TYPE", isExpanded: $typeExpanded) {
                ForEach([NoteType.fleeting, .literature, .permanent, .structure], id: \.self) { type in
                    let config: (icon: String, label: String, color: Color) = {
                        switch type {
                        case .fleeting: return ("bolt.fill", "Fleeting", Moros.ambient)
                        case .literature: return ("book.fill", "Literature", Moros.oracle)
                        case .permanent: return ("diamond.fill", "Permanent", Moros.verdit)
                        case .structure: return ("folder.fill", "Structure", Moros.textSub)
                        }
                    }()
                    SidebarNoteTypeRow(
                        noteType: type,
                        icon: config.icon,
                        label: config.label,
                        color: config.color,
                        isSelected: appState.selectedNoteTypeFilter == type
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if appState.selectedNoteTypeFilter == type {
                            appState.selectedNoteTypeFilter = nil
                        } else {
                            appState.selectedNoteTypeFilter = type
                            appState.selectedPARAFilter = nil
                            appState.selectedCODEFilter = nil
                        }
                        appState.selectedView = .stack
                    }
                }
            } collapsedSummary: {
                TypeCollapsedSummary()
            }

            // ▸ PIPELINE — collapsible, starts collapsed
            CollapsibleSection(title: "PIPELINE", isExpanded: $pipelineExpanded) {
                ForEach(CODEStage.allCases) { stage in
                    SidebarCODERow(stage: stage, isSelected: appState.selectedCODEFilter == stage)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if appState.selectedCODEFilter == stage {
                                appState.selectedCODEFilter = nil
                            } else {
                                appState.selectedCODEFilter = stage
                                appState.selectedNoteTypeFilter = nil
                                appState.selectedPARAFilter = nil
                            }
                            appState.selectedView = .stack
                        }
                }
            } collapsedSummary: {
                PipelineCollapsedSummary()
            }

            // ▸ TOOLS — collapsible, starts collapsed
            CollapsibleSection(title: "TOOLS", isExpanded: $toolsExpanded) {
                SidebarToolButton(icon: "chart.bar", label: "Dashboard", color: Moros.oracle) {
                    appState.activeToolView = .dashboard
                }
                SidebarToolButton(icon: "cpu.fill", label: "Agent", color: Moros.oracle) {
                    appState.activeToolView = .zettelkastenAgent
                }
                SidebarToolButton(icon: "brain.head.profile", label: "AI Chat", color: Moros.oracle) {
                    appState.activeToolView = .aiChat
                }
                SidebarToolButton(icon: "phone.fill", label: "Call Notes", color: Moros.oracle) {
                    appState.activeToolView = .callNotes
                }
                SidebarToolButton(icon: "mic.fill", label: "VoiceInk", color: Moros.oracle) {
                    appState.activeToolView = .voiceInk
                }
                SidebarToolButton(icon: "books.vertical", label: "Sources", color: Moros.ambient) {
                    appState.activeToolView = .sources
                }
                SidebarToolButton(icon: "magnifyingglass", label: "Index", color: Moros.ambient) {
                    appState.activeToolView = .index
                }
                SidebarToolButton(icon: "clock.arrow.circlepath", label: "Queue", color: Moros.ambient) {
                    appState.activeToolView = .processingQueue
                }
                SidebarToolButton(icon: "arrow.right.arrow.left", label: "Pipeline", color: Moros.oracle) {
                    appState.activeToolView = .pipeline
                }
                SidebarToolButton(icon: "book.closed.circle.fill", label: "Ready to Card", color: Moros.oracle) {
                    appState.activeToolView = .readyToCard
                }
                SidebarToolButton(icon: "rectangle.grid.2x2", label: "Card View", color: Moros.oracle) {
                    appState.selectedView = .cards
                    appState.activeToolView = nil
                }
            }

            // ▸ TAGS — collapsible, starts collapsed
            if !tags.isEmpty {
                CollapsibleSection(title: "TAGS", isExpanded: $tagsExpanded) {
                    ForEach(tags.prefix(15), id: \.objectID) { tag in
                        if let name = tag.name {
                            HStack(spacing: 6) {
                                Image(systemName: "tag").foregroundStyle(Moros.ambient)
                                Text(name).foregroundStyle(Moros.textSub)
                            }
                            .font(Moros.fontSmall)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .tint(Moros.oracle)
        .accentColor(Color(red: 0.267, green: 0.467, blue: 0.800))
        .scrollContentBackground(.hidden)
        .morosBackground(Moros.limit01)
        .animation(.morosSnap, value: appState.selectedPARAFilter)
        .animation(.morosSnap, value: appState.selectedNoteTypeFilter)
        .animation(.morosSnap, value: appState.selectedCODEFilter)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(Moros.textDim)
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View, Summary: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let collapsedSummary: Summary

    init(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder collapsedSummary: () -> Summary
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
        self.collapsedSummary = collapsedSummary()
    }

    var body: some View {
        Section {
            if isExpanded {
                content
            }
        } header: {
            Button(action: {
                withAnimation(.morosSnap) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Moros.textDim)
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .textCase(.uppercase)
                        .foregroundStyle(Moros.textDim)
                    if !isExpanded {
                        Spacer()
                        collapsedSummary
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

extension CollapsibleSection where Summary == EmptyView {
    init(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, isExpanded: isExpanded, content: content, collapsedSummary: { EmptyView() })
    }
}

// MARK: - Sidebar Tool Button

struct SidebarToolButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(label).foregroundStyle(Moros.textSub)
            }
        }
        .buttonStyle(.plain)
        .pressEffect()
    }
}

// MARK: - Sidebar Rows

struct SidebarPARARow: View {
    let category: PARACategory
    let isSelected: Bool
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundStyle(isSelected ? Moros.void : Moros.textSub)
                .frame(width: 20)
            Text(category.label)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Moros.limit03, in: Rectangle())
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? Moros.oracle : .clear, in: Rectangle())
        .foregroundStyle(isSelected ? Moros.void : Moros.textMain)
        .animation(.morosSnap, value: isSelected)
    }

    private var count: Int {
        let service = NoteService(context: context)
        return service.countNotes(para: category)
    }
}

struct SidebarCODERow: View {
    let stage: CODEStage
    let isSelected: Bool
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack {
            Image(systemName: stage.icon)
                .foregroundStyle(isSelected ? Moros.void : Moros.textSub)
                .frame(width: 20)
            Text(stage.label)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Moros.limit03, in: Rectangle())
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? Moros.oracle : .clear, in: Rectangle())
        .foregroundStyle(isSelected ? Moros.void : Moros.textMain)
        .animation(.morosSnap, value: isSelected)
    }

    private var count: Int {
        let service = NoteService(context: context)
        return service.countNotes(codeStage: stage)
    }
}

// MARK: - Zettelkasten Note Type Row

struct SidebarNoteTypeRow: View {
    let noteType: NoteType
    let icon: String
    let label: String
    let color: Color
    var isSelected: Bool = false
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? .white : color)
                .frame(width: 16)
            Text(label)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : Moros.textSub)
            Spacer()
            Text("\(count)")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(isSelected ? .white.opacity(0.7) : Moros.textDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? color.opacity(0.3) : Moros.limit03, in: Rectangle())
        }
        .font(Moros.fontSmall)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? color.opacity(0.2) : .clear, in: Rectangle())
        .animation(.morosSnap, value: isSelected)
    }

    private var count: Int {
        let service = NoteService(context: context)
        return service.countNotes(noteType: noteType)
    }
}

// MARK: - Collapsed Summary Views

struct TypeCollapsedSummary: View {
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(spacing: 6) {
            summaryItem(icon: "bolt.fill", type: .fleeting)
            summaryItem(icon: "book.fill", type: .literature)
            summaryItem(icon: "diamond.fill", type: .permanent)
            summaryItem(icon: "folder.fill", type: .structure)
        }
        .foregroundStyle(Moros.textDim)
    }

    private func summaryItem(icon: String, type: NoteType) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 8))
            Text("\(NoteService(context: context).countNotes(noteType: type))")
                .font(.system(size: 9, design: .monospaced))
        }
    }
}

struct PipelineCollapsedSummary: View {
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(spacing: 6) {
            summaryItem(icon: "square.and.arrow.down", stage: .captured)
            summaryItem(icon: "folder.badge.gearshape", stage: .organized)
            summaryItem(icon: "text.badge.star", stage: .distilled)
            summaryItem(icon: "paperplane", stage: .expressed)
        }
        .foregroundStyle(Moros.textDim)
    }

    private func summaryItem(icon: String, stage: CODEStage) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 8))
            Text("\(NoteService(context: context).countNotes(codeStage: stage))")
                .font(.system(size: 9, design: .monospaced))
        }
    }
}
