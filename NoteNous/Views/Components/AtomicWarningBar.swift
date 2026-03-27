import SwiftUI

/// A prominent full-width bar that appears in the editor when a PERMANENT or LITERATURE note
/// violates atomicity principles. Impossible to miss, impossible to ignore.
struct AtomicWarningBar: View {
    let report: AtomicityReport
    let onSplit: () -> Void
    let onRefineTitle: () -> Void

    @State private var showGreenFlash: Bool = true

    var body: some View {
        Group {
            switch report.severity {
            case .critical:
                criticalBar
            case .warning:
                warningBar
            case .good:
                goodBar
            }
        }
    }

    // MARK: - Critical (RED / SIGNAL)

    private var criticalBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Moros.signal)
                .font(.system(size: 14))

            Text(criticalMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Moros.textMain)
                .lineLimit(2)

            Spacer()

            if hasSplittableIssue {
                Button(action: onSplit) {
                    Text("Split Now")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.void)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Moros.signal, in: Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Moros.signal.opacity(0.12))
        .overlay(alignment: .top) {
            Rectangle().fill(Moros.signal).frame(height: 2)
        }
    }

    // MARK: - Warning (YELLOW / ORACLE)

    private var warningBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Moros.oracle)
                .font(.system(size: 14))

            Text(warningMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Moros.textMain)
                .lineLimit(2)

            Spacer()

            if hasTopicTitleIssue {
                Button(action: onRefineTitle) {
                    Text("Refine Title")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.void)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Moros.oracle, in: Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Moros.oracle.opacity(0.08))
        .overlay(alignment: .top) {
            Rectangle().fill(Moros.oracle).frame(height: 2)
        }
    }

    // MARK: - Good (GREEN / VERDIT) — brief flash

    private var goodBar: some View {
        Group {
            if showGreenFlash {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Moros.verdit)
                        .font(.system(size: 14))

                    Text("Atomic -- 1 idea, clear claim, well-connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Moros.verdit)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Moros.verdit.opacity(0.06))
                .overlay(alignment: .top) {
                    Rectangle().fill(Moros.verdit).frame(height: 2)
                }
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: Moros.animSlow)) {
                            showGreenFlash = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed

    private var criticalMessage: String {
        var parts: [String] = []
        for issue in report.issues {
            switch issue {
            case .tooLong(let wordCount, _):
                parts.append("\(wordCount) words")
            case .multipleHeadings(let count):
                parts.append("\(count) headings")
            case .tooManyParagraphs(let count):
                parts.append("\(count) paragraphs")
            case .tooShort(let wordCount, _):
                parts.append("only \(wordCount) words")
            case .missingSource:
                parts.append("no source")
            default:
                break
            }
        }

        let ideaCount = max(report.headingCount, 1)
        if ideaCount > 1 {
            return "This note has \(ideaCount) ideas (\(parts.joined(separator: ", "))). Split it."
        }
        return "Issues: \(parts.joined(separator: ", ")). Fix before this note is ready."
    }

    private var warningMessage: String {
        var parts: [String] = []
        for issue in report.issues {
            switch issue {
            case .topicTitle:
                parts.append("Title is a topic, not a claim. Sharpen: 'X does Y because Z'")
            case .noOutgoingLinks:
                parts.append("No links. Connect this idea to your existing knowledge.")
            default:
                parts.append(issue.description)
            }
        }
        return parts.joined(separator: " ")
    }

    private var hasSplittableIssue: Bool {
        report.issues.contains(where: {
            switch $0 {
            case .tooLong, .multipleHeadings, .tooManyParagraphs: return true
            default: return false
            }
        })
    }

    private var hasTopicTitleIssue: Bool {
        report.issues.contains(where: {
            if case .topicTitle = $0 { return true }
            return false
        })
    }
}
