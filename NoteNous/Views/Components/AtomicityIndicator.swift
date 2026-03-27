import SwiftUI

/// A visual indicator showing the atomicity health of a note.
/// Shows as a colored dot: VERDIT (atomic), ORACLE (minor issues), SIGNAL (needs work).
struct AtomicityIndicator: View {
    let report: AtomicityReport
    var size: IndicatorSize = .small

    @State private var showPopover = false

    enum IndicatorSize {
        case small, medium, large

        var dotSize: CGFloat {
            switch self {
            case .small: 8
            case .medium: 12
            case .large: 16
            }
        }

        var font: Font {
            switch self {
            case .small: Moros.fontMicro
            case .medium: Moros.fontCaption
            case .large: Moros.fontBody
            }
        }
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(severityColor)
                    .frame(width: size.dotSize, height: size.dotSize)

                if size != .small {
                    Text(report.severity.label)
                        .font(size.font)
                        .foregroundStyle(severityColor)
                }
            }
        }
        .buttonStyle(.plain)
        .help(report.severity.label)
        .popover(isPresented: $showPopover) {
            atomicityPopover
        }
    }

    // MARK: - Popover

    private var atomicityPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Circle()
                    .fill(severityColor)
                    .frame(width: 12, height: 12)
                Text(report.severity.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                Spacer()
            }

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Stats
            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "Words", value: "\(report.wordCount)", ideal: "40-400")
                statRow(label: "Headings", value: "\(report.headingCount)", ideal: "0-1")
                statRow(label: "Paragraphs", value: "\(report.paragraphCount)", ideal: "1-4")
                statRow(label: "Outgoing Links", value: "\(report.outgoingLinkCount)", ideal: "1+")
                statRow(label: "Title Words", value: "\(report.titleWordCount)", ideal: "4+")
            }

            // Issues
            if !report.issues.isEmpty {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("ISSUES")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)

                    ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: issue.icon)
                                .foregroundStyle(issue.isCritical ? Moros.signal : Moros.ambient)
                                .font(.caption)
                                .frame(width: 14)
                            Text(issue.description)
                                .font(Moros.fontCaption)
                                .foregroundStyle(issue.isCritical ? Moros.textMain : Moros.textSub)
                        }
                    }
                }
            } else {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)

                Label("This note follows atomic note principles", systemImage: "checkmark.circle.fill")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.verdit)
            }
        }
        .padding(12)
        .frame(width: 300)
        .morosBackground(Moros.limit02)
    }

    private func statRow(label: String, value: String, ideal: String) -> some View {
        HStack {
            Text(label)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textSub)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textMain)
                .frame(width: 40, alignment: .trailing)
            Text("(\(ideal))")
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textDim)
        }
    }

    // MARK: - Colors

    private var severityColor: Color {
        switch report.severity {
        case .good: Moros.verdit
        case .warning: Moros.oracle
        case .critical: Moros.signal
        }
    }
}

// MARK: - Convenience for NoteEntity

struct NoteAtomicityIndicator: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    var size: AtomicityIndicator.IndicatorSize = .small

    var body: some View {
        // Only show for permanent notes
        if note.noteType == .permanent || note.noteType == .literature {
            let service = AtomicNoteService(context: context)
            let report = service.analyze(note: note)
            AtomicityIndicator(report: report, size: size)
        }
    }
}
