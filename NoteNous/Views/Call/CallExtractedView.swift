import SwiftUI

struct CallExtractedView: View {
    let result: CallNoteService.ExtractionResult
    let onApply: () -> Void

    @Environment(\.moros) private var moros
    @State private var expandedSections: Set<String> = ["summary", "decisions", "actions", "insights"]

    var body: some View {
        VStack(alignment: .leading, spacing: Moros.spacing12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(moros.oracle)
                Text("AI Extraction Results")
                    .font(Moros.fontSubhead)
                    .foregroundStyle(moros.oracle)
                Spacer()
            }

            // Summary
            extractionSection(key: "summary", title: "Summary", icon: "doc.text") {
                Text(result.summary)
                    .font(Moros.fontBody)
                    .foregroundStyle(moros.textSub)
            }

            // Key Decisions
            if !result.keyDecisions.isEmpty {
                extractionSection(key: "decisions", title: "Key Decisions", icon: "checkmark.seal") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.keyDecisions, id: \.self) { decision in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Moros.fontCaption)
                                    .foregroundStyle(moros.verdit)
                                Text(decision)
                                    .font(Moros.fontSmall)
                                    .foregroundStyle(moros.textSub)
                            }
                        }
                    }
                }
            }

            // Action Items
            if !result.actionItems.isEmpty {
                extractionSection(key: "actions", title: "Action Items", icon: "checklist") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.actionItems) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                    .font(Moros.fontSmall)
                                    .foregroundStyle(moros.oracle)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.text)
                                        .font(Moros.fontSmall)
                                        .foregroundStyle(moros.textSub)
                                    HStack(spacing: 6) {
                                        if let assignee = item.assignee {
                                            Text("@\(assignee)")
                                                .font(Moros.fontCaption)
                                                .foregroundStyle(moros.oracle)
                                        }
                                        if let due = item.dueDate {
                                            Text("due: \(due.formatted(date: .abbreviated, time: .omitted))")
                                                .font(Moros.fontCaption)
                                                .foregroundStyle(moros.textDim)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Insights
            if !result.insights.isEmpty {
                extractionSection(key: "insights", title: "Insights (\(result.insights.count) Zettels)", icon: "diamond") {
                    VStack(spacing: 8) {
                        ForEach(Array(result.insights.enumerated()), id: \.offset) { _, insight in
                            insightCard(insight)
                        }
                    }
                }
            }

            // Tags
            if !result.suggestedTags.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(Moros.fontCaption)
                        .foregroundStyle(moros.textDim)
                    ForEach(result.suggestedTags, id: \.self) { tag in
                        Text(tag)
                            .font(Moros.fontCaption)
                            .foregroundStyle(moros.textSub)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(moros.limit03, in: Rectangle())
                    }
                }
            }

            // Follow-up
            if let followUp = result.followUpDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(Moros.fontSmall)
                        .foregroundStyle(moros.oracle)
                    Text("Follow-up: \(followUp.formatted(date: .abbreviated, time: .omitted))")
                        .font(Moros.fontSmall)
                        .foregroundStyle(moros.textSub)
                }
            }

            // Apply button
            Button(action: onApply) {
                HStack {
                    Image(systemName: "arrow.down.doc.fill")
                    Text("Apply — Create \(1 + result.insights.count) Notes")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(Moros.void)
                .background(moros.verdit, in: Rectangle())
                .font(Moros.fontSubhead)
            }
            .buttonStyle(.plain)
        }
        .padding(Moros.spacing12)
        .background(moros.oracle.opacity(0.04), in: Rectangle())
        .overlay(
            Rectangle()
                .strokeBorder(moros.oracle.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Section

    @ViewBuilder
    private func extractionSection<Content: View>(
        key: String,
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if expandedSections.contains(key) {
                    expandedSections.remove(key)
                } else {
                    expandedSections.insert(key)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedSections.contains(key) ? "chevron.down" : "chevron.right")
                        .font(Moros.fontCaption)
                    Image(systemName: icon)
                        .font(Moros.fontSmall)
                    Text(title)
                        .font(Moros.fontSmall)
                        .fontWeight(.medium)
                }
                .foregroundStyle(moros.textMain)
            }
            .buttonStyle(.plain)

            if expandedSections.contains(key) {
                content()
                    .padding(.leading, Moros.spacing16)
            }
        }
    }

    // MARK: - Insight Card

    private func insightCard(_ insight: CallNoteService.ExtractionResult.ExtractedInsight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: insight.noteType == .permanent ? "diamond.fill" : "book.fill")
                    .font(Moros.fontCaption)
                    .foregroundStyle(insight.noteType == .permanent ? moros.verdit : moros.oracle)
                Text(insight.title)
                    .font(Moros.fontSmall)
                    .fontWeight(.medium)
                    .foregroundStyle(moros.textMain)
                    .lineLimit(2)
            }

            Text(insight.content)
                .font(Moros.fontCaption)
                .foregroundStyle(moros.textDim)
                .lineLimit(3)

            if !insight.suggestedTags.isEmpty {
                HStack(spacing: 2) {
                    ForEach(insight.suggestedTags, id: \.self) { tag in
                        Text(tag)
                            .font(Moros.fontMicro)
                            .foregroundStyle(moros.textDim)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(moros.limit03, in: Rectangle())
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(moros.limit02, in: Rectangle())
    }
}
