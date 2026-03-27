import SwiftUI
import CoreData

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TagEntity.usageCount, ascending: false)],
        animation: .default
    ) private var tags: FetchedResults<TagEntity>

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

            // New Zettel Button (opens ZettelCreationSheet)
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
            .padding(.bottom, 8)

            // ZETTELKASTEN Section — tappable filters
            Section {
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
                            // Clear other filters
                            appState.selectedPARAFilter = nil
                            appState.selectedCODEFilter = nil
                        }
                        appState.selectedView = .stack
                    }
                }
            } header: {
                Text("ZETTELKASTEN")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Moros.textDim)
            }

            // PIPELINE Section
            Section {
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
            } header: {
                Text("PIPELINE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Moros.textDim)
            }

            // NOTECARDS (Greene/Holiday)
            Section {
                NavigationLink(destination: SourceBrowserView(sourceService: SourceService())) {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical").foregroundStyle(Moros.ambient)
                        Text("Sources").foregroundStyle(Moros.textSub)
                    }
                }
            } header: {
                Text("NOTECARDS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Moros.textDim)
            }

            // TOOLS
            Section {
                NavigationLink(destination: IndexBrowserView(indexService: IndexService()).environment(\.managedObjectContext, context)) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Moros.ambient)
                        Text("Index").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: WorkflowDashboard(sourceService: SourceService(), indexService: IndexService()).environment(\.managedObjectContext, context)) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar").foregroundStyle(Moros.oracle)
                        Text("Dashboard").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: FleetingReviewQueue().environment(\.managedObjectContext, context).environmentObject(appState)) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Moros.ambient)
                        Text("Processing Queue").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: ProcessingPipeline().environment(\.managedObjectContext, context).environmentObject(appState)) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.arrow.left").foregroundStyle(Moros.oracle)
                        Text("Pipeline").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: AgentDashboard().environment(\.managedObjectContext, context).environmentObject(appState)) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill").foregroundStyle(Moros.oracle)
                        Text("Zettelkasten Agent").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: AIChatView().environment(\.managedObjectContext, context).environmentObject(appState)) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile").foregroundStyle(Moros.oracle)
                        Text("AI Chat").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: VoiceInkDashboard().environment(\.managedObjectContext, context).environmentObject(appState)) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill").foregroundStyle(Moros.oracle)
                        Text("VoiceInk").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: CallNoteListView(callNoteService: CallNoteService()).environment(\.managedObjectContext, context).environmentObject(appState)) {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill").foregroundStyle(Moros.oracle)
                        Text("Call Notes").foregroundStyle(Moros.textSub)
                    }
                }
            } header: {
                Text("TOOLS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Moros.textDim)
            }

            // PARA Section
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
            } header: {
                Text("PARA")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Moros.textDim)
            }

            // Tags
            if !tags.isEmpty {
                Section {
                    ForEach(tags.prefix(15), id: \.objectID) { tag in
                        if let name = tag.name {
                            HStack(spacing: 6) {
                                Image(systemName: "tag").foregroundStyle(Moros.ambient)
                                Text(name).foregroundStyle(Moros.textSub)
                            }
                            .font(Moros.fontSmall)
                        }
                    }
                } header: {
                    Text("TAGS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .textCase(.uppercase)
                        .foregroundStyle(Moros.textDim)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .tint(Moros.oracle)
        .scrollContentBackground(.hidden)
        .morosBackground(Moros.limit01)
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
    }

    private var count: Int {
        let service = NoteService(context: context)
        return service.countNotes(noteType: noteType)
    }
}
