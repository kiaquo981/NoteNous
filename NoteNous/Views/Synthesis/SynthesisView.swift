import SwiftUI
import CoreData
import UniformTypeIdentifiers

/// The EXPRESS phase UI: select notes, arrange, configure, generate, and export.
struct SynthesisView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @State private var step: SynthesisStep = .selectNotes
    @State private var selectedNotes: [NoteEntity] = []
    @State private var searchQuery: String = ""
    @State private var writingStyle: SynthesisService.SynthesisRequest.WritingStyle = .essay
    @State private var lengthTarget: SynthesisService.SynthesisRequest.LengthTarget = .medium
    @State private var customTitle: String = ""
    @State private var result: SynthesisService.SynthesisResult?
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var refineFeedback: String = ""
    @State private var showRefineField: Bool = false
    @State private var draggedNote: NoteEntity?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)],
        predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isArchived == NO"),
            NSPredicate(format: "noteTypeRaw == %d OR noteTypeRaw == %d",
                        NoteType.permanent.rawValue, NoteType.structure.rawValue)
        ]),
        animation: .default
    ) private var availableNotes: FetchedResults<NoteEntity>

    private let synthesisService = SynthesisService()

    enum SynthesisStep: Int, CaseIterable {
        case selectNotes = 0
        case arrange = 1
        case configure = 2
        case generate = 3
        case review = 4

        var label: String {
            switch self {
            case .selectNotes: "Select Notes"
            case .arrange: "Arrange"
            case .configure: "Configure"
            case .generate: "Generate"
            case .review: "Review"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Moros.border).frame(height: 1)
            stepIndicator
            Rectangle().fill(Moros.border).frame(height: 1)

            switch step {
            case .selectNotes: selectNotesStep
            case .arrange: arrangeStep
            case .configure: configureStep
            case .generate: generateStep
            case .review: reviewStep
            }
        }

        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 16) {
            Label("KNOWLEDGE SYNTHESIS", systemImage: "text.book.closed")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Moros.verdit)

            Spacer()

            Text("\(selectedNotes.count) notes selected")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textSub)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Moros.limit01)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(SynthesisStep.allCases, id: \.rawValue) { s in
                let isCurrent = s == step
                let isPast = s.rawValue < step.rawValue

                HStack(spacing: 4) {
                    Circle()
                        .fill(isCurrent ? Moros.oracle : isPast ? Moros.verdit : Moros.limit03)
                        .frame(width: 8, height: 8)

                    Text(s.label.uppercased())
                        .font(Moros.fontMicro)
                        .foregroundStyle(isCurrent ? Moros.oracle : isPast ? Moros.verdit : Moros.textDim)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Moros.limit01)
    }

    // MARK: - Step 1: Select Notes

    private var selectNotesStep: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Moros.textDim)
                TextField("Search permanent notes...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
            }
            .padding(8)
            .background(Moros.limit02, in: Rectangle())
            .padding(.horizontal)
            .padding(.top, 8)

            // Notes list
            List {
                let filtered = filteredNotes
                ForEach(filtered, id: \.objectID) { note in
                    let isSelected = selectedNotes.contains(where: { $0.objectID == note.objectID })

                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isSelected ? Moros.oracle : Moros.textDim)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Moros.textMain)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(note.zettelId ?? "")
                                    .font(Moros.fontMonoSmall)
                                    .foregroundStyle(Moros.oracle)

                                NoteTypeBadge(type: note.noteType)

                                Text("\(note.outgoingLinksArray.count) links")
                                    .font(Moros.fontMonoSmall)
                                    .foregroundStyle(Moros.textDim)
                            }
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSelection(note)
                    }
                    .listRowBackground(isSelected ? Moros.oracle.opacity(0.05) : Moros.limit01)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
    

            // Navigation
            HStack {
                Spacer()
                Button {
                    withAnimation { step = .arrange }
                } label: {
                    HStack {
                        Text("Arrange")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedNotes.count >= 2 ? Moros.oracle : Moros.textDim)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedNotes.count >= 2 ? Moros.oracle.opacity(0.1) : Moros.limit02, in: Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selectedNotes.count < 2)
            }
            .padding()
        }
    }

    // MARK: - Step 2: Arrange

    private var arrangeStep: some View {
        VStack(spacing: 0) {
            Text("Drag to reorder notes. The synthesis will follow this sequence.")
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textSub)
                .padding()

            List {
                ForEach(Array(selectedNotes.enumerated()), id: \.element.objectID) { index, note in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Moros.oracle)
                            .frame(width: 24)

                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Moros.textDim)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Moros.textMain)
                                .lineLimit(1)

                            Text(note.zettelId ?? "")
                                .font(Moros.fontMonoSmall)
                                .foregroundStyle(Moros.textDim)
                        }

                        Spacer()

                        Button {
                            selectedNotes.removeAll { $0.objectID == note.objectID }
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(Moros.signal)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Moros.limit01)
                }
                .onMove { indices, newOffset in
                    selectedNotes.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
    

            // Navigation
            HStack {
                Button {
                    withAnimation { step = .selectNotes }
                } label: {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Moros.textSub)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Moros.limit02, in: Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation { step = .configure }
                } label: {
                    HStack {
                        Text("Configure")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Moros.oracle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Moros.oracle.opacity(0.1), in: Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    // MARK: - Step 3: Configure

    private var configureStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TITLE (optional)")
                            .font(Moros.fontLabel)
                            .foregroundStyle(Moros.textDim)
                        TextField("Auto-generate from content...", text: $customTitle)
                            .textFieldStyle(.plain)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                            .padding(8)
                            .background(Moros.limit02, in: Rectangle())
                    }

                    // Writing style
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WRITING STYLE")
                            .font(Moros.fontLabel)
                            .foregroundStyle(Moros.textDim)

                        ForEach(SynthesisService.SynthesisRequest.WritingStyle.allCases) { style in
                            let isSelected = writingStyle == style
                            Button {
                                writingStyle = style
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(isSelected ? Moros.oracle : Moros.textDim)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(style.rawValue)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Moros.textMain)
                                        Text(style.description)
                                            .font(Moros.fontSmall)
                                            .foregroundStyle(Moros.textDim)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(isSelected ? Moros.oracle.opacity(0.05) : Color.clear, in: Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Length target
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TARGET LENGTH")
                            .font(Moros.fontLabel)
                            .foregroundStyle(Moros.textDim)

                        HStack(spacing: 8) {
                            ForEach(SynthesisService.SynthesisRequest.LengthTarget.allCases) { length in
                                let isSelected = lengthTarget == length
                                Button {
                                    lengthTarget = length
                                } label: {
                                    Text(length.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(isSelected ? Moros.oracle : Moros.textSub)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Moros.oracle.opacity(0.1) : Moros.limit02, in: Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }

            // Navigation
            HStack {
                Button {
                    withAnimation { step = .arrange }
                } label: {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Moros.textSub)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Moros.limit02, in: Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation { step = .generate }
                    startGeneration()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Generate")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Moros.verdit)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Moros.verdit.opacity(0.1), in: Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    // MARK: - Step 4: Generate

    private var generateStep: some View {
        VStack(spacing: 16) {
            if isGenerating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(Moros.oracle)

                Text("Synthesizing \(selectedNotes.count) notes...")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textSub)

                Text("Style: \(writingStyle.rawValue) | Length: \(lengthTarget.rawValue)")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
            } else if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(Moros.signal)

                Text(error)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textSub)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    startGeneration()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Moros.oracle)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Moros.oracle.opacity(0.1), in: Rectangle())
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        VStack(spacing: 0) {
            if let result = result {
                // Result header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(Moros.fontH3)
                            .foregroundStyle(Moros.textMain)
                        Text("\(result.wordCount) words | \(result.outline.count) sections | \(result.sourcedNotes.count) sources")
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.textDim)
                    }
                    Spacer()
                }
                .padding()

                Rectangle().fill(Moros.border).frame(height: 1)

                // Content
                ScrollView {
                    Text(result.content)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(16)
                }

                Rectangle().fill(Moros.border).frame(height: 1)

                // Refine input
                if showRefineField {
                    HStack(spacing: 8) {
                        TextField("Enter feedback for refinement...", text: $refineFeedback)
                            .textFieldStyle(.plain)
                            .font(Moros.fontSmall)
                            .foregroundStyle(Moros.textMain)
                            .padding(6)
                            .background(Moros.limit02, in: Rectangle())

                        Button("Send") {
                            startRefinement()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Moros.oracle)
                        .disabled(refineFeedback.isEmpty || isGenerating)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }

                // Actions
                HStack(spacing: 12) {
                    Button {
                        showRefineField.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Refine")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Moros.oracle)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Moros.oracle.opacity(0.1), in: Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        copyToClipboard(result.content)
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Moros.ambient)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Moros.ambient.opacity(0.1), in: Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        saveAsNote(result)
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save as Note")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Moros.verdit)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Moros.verdit.opacity(0.1), in: Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        exportAsMarkdown(result)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.doc")
                            Text("Export .md")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Moros.textSub)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Moros.limit02, in: Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding()
            }
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ note: NoteEntity) {
        if let index = selectedNotes.firstIndex(where: { $0.objectID == note.objectID }) {
            selectedNotes.remove(at: index)
        } else {
            selectedNotes.append(note)
        }
    }

    private var filteredNotes: [NoteEntity] {
        guard !searchQuery.isEmpty else { return Array(availableNotes) }
        let query = searchQuery.lowercased()
        return availableNotes.filter {
            $0.title.lowercased().contains(query) ||
            $0.contentPlainText.lowercased().contains(query) ||
            ($0.zettelId ?? "").lowercased().contains(query)
        }
    }

    private func startGeneration() {
        isGenerating = true
        errorMessage = nil

        let request = SynthesisService.SynthesisRequest(
            notes: selectedNotes,
            style: writingStyle,
            targetLength: lengthTarget,
            title: customTitle.isEmpty ? nil : customTitle
        )

        Task {
            do {
                let synthesisResult = try await synthesisService.synthesize(request: request, context: context)
                await MainActor.run {
                    self.result = synthesisResult
                    self.isGenerating = false
                    withAnimation { self.step = .review }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }

    private func startRefinement() {
        guard let currentResult = result else { return }
        isGenerating = true

        let request = SynthesisService.SynthesisRequest(
            notes: selectedNotes,
            style: writingStyle,
            targetLength: lengthTarget,
            title: customTitle.isEmpty ? nil : customTitle
        )

        Task {
            do {
                let refined = try await synthesisService.refine(
                    previousResult: currentResult,
                    feedback: refineFeedback,
                    request: request
                )
                await MainActor.run {
                    self.result = refined
                    self.isGenerating = false
                    self.refineFeedback = ""
                    self.showRefineField = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveAsNote(_ result: SynthesisService.SynthesisResult) {
        let noteService = NoteService(context: context)
        let note = noteService.createNote(
            title: result.title,
            content: result.content,
            paraCategory: .resource
        )
        note.noteType = NoteType.structure
        note.codeStage = CODEStage.distilled
        note.updatedAt = Date()
        try? context.save()
        appState.selectedNote = note
    }

    private func exportAsMarkdown(_ result: SynthesisService.SynthesisResult) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "\(result.title).md"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? result.content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
