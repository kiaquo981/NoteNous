import SwiftUI
import CoreData

struct AIChatSidePanel: View {
    @StateObject private var chatService = ChatService()
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Compact header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(Moros.oracle)
                Text("AI")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)
                Spacer()
                if !chatService.messages.isEmpty {
                    Button(action: { chatService.clearChat() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(Moros.textDim)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: { appState.isAIChatVisible = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Moros.spacing8)
            .padding(.vertical, 6)
            .background(Moros.limit02)

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Moros.spacing8) {
                        if chatService.messages.isEmpty {
                            compactEmptyState
                        }

                        ForEach(chatService.messages) { message in
                            compactBubble(for: message)
                                .id(message.id)
                        }

                        if chatService.isStreaming {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                if let status = chatService.statusMessage {
                                    Text(status)
                                        .font(Moros.fontCaption)
                                        .foregroundStyle(Moros.textDim)
                                }
                            }
                            .padding(.horizontal, Moros.spacing8)
                        }
                    }
                    .padding(Moros.spacing8)
                }
                .onChange(of: chatService.messages.count) {
                    if let lastId = chatService.messages.last?.id {
                        withAnimation(.easeOut(duration: Moros.animFast)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Compact input
            HStack(spacing: 6) {
                TextField("Ask...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textMain)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(inputText.isEmpty || chatService.isStreaming ? Moros.textDim : Moros.oracle)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || chatService.isStreaming)
            }
            .padding(.horizontal, Moros.spacing8)
            .padding(.vertical, 6)
            .background(Moros.limit02)
        }
        .frame(width: 300)

    }

    // MARK: - Compact Empty State

    private var compactEmptyState: some View {
        VStack(spacing: Moros.spacing8) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(Moros.oracle.opacity(0.3))
            Text("Ask about your notes")
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Compact Bubble

    @ViewBuilder
    private func compactBubble(for message: ChatService.AIChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 30)
                Text(message.content)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textMain)
                    .padding(Moros.spacing8)
                    .background(Moros.oracle.opacity(0.15))
                    .clipShape(Rectangle())
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textMain)
                    .textSelection(.enabled)
                    .padding(Moros.spacing8)
                    .background(Moros.limit02)
                    .clipShape(Rectangle())

                if !message.referencedNotes.isEmpty {
                    HStack(spacing: 2) {
                        Text("Refs:")
                            .font(Moros.fontMicro)
                            .foregroundStyle(Moros.textGhost)
                        ForEach(message.referencedNotes.prefix(3), id: \.objectID) { note in
                            Button(action: { appState.selectedNote = note }) {
                                Text(note.title.prefix(15) + (note.title.count > 15 ? "..." : ""))
                                    .font(Moros.fontMicro)
                                    .foregroundStyle(Moros.oracle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 2)
                }
            }

        case .system:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputText = ""

        Task {
            await chatService.ask(
                question: question,
                context: context,
                currentNote: appState.selectedNote
            )
        }
    }
}
