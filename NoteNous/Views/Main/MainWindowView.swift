import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ViewRouter()
        } detail: {
            HStack(spacing: 0) {
                if let note = appState.selectedNote {
                    NoteEditorView(note: note)
                } else {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No Note Selected",
                        subtitle: "Select a note or press \u{2318}N to create one"
                    )
                }

                if appState.isAIChatVisible {
                    Rectangle()
                        .fill(Moros.border)
                        .frame(width: 1)
                        .transition(.opacity)
                    AIChatSidePanel()
                        .transition(.morosSlideIn)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(Moros.oracle, lineWidth: 3)
                    .background(Moros.oracle.opacity(0.05))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.plainText, .url, .fileURL, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(isPresented: $appState.isCommandPaletteVisible) {
            CommandPaletteView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
        }
        .overlay {
            if appState.isQuickSwitcherVisible {
                QuickSwitcherView()
                    .environmentObject(appState)
                    .environment(\.managedObjectContext, context)
                    .transition(.morosScale)
            }
        }
        .animation(.morosPanel, value: appState.isQuickSwitcherVisible)
        .animation(.morosPanel, value: appState.isAIChatVisible)
        .sheet(isPresented: $appState.isZettelCreationVisible) {
            ZettelCreationSheet()
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
        }
        .sheet(item: $appState.activeToolView) { tool in
            toolView(for: tool)
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
                .morosTheme()
                .frame(minWidth: 700, minHeight: 500)
        }

    }

    // MARK: - Tool Views

    @ViewBuilder
    func toolView(for tool: AppState.ToolView) -> some View {
        switch tool {
        case .sources:
            SourceBrowserView(sourceService: SourceService())
        case .readyToCard:
            SourcesDuePanel(sourceService: SourceService())
        case .cardView:
            EmptyView() // Card view switches ViewMode instead
        case .index:
            IndexBrowserView(indexService: IndexService())
        case .dashboard:
            WorkflowDashboard(sourceService: SourceService(), indexService: IndexService())
        case .processingQueue:
            FleetingReviewQueue()
        case .pipeline:
            ProcessingPipeline()
        case .zettelkastenAgent:
            AgentDashboard()
        case .aiChat:
            AIChatView()
        case .voiceInk:
            VoiceInkDashboard()
        case .callNotes:
            CallNoteListView(callNoteService: CallNoteService())
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // File URLs (.txt, .md)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "txt" || ext == "md" else { return }
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                    let title = url.deletingPathExtension().lastPathComponent
                    Task { @MainActor in
                        createDroppedNote(title: title, content: content)
                    }
                }
            }
            // Plain text or URL strings
            else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    guard let text = data as? String ?? (data as? Data).flatMap({ String(data: $0, encoding: .utf8) }) else { return }
                    Task { @MainActor in
                        createDroppedNote(title: "", content: text)
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    Task { @MainActor in
                        createDroppedNote(title: url.host ?? "Link", content: url.absoluteString)
                    }
                }
            }
        }
    }

    @MainActor
    private func createDroppedNote(title: String, content: String) {
        let service = NoteService(context: context)
        let note = service.createNote(title: title, content: content)
        appState.selectedNote = note
    }
}
