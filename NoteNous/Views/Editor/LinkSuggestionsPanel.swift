import SwiftUI
import CoreData

struct LinkSuggestionsPanel: View {
    let note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState

    @State private var suggestions: [LinkSuggestionService.LinkSuggestion] = []
    @State private var dismissedIds: Set<UUID> = []
    @State private var isLoading: Bool = false
    @State private var useAI: Bool = false
    @State private var refreshTask: Task<Void, Never>?

    private let service = LinkSuggestionService()

    var visibleSuggestions: [LinkSuggestionService.LinkSuggestion] {
        suggestions.filter { !dismissedIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 10))
                    .foregroundStyle(Moros.oracle)
                Text("SUGGESTED LINKS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)

                Spacer()

                // Mode toggle
                Picker("", selection: $useAI) {
                    Text("Local").tag(false)
                    Text("AI").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .controlSize(.mini)
                .onChange(of: useAI) { refreshSuggestions() }

                Button(action: refreshSuggestions) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Moros.textDim)
                        .rotationEffect(isLoading ? .degrees(360) : .zero)
                        .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(useAI ? "AI analyzing connections..." : "Scanning notes...")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if visibleSuggestions.isEmpty && !isLoading {
                HStack {
                    Text("No suggestions found")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textGhost)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Suggestion list
            ForEach(visibleSuggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .onAppear { refreshSuggestions() }
        .onChange(of: note.objectID) {
            dismissedIds.removeAll()
            refreshSuggestions()
        }
    }

    // MARK: - Suggestion Row

    private func suggestionRow(_ suggestion: LinkSuggestionService.LinkSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Target note title (clickable)
                Button(action: { appState.selectedNote = suggestion.targetNote }) {
                    Text(suggestion.targetNote.title.isEmpty ? "(untitled)" : suggestion.targetNote.title)
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.oracle)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Spacer()

                // Link type badge
                Text(suggestion.suggestedLinkType.label)
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Moros.limit03)
                    .clipShape(Rectangle())
            }

            // Reason
            Text(suggestion.reason)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
                .lineLimit(2)

            HStack(spacing: 6) {
                // Confidence bar
                confidenceBar(suggestion.confidence)

                Spacer()

                // Link button
                Button(action: { createLink(suggestion) }) {
                    HStack(spacing: 2) {
                        Image(systemName: "link")
                        Text("Link")
                    }
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.verdit)
                }
                .buttonStyle(.plain)

                // Dismiss button
                Button(action: { dismissedIds.insert(suggestion.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(Moros.textGhost)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Moros.limit02.opacity(0.5))
    }

    // MARK: - Confidence Bar

    private func confidenceBar(_ confidence: Float) -> some View {
        HStack(spacing: 2) {
            Text("\(Int(confidence * 100))%")
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textDim)
                .frame(width: 28, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Moros.limit03)
                        .frame(height: 3)
                    Rectangle()
                        .fill(confidenceColor(confidence))
                        .frame(width: geo.size.width * CGFloat(confidence), height: 3)
                }
            }
            .frame(width: 40, height: 3)
        }
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.7 { return Moros.verdit }
        if confidence > 0.4 { return Moros.oracle }
        return Moros.ambient
    }

    // MARK: - Actions

    private func refreshSuggestions() {
        refreshTask?.cancel()
        isLoading = true

        refreshTask = Task {
            if useAI {
                do {
                    let results = try await service.suggestLinksWithAI(for: note, context: context)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        suggestions = results
                        isLoading = false
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        isLoading = false
                    }
                }
            } else {
                let results = service.suggestLinks(for: note, context: context)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    suggestions = results
                    isLoading = false
                }
            }
        }
    }

    private func createLink(_ suggestion: LinkSuggestionService.LinkSuggestion) {
        let linkService = LinkService(context: context)
        linkService.createLink(
            from: note,
            to: suggestion.targetNote,
            type: suggestion.suggestedLinkType,
            context: suggestion.reason,
            strength: suggestion.confidence,
            isAISuggested: true
        )
        // Remove from suggestions after creating
        suggestions.removeAll { $0.id == suggestion.id }
    }
}
