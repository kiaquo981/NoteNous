import SwiftUI
import CoreData

struct AIChatView: View {
    @StateObject private var chatService = ChatService()
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Moros.oracle)
                Text("AI CHAT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)
                Spacer()
                if !chatService.messages.isEmpty {
                    Button(action: { chatService.clearChat() }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(Moros.textDim)
                    }
                    .buttonStyle(.plain)
                    .help("Clear chat")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Moros.spacing12) {
                        if chatService.messages.isEmpty {
                            emptyState
                        }

                        ForEach(chatService.messages) { message in
                            chatBubble(for: message)
                                .id(message.id)
                        }

                        if chatService.isStreaming {
                            streamingIndicator
                        }
                    }
                    .padding()
                }
                .onChange(of: chatService.messages.count) {
                    if let lastId = chatService.messages.last?.id {
                        withAnimation(.easeOut(duration: Moros.animBase)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Status
            if let status = chatService.statusMessage {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(status)
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            // Input
            HStack(spacing: 8) {
                TextField("Ask about your notes...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(inputText.isEmpty || chatService.isStreaming ? Moros.textDim : Moros.oracle)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || chatService.isStreaming)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Moros.limit02)
        }

        .onAppear { isInputFocused = true }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Moros.spacing12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundStyle(Moros.oracle.opacity(0.4))
            Text("Ask anything about your notes")
                .font(Moros.fontSubhead)
                .foregroundStyle(Moros.textSub)
            Text("I'll search your Zettelkasten and answer based on what you've written.")
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Chat Bubble

    @ViewBuilder
    private func chatBubble(for message: ChatService.AIChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .padding(Moros.spacing12)
                    .background(Moros.oracle.opacity(0.15))
                    .clipShape(Rectangle())
            }

        case .assistant:
            VStack(alignment: .leading, spacing: Moros.spacing8) {
                Text(message.content)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .textSelection(.enabled)
                    .padding(Moros.spacing12)
                    .background(Moros.limit02)
                    .clipShape(Rectangle())

                // Referenced notes
                if !message.referencedNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Based on:")
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.textDim)
                        FlowLayout(spacing: 4) {
                            ForEach(message.referencedNotes, id: \.objectID) { note in
                                Button(action: { appState.selectedNote = note }) {
                                    Text("[[\(note.title)]]")
                                        .font(Moros.fontCaption)
                                        .foregroundStyle(Moros.oracle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.leading, Moros.spacing4)
                }
            }

        case .system:
            EmptyView()
        }
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Moros.oracle)
                    .frame(width: 6, height: 6)
                    .opacity(0.5)
            }
        }
        .padding(Moros.spacing12)
        .background(Moros.limit02)
        .clipShape(Rectangle())
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

// FlowLayout is defined in PromotionSheet.swift — reused here
