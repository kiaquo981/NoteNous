import SwiftUI
import CoreData

/// Main UI for the Autonomous Zettelkasten Agent.
/// Top: Run button + phase indicator + progress. Middle: Action review list. Bottom: Stats + apply.
struct AgentDashboard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @StateObject private var agent = ZettelkastenAgent()

    @State private var selectedActionType: AgentAction.ActionType? = nil
    @State private var expandedActionId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            agentHeader
            Rectangle().fill(Moros.border).frame(height: 1)
            phaseBar
            Rectangle().fill(Moros.border).frame(height: 1)

            if agent.phase == .idle && agent.actions.isEmpty {
                emptyState
            } else if agent.isRunning {
                runningState
            } else {
                actionReviewSection
            }

            Rectangle().fill(Moros.border).frame(height: 1)
            statsBar
        }
        .morosBackground(Moros.limit01)
    }

    // MARK: - Header

    private var agentHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 16))
                .foregroundStyle(Moros.oracle)
                .morosGlow(Moros.oracle, radius: agent.isRunning ? 12 : 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Zettelkasten Agent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                Text(agent.phase.rawValue)
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(agent.isRunning ? Moros.oracle : Moros.textDim)
            }

            Spacer()

            if !agent.isRunning {
                Button {
                    Task {
                        await agent.processFleetingNotes(context: context)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Run Agent")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Moros.void)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Moros.oracle, in: Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Moros.oracle)
            }
        }
        .padding()
    }

    // MARK: - Phase Bar

    private var phaseBar: some View {
        VStack(spacing: 6) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Moros.limit03)
                        .frame(height: 3)
                    Rectangle()
                        .fill(Moros.oracle)
                        .frame(width: geo.size.width * agent.progress, height: 3)
                        .animation(.easeInOut(duration: Moros.animBase), value: agent.progress)
                }
            }
            .frame(height: 3)

            // Phase dots
            HStack(spacing: 0) {
                ForEach(AgentPhase.allCases, id: \.rawValue) { phase in
                    phaseDot(phase)
                    if phase != AgentPhase.allCases.last {
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func phaseDot(_ phase: AgentPhase) -> some View {
        let isActive = agent.phase == phase
        let isPast = AgentPhase.allCases.firstIndex(of: agent.phase)! >= AgentPhase.allCases.firstIndex(of: phase)!

        return VStack(spacing: 3) {
            Circle()
                .fill(isPast ? Moros.oracle : Moros.limit04)
                .frame(width: isActive ? 8 : 5, height: isActive ? 8 : 5)
                .overlay(
                    Circle()
                        .stroke(isActive ? Moros.oracle.opacity(0.5) : .clear, lineWidth: 2)
                        .frame(width: 12, height: 12)
                )
            Text(phase.rawValue.components(separatedBy: " ").first ?? "")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(isPast ? Moros.textSub : Moros.textGhost)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundStyle(Moros.textGhost)
            Text("Autonomous Zettelkasten Agent")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Moros.textSub)
            Text("Analyzes fleeting notes and proposes classifications,\npromotions, links, index updates, splits, and merges.\nYou review and approve every action.")
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Running State

    private var runningState: some View {
        VStack(spacing: 0) {
            AgentActivityLog(entries: agent.log)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Action Review Section

    private var actionReviewSection: some View {
        VStack(spacing: 0) {
            // Type filter bar
            typeFilterBar
            Rectangle().fill(Moros.border).frame(height: 1)

            // Batch controls
            batchControls
            Rectangle().fill(Moros.border).frame(height: 1)

            // Action list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredActions) { action in
                        actionRow(action)
                    }
                }
            }

            Rectangle().fill(Moros.border).frame(height: 1)

            // Activity log (compact)
            AgentActivityLog(entries: agent.log)
                .frame(height: 120)
        }
    }

    // MARK: - Type Filter Bar

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "All", type: nil, count: agent.actions.count)
                ForEach(AgentAction.ActionType.allCases, id: \.rawValue) { type in
                    let count = agent.actions.filter { $0.type == type }.count
                    if count > 0 {
                        filterChip(label: type.rawValue, type: type, count: count)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func filterChip(label: String, type: AgentAction.ActionType?, count: Int) -> some View {
        let isSelected = selectedActionType == type

        return Button {
            selectedActionType = type
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Moros.limit03, in: Rectangle())
            }
            .foregroundStyle(isSelected ? Moros.void : Moros.textSub)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Moros.oracle : Moros.limit03, in: Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Batch Controls

    private var batchControls: some View {
        HStack(spacing: 8) {
            Button("Approve All") { agent.approveAll() }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Moros.verdit)
                .buttonStyle(.plain)

            Text("|").foregroundStyle(Moros.textGhost).font(.system(size: 10))

            Button("Reject All") { agent.rejectAll() }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Moros.signal)
                .buttonStyle(.plain)

            Spacer()

            if agent.approvedCount > 0 {
                Button {
                    agent.applyAllApproved(context: context)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("Apply \(agent.approvedCount) Approved")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Moros.void)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Moros.verdit, in: Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Action Row

    private func actionRow(_ action: AgentAction) -> some View {
        let isExpanded = expandedActionId == action.id

        return VStack(spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                // Status indicator
                statusBadge(action.status)

                // Type icon
                Image(systemName: action.type.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(actionTypeColor(action.type))
                    .frame(width: 16)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Moros.textMain)
                        .lineLimit(isExpanded ? nil : 1)

                    if isExpanded {
                        Text(action.reasoning)
                            .font(.system(size: 10))
                            .foregroundStyle(Moros.textDim)
                            .lineLimit(4)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                // Type badge
                Text(action.type.rawValue)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(actionTypeColor(action.type))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(actionTypeColor(action.type).opacity(0.1), in: Rectangle())

                // Action buttons
                if action.status == .pending {
                    HStack(spacing: 4) {
                        Button { agent.approve(action.id) } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Moros.verdit)
                                .frame(width: 22, height: 22)
                                .background(Moros.verdit.opacity(0.1), in: Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button { agent.reject(action.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Moros.signal)
                                .frame(width: 22, height: 22)
                                .background(Moros.signal.opacity(0.1), in: Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: Moros.animFast)) {
                    expandedActionId = isExpanded ? nil : action.id
                }
            }
        }
        .background(backgroundForStatus(action.status))
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: AgentAction.ActionStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 6, height: 6)
    }

    private func statusColor(_ status: AgentAction.ActionStatus) -> Color {
        switch status {
        case .pending: return Moros.ambient
        case .approved: return Moros.verdit
        case .rejected: return Moros.signal
        case .applied: return Moros.oracle
        }
    }

    private func backgroundForStatus(_ status: AgentAction.ActionStatus) -> Color {
        switch status {
        case .pending: return Moros.limit01
        case .approved: return Moros.verdit.opacity(0.03)
        case .rejected: return Moros.signal.opacity(0.03)
        case .applied: return Moros.oracle.opacity(0.03)
        }
    }

    private func actionTypeColor(_ type: AgentAction.ActionType) -> Color {
        switch type {
        case .classify: return Moros.ambient
        case .promote: return Moros.oracle
        case .placeFolgezettel: return Moros.verdit
        case .createLink: return Moros.oracle
        case .updateIndex: return Moros.ambient
        case .splitNote: return Moros.signal
        case .mergeNotes: return Moros.ambient
        case .createStructureNote: return Moros.verdit
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            statPill(label: "Proposed", value: agent.actions.count, color: Moros.textDim)
            statPill(label: "Approved", value: agent.approvedCount, color: Moros.verdit)
            statPill(label: "Applied", value: agent.appliedCount, color: Moros.oracle)
            statPill(label: "Rejected", value: agent.actions.filter { $0.status == .rejected }.count, color: Moros.signal)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func statPill(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Moros.textDim)
        }
    }

    // MARK: - Filtered Actions

    private var filteredActions: [AgentAction] {
        if let type = selectedActionType {
            return agent.actions.filter { $0.type == type }
        }
        return agent.actions
    }
}
