import SwiftUI

/// Visual calendar showing review load for the next 30 days.
/// Color-coded by card count: 0=empty, 1-3=AMBIENT, 4-7=ORACLE, 8+=SIGNAL.
struct ReviewCalendarView: View {
    @ObservedObject var srsService: SpacedRepetitionService

    @State private var selectedDate: Date?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle().fill(Moros.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Stats row
                    statsRow

                    // Day-of-week headers
                    dayOfWeekHeaders

                    // Calendar grid
                    calendarGrid

                    // Selected day detail
                    if let date = selectedDate {
                        selectedDayDetail(date: date)
                    }
                }
                .padding(16)
            }
        }

        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 16) {
            Label("REVIEW CALENDAR", systemImage: "calendar")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Moros.oracle)

            Spacer()

            let srsStats = srsService.stats()
            Text("\(srsStats.enrolled) enrolled")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)

            Text("avg interval \(averageInterval)d")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Moros.limit01)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let srsStats = srsService.stats()
        return HStack(spacing: 16) {
            miniStat(label: "Due today", value: "\(srsStats.dueToday)", color: Moros.signal)
            miniStat(label: "This week", value: "\(srsStats.dueThisWeek)", color: Moros.oracle)
            miniStat(label: "Enrolled", value: "\(srsStats.enrolled)", color: Moros.ambient)
            miniStat(label: "Avg ease", value: String(format: "%.1f", srsStats.averageEase), color: Moros.verdit)
            Spacer()
        }
    }

    private func miniStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Moros.limit02, in: Rectangle())
    }

    // MARK: - Day of Week Headers

    private var dayOfWeekHeaders: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { day in
                Text(day)
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = next30Days()
        let today = calendar.startOfDay(for: Date())

        // Pad to align with weekday
        let firstWeekday = calendar.component(.weekday, from: today)
        let paddingDays = firstWeekday - 1 // Sunday = 1

        return LazyVGrid(columns: columns, spacing: 4) {
            // Leading padding
            ForEach(0..<paddingDays, id: \.self) { _ in
                Color.clear
                    .frame(height: 44)
            }

            // Actual days
            ForEach(days, id: \.self) { date in
                let count = srsService.cardsDue(on: date).count
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                Button {
                    withAnimation(.easeInOut(duration: Moros.animFast)) {
                        selectedDate = date
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12, weight: isToday ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(isToday ? Moros.oracle : Moros.textMain)

                        if count > 0 {
                            Text("\(count)")
                                .font(Moros.fontMicro)
                                .foregroundStyle(cardCountColor(count))
                        } else {
                            Text("-")
                                .font(Moros.fontMicro)
                                .foregroundStyle(Moros.textGhost)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(cellBackground(count: count, isToday: isToday, isSelected: isSelected), in: Rectangle())
                    .overlay(
                        Rectangle()
                            .strokeBorder(isToday ? Moros.oracle : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Selected Day Detail

    private func selectedDayDetail(date: Date) -> some View {
        let cards = srsService.cardsDue(on: date)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        return VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Moros.border).frame(height: 1)

            HStack {
                Text(formatter.string(from: date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)

                Text("\(cards.count) cards due")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textSub)

                Spacer()
            }

            if cards.isEmpty {
                Text("No reviews scheduled for this day.")
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textDim)
            } else {
                ForEach(cards) { card in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(easeColor(card.easeFactor))
                            .frame(width: 6, height: 6)

                        Text(card.id.uuidString.prefix(8))
                            .font(Moros.fontMono)
                            .foregroundStyle(Moros.textSub)

                        Text("ease \(String(format: "%.1f", card.easeFactor))")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)

                        Text("rep \(card.repetitions)")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Helpers

    private func next30Days() -> [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<30).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    private func cardCountColor(_ count: Int) -> Color {
        if count >= 8 { return Moros.signal }
        if count >= 4 { return Moros.oracle }
        if count >= 1 { return Moros.ambient }
        return Moros.textGhost
    }

    private func cellBackground(count: Int, isToday: Bool, isSelected: Bool) -> Color {
        if isSelected { return Moros.limit04 }
        if count >= 8 { return Moros.signal.opacity(0.08) }
        if count >= 4 { return Moros.oracle.opacity(0.06) }
        if count >= 1 { return Moros.ambient.opacity(0.04) }
        return Moros.limit01
    }

    private func easeColor(_ ease: Double) -> Color {
        if ease >= 2.5 { return Moros.verdit }
        if ease >= 2.0 { return Moros.oracle }
        if ease >= 1.5 { return Moros.ambient }
        return Moros.signal
    }

    private var averageInterval: Int {
        let cards = Array(srsService.cards.values)
        guard !cards.isEmpty else { return 0 }
        let total = cards.reduce(0) { $0 + $1.interval }
        return total / cards.count
    }
}
