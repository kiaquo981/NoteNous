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
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 4)

            // New Note Button
            Button(action: createNewNote) {
                Label("New Note", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            // PARA Section
            Section("PARA") {
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
            }

            // CODE Pipeline
            Section("CODE Pipeline") {
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
            }

            // Workflow
            Section("Workflow") {
                NavigationLink(destination: FleetingReviewQueue().environment(\.managedObjectContext, context)) {
                    Label("Fleeting Queue", systemImage: "tray.full")
                }
                NavigationLink(destination: SourceBrowserView(sourceService: SourceService())) {
                    Label("Sources", systemImage: "books.vertical")
                }
                NavigationLink(destination: IndexBrowserView(indexService: IndexService()).environment(\.managedObjectContext, context)) {
                    Label("Index", systemImage: "list.bullet.rectangle")
                }
                NavigationLink(destination: WorkflowDashboard(sourceService: SourceService(), indexService: IndexService()).environment(\.managedObjectContext, context)) {
                    Label("Dashboard", systemImage: "chart.bar")
                }
            }

            // Tags
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags.prefix(15), id: \.objectID) { tag in
                        if let name = tag.name {
                            Label(name, systemImage: "tag")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
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
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 20)
            Text(category.label)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isSelected ? .white : .primary)
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
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 20)
            Text(stage.label)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isSelected ? .white : .primary)
    }

    private var count: Int {
        let service = NoteService(context: context)
        return service.countNotes(codeStage: stage)
    }
}
