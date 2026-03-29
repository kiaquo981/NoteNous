import SwiftUI

struct CallNoteListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.moros) private var moros

    @ObservedObject var callNoteService: CallNoteService

    @State private var filter: CallNoteFilter = .all
    @State private var selectedCallNoteId: UUID?
    @State private var showNewCallNote: Bool = false

    enum CallNoteFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case processed = "Processed"
    }

    private var filteredNotes: [CallNoteService.CallNote] {
        switch filter {
        case .all: return callNoteService.allCallNotes()
        case .pending: return callNoteService.pendingCallNotes()
        case .processed: return callNoteService.callNotes.filter { $0.isProcessed }.sorted { $0.date > $1.date }
        }
    }

    private var pendingCount: Int {
        callNoteService.pendingCallNotes().count
    }

    private var totalInsights: Int {
        callNoteService.callNotes.filter { $0.isProcessed }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Moros.spacing8) {
                HStack {
                    Text("Call Notes")
                        .font(Moros.fontH2)
                        .foregroundStyle(moros.textMain)

                    Spacer()

                    Button {
                        showNewCallNote = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New Call")
                        }
                        .font(Moros.fontSmall)
                        .foregroundStyle(moros.oracle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(moros.oracle.opacity(0.15), in: Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Stats
                HStack(spacing: Moros.spacing16) {
                    statBadge(
                        label: "Total",
                        value: "\(callNoteService.callNotes.count)",
                        color: moros.textSub
                    )
                    statBadge(
                        label: "Pending",
                        value: "\(pendingCount)",
                        color: pendingCount > 0 ? Moros.signal : moros.textDim
                    )
                    statBadge(
                        label: "Processed",
                        value: "\(totalInsights)",
                        color: moros.verdit
                    )
                }

                // Filter
                Picker("Filter", selection: $filter) {
                    ForEach(CallNoteFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            .padding(Moros.spacing16)


            Divider().background(moros.border)

            // List
            if filteredNotes.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredNotes) { callNote in
                        CallNoteRow(callNote: callNote, moros: moros)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCallNoteId = callNote.id
                            }
                            .listRowBackground(moros.limit01)
                            .listRowSeparatorTint(moros.border)
                    }
                    .onDelete(perform: deleteNotes)
                }
                .listStyle(.plain)
        

            }
        }

        .sheet(isPresented: $showNewCallNote) {
            CallNoteSheet(callNoteService: callNoteService, callNoteId: nil)
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
                .morosTheme()
                .frame(minWidth: 600, minHeight: 500)
        }
        .sheet(item: $selectedCallNoteId) { noteId in
            CallNoteSheet(callNoteService: callNoteService, callNoteId: noteId)
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
                .morosTheme()
                .frame(minWidth: 600, minHeight: 500)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Moros.spacing12) {
            Spacer()
            Image(systemName: "phone.fill")
                .font(.system(size: 40))
                .foregroundStyle(moros.textGhost)
            Text("No call notes yet")
                .font(Moros.fontSubhead)
                .foregroundStyle(moros.textDim)
            Text("Start a new call note to capture meeting insights")
                .font(Moros.fontSmall)
                .foregroundStyle(moros.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Moros.fontH3)
                .foregroundStyle(color)
            Text(label)
                .font(Moros.fontCaption)
                .foregroundStyle(moros.textDim)
        }
    }

    private func deleteNotes(at offsets: IndexSet) {
        let notes = filteredNotes
        for index in offsets {
            callNoteService.deleteCallNote(id: notes[index].id)
        }
    }
}

// MARK: - UUID + Identifiable for sheet binding

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Row

struct CallNoteRow: View {
    let callNote: CallNoteService.CallNote
    let moros: MorosAdaptive

    var body: some View {
        HStack(spacing: Moros.spacing12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(callNote.topic)
                    .font(Moros.fontBody)
                    .foregroundStyle(moros.textMain)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(callNote.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Moros.fontCaption)
                        .foregroundStyle(moros.textDim)

                    if !callNote.participants.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2")
                                .font(Moros.fontCaption)
                            Text("\(callNote.participants.count)")
                                .font(Moros.fontCaption)
                        }
                        .foregroundStyle(moros.textDim)
                    }

                    if let duration = callNote.duration {
                        Text("\(Int(duration))m")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(moros.textDim)
                    }
                }
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if callNote.isProcessed { return moros.verdit }
        if !callNote.annotations.isEmpty { return Moros.signal }
        return moros.textGhost
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(Moros.fontMicro)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.12), in: Rectangle())
    }

    private var statusLabel: String {
        if callNote.isProcessed { return "PROCESSED" }
        if !callNote.annotations.isEmpty { return "PENDING" }
        return "LIVE"
    }
}
