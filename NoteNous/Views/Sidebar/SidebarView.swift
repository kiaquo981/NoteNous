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

            // New Note Button
            Button(action: createNewNote) {
                Label("New Note", systemImage: "plus.circle.fill")
                    .foregroundStyle(Moros.oracle)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

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
                            }
                        }
                }
            } header: {
                Text("PARA")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Moros.textDim)
            }

            // CODE Pipeline
            Section {
                ForEach(CODEStage.allCases) { stage in
                    SidebarCODERow(stage: stage, isSelected: appState.selectedCODEFilter == stage)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if appState.selectedCODEFilter == stage {
                                appState.selectedCODEFilter = nil
                            } else {
                                appState.selectedCODEFilter = stage
                            }
                        }
                }
            } header: {
                Text("CODE PIPELINE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Moros.textDim)
            }

            // Workflow
            Section {
                NavigationLink(destination: FleetingReviewQueue().environment(\.managedObjectContext, context)) {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full").foregroundStyle(Moros.ambient)
                        Text("Fleeting Queue").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: SourceBrowserView(sourceService: SourceService())) {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical").foregroundStyle(Moros.ambient)
                        Text("Sources").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: IndexBrowserView(indexService: IndexService()).environment(\.managedObjectContext, context)) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle").foregroundStyle(Moros.ambient)
                        Text("Index").foregroundStyle(Moros.textSub)
                    }
                }
                NavigationLink(destination: WorkflowDashboard(sourceService: SourceService(), indexService: IndexService()).environment(\.managedObjectContext, context)) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar").foregroundStyle(Moros.oracle)
                        Text("Dashboard").foregroundStyle(Moros.textSub)
                    }
                }
            } header: {
                Text("WORKFLOW")
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

    private func createNewNote() {
        let service = NoteService(context: context)
        let note = service.createNote()
        appState.selectedNote = note
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
