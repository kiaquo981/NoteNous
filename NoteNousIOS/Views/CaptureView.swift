import SwiftUI
import CoreData

struct CaptureView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var title = ""
    @State private var content = ""
    @State private var selectedNoteType: NoteType = .fleeting
    @State private var showConfirmation = false
    @State private var showVoiceCapture = false

    private let noteTypes: [NoteType] = [.fleeting, .literature, .permanent]

    var body: some View {
        NavigationStack {
            ZStack {
                MorosIOS.void.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: MorosIOS.spacing20) {

                        // Title field
                        TextField("Title", text: $title)
                            .font(MorosIOS.fontH2)
                            .foregroundColor(MorosIOS.textMain)
                            .padding(MorosIOS.spacing16)
                            .background(MorosIOS.limit02)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Content field
                        ZStack(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("What's on your mind?")
                                    .font(MorosIOS.fontBody)
                                    .foregroundColor(MorosIOS.textDim)
                                    .padding(MorosIOS.spacing16)
                                    .padding(.top, 2)
                            }
                            TextEditor(text: $content)
                                .font(MorosIOS.fontBody)
                                .foregroundColor(MorosIOS.textMain)
                                .scrollContentBackground(.hidden)
                                .padding(MorosIOS.spacing12)
                                .frame(minHeight: 200)
                        }
                        .background(MorosIOS.limit02)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Note type selector
                        HStack(spacing: MorosIOS.spacing12) {
                            ForEach(noteTypes) { type in
                                noteTypeButton(type)
                            }
                        }

                        // Capture button
                        Button(action: captureNote) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Capture")
                                    .font(MorosIOS.fontSubhead)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(MorosIOS.void)
                            .frame(maxWidth: .infinity)
                            .frame(height: MorosIOS.buttonHeight)
                            .background(MorosIOS.oracle)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .disabled(title.isEmpty && content.isEmpty)
                        .opacity(title.isEmpty && content.isEmpty ? 0.4 : 1)

                    }
                    .padding(MorosIOS.spacing16)
                }
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVoiceCapture = true
                    } label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.title2)
                            .foregroundColor(MorosIOS.oracle)
                    }
                }
            }
            .sheet(isPresented: $showVoiceCapture) {
                VoiceCaptureView()
            }
            .overlay {
                if showConfirmation {
                    confirmationOverlay
                }
            }
        }
    }

    // MARK: - Note Type Button

    private func noteTypeButton(_ type: NoteType) -> some View {
        Button {
            selectedNoteType = type
        } label: {
            VStack(spacing: MorosIOS.spacing4) {
                Image(systemName: type.icon)
                    .font(.title3)
                Text(type.label)
                    .font(MorosIOS.fontCaption)
            }
            .foregroundColor(selectedNoteType == type ? MorosIOS.oracle : MorosIOS.textDim)
            .frame(maxWidth: .infinity)
            .frame(height: MorosIOS.touchTargetMin)
            .background(
                selectedNoteType == type ? MorosIOS.oracle.opacity(0.12) : MorosIOS.limit02
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        selectedNoteType == type ? MorosIOS.oracle.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
    }

    // MARK: - Capture Action

    private func captureNote() {
        let noteService = NoteService(context: viewContext)
        let note = noteService.createNote(
            title: title.isEmpty ? Constants.autoTitle(from: content) : title,
            content: content,
            paraCategory: .inbox
        )
        note.noteType = selectedNoteType

        do {
            try viewContext.save()
        } catch {
            // Already saved by NoteService
        }

        // Reset and show confirmation
        title = ""
        content = ""
        selectedNoteType = .fleeting

        withAnimation(.easeInOut(duration: MorosIOS.animBase)) {
            showConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: MorosIOS.animBase)) {
                showConfirmation = false
            }
        }
    }

    // MARK: - Confirmation Overlay

    private var confirmationOverlay: some View {
        VStack(spacing: MorosIOS.spacing12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(MorosIOS.verdit)
            Text("Captured")
                .font(MorosIOS.fontH3)
                .foregroundColor(MorosIOS.textMain)
        }
        .padding(MorosIOS.spacing32)
        .background(MorosIOS.limit02)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .morosIOSGlow(MorosIOS.verdit, radius: 12)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
