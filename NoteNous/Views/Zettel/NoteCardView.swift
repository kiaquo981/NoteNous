import SwiftUI
import CoreData

/// A view that renders a note as a physical notecard (Holiday/Greene 4x6 card style).
/// Front: theme tag, content body, source reference, domain color stripe.
/// Back: metadata (zettelId, created date, link count, atomicity) with flip animation.
struct NoteCardView: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context

    var showFlip: Bool = true
    var maxWidth: CGFloat = 320
    var maxHeight: CGFloat = 220

    @State private var isFlipped: Bool = false

    var body: some View {
        ZStack {
            // Back of card
            cardBack
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)

            // Front of card
            cardFront
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
        }
        .frame(width: maxWidth, height: maxHeight)
        .animation(.easeInOut(duration: Moros.animBase), value: isFlipped)
        .onTapGesture(count: 2) {
            if showFlip {
                isFlipped.toggle()
            }
        }
    }

    // MARK: - Front

    private var cardFront: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color stripe (domain/type indicator)
            Rectangle()
                .fill(stripeColor)
                .frame(height: 5)

            VStack(alignment: .leading, spacing: 8) {
                // Top: theme/category tag
                HStack {
                    Spacer()
                    if let firstTag = note.tagsArray.first, let name = firstTag.name {
                        Text(name.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Moros.oracle.opacity(0.15), in: Rectangle())
                            .foregroundStyle(Moros.oracle)
                    } else {
                        Text(note.noteType.label.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(noteTypeColor.opacity(0.15), in: Rectangle())
                            .foregroundStyle(noteTypeColor)
                    }
                }

                // Body: content as paragraph
                Text(note.contentPlainText.isEmpty ? "No content" : String(note.contentPlainText.prefix(280)))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Bottom: source reference
                HStack(spacing: 6) {
                    if let sourceTitle = note.sourceTitle {
                        Image(systemName: "book.closed")
                            .font(.system(size: 9))
                            .foregroundStyle(Moros.textDim)
                        Text(sourceTitle)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(Moros.textDim)
                            .lineLimit(1)
                    }
                    Spacer()
                    if showFlip {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 9))
                            .foregroundStyle(Moros.textGhost)
                    }
                }
            }
            .padding(12)
        }
        .background(Moros.limit02)
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(Moros.borderLit, lineWidth: 1))
    }

    // MARK: - Back

    private var cardBack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(stripeColor)
                .frame(height: 5)

            VStack(alignment: .leading, spacing: 10) {
                // Title
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(2)

                Rectangle().fill(Moros.border).frame(height: 1)

                // Metadata
                VStack(alignment: .leading, spacing: 6) {
                    metaRow(label: "Zettel ID", value: note.zettelId ?? "none")
                    metaRow(label: "Type", value: note.noteType.label)
                    metaRow(label: "Created", value: formattedDate)
                    metaRow(label: "Links", value: "\(note.totalLinkCount)")

                    // Atomicity
                    let service = AtomicNoteService(context: context)
                    let report = service.analyze(note: note)
                    metaRow(label: "Words", value: "\(report.wordCount)")
                    HStack(spacing: 4) {
                        Text("Atomic:")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)
                            .frame(width: 60, alignment: .leading)
                        Circle()
                            .fill(report.isAtomic ? Moros.verdit : Moros.signal)
                            .frame(width: 6, height: 6)
                        Text(report.severity.label)
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(report.isAtomic ? Moros.verdit : Moros.signal)
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    if showFlip {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 9))
                            .foregroundStyle(Moros.textGhost)
                    }
                }
            }
            .padding(12)
        }
        .background(Moros.limit02)
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(Moros.borderLit, lineWidth: 1))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textSub)
        }
    }

    // MARK: - Computed

    private var stripeColor: Color {
        if let hex = note.colorHex {
            return Color(hex: hex)
        }
        return noteTypeColor.opacity(0.6)
    }

    private var noteTypeColor: Color {
        switch note.noteType {
        case .fleeting: Moros.ambient
        case .literature: Moros.oracle
        case .permanent: Moros.verdit
        case .structure: Moros.textSub
        }
    }

    private var formattedDate: String {
        guard let date = note.createdAt else { return "?" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
