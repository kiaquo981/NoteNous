import SwiftUI

/// Compact live log view showing real-time agent activity.
/// Monospaced, color-coded by severity, auto-scrolls to bottom.
struct AgentActivityLog: View {
    let entries: [ZettelkastenAgent.LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            logHeader
            Rectangle().fill(Moros.border).frame(height: 1)
            logContent
        }
    }

    // MARK: - Header

    private var logHeader: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .font(.system(size: 10))
                .foregroundStyle(Moros.textDim)
            Text("Activity Log")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)
            Spacer()
            Text("\(entries.count) entries")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textGhost)
            Button {
                copyLog()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(Moros.textDim)
            }
            .buttonStyle(.plain)
            .help("Copy log to clipboard")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Moros.limit02)
    }

    // MARK: - Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(8)
            }
            .background(Moros.void)
            .onChange(of: entries.count) { _ in
                if let last = entries.last {
                    withAnimation(.easeOut(duration: Moros.animFast)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRow(_ entry: ZettelkastenAgent.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(timeString(entry.timestamp))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Moros.textGhost)
                .frame(width: 60, alignment: .leading)

            Circle()
                .fill(severityColor(entry.severity))
                .frame(width: 4, height: 4)
                .padding(.top, 4)

            Text(entry.message)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(severityColor(entry.severity))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func severityColor(_ severity: ZettelkastenAgent.LogEntry.Severity) -> Color {
        switch severity {
        case .info: return Moros.textDim
        case .action: return Moros.oracle
        case .warning: return Moros.ambient
        case .error: return Moros.signal
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func copyLog() {
        let text = entries.map { entry in
            "[\(timeString(entry.timestamp))] [\(entry.severity.rawValue.uppercased())] \(entry.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
