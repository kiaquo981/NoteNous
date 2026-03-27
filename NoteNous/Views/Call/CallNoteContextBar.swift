import SwiftUI

struct CallNoteContextBar: View {
    let callNote: CallNoteService.CallNote
    let onTap: () -> Void

    @Environment(\.moros) private var moros

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(Moros.fontCaption)
                    .foregroundStyle(moros.oracle)

                Text("From call:")
                    .font(Moros.fontCaption)
                    .foregroundStyle(moros.textDim)

                Text(callNote.topic)
                    .font(Moros.fontCaption)
                    .fontWeight(.medium)
                    .foregroundStyle(moros.textSub)
                    .lineLimit(1)

                Text("on \(callNote.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(Moros.fontCaption)
                    .foregroundStyle(moros.textDim)

                if !callNote.participants.isEmpty {
                    Text("with \(callNote.participants.joined(separator: ", "))")
                        .font(Moros.fontCaption)
                        .foregroundStyle(moros.textDim)
                        .lineLimit(1)
                }

                Spacer()

                if callNote.isProcessed {
                    Image(systemName: "sparkles")
                        .font(Moros.fontCaption)
                        .foregroundStyle(moros.oracle)
                }

                Image(systemName: "chevron.right")
                    .font(Moros.fontMicro)
                    .foregroundStyle(moros.textGhost)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(moros.oracle.opacity(0.06), in: Rectangle())
            .overlay(
                Rectangle()
                    .strokeBorder(moros.oracle.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
