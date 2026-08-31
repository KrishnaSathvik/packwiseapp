import SwiftUI

/// A month grid with a selected date range.
///
/// The board's dates step is a calendar, and two `DatePicker` wheels do not
/// answer the question a traveller is actually asking — how long the trip is
/// and which days it covers. SwiftUI has no range calendar (`MultiDatePicker`
/// selects a set, not a span), so this draws one.
///
/// Tapping picks a start and collapses the range; the next tap sets the end,
/// or starts over when it falls before the start.
struct PackWiseDateRangePicker: View {
    @Binding var start: Date
    @Binding var end: Date
    /// Days before this are not selectable. Trips do not start in the past.
    var earliest: Date

    @State private var visibleMonth: Date
    @State private var awaitingEnd = false

    private let calendar: Calendar
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(start: Binding<Date>, end: Binding<Date>, earliest: Date, calendar: Calendar = .current) {
        _start = start
        _end = end
        self.earliest = earliest
        self.calendar = calendar
        _visibleMonth = State(initialValue: calendar.startOfDay(for: start.wrappedValue))
    }

    var body: some View {
        VStack(spacing: PackWiseSpacing.regular) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: Self.columns, spacing: PackWiseSpacing.tight) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Previous month")

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next month")
        }
        .font(.body.weight(.semibold))
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Short weekday names rotated to the locale's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Days

    private func dayCell(_ day: Date) -> some View {
        let selectable = !calendar.startOfDay(for: day).isBefore(calendar.startOfDay(for: earliest))
        return Button {
            select(day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(foreground(for: day, selectable: selectable))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(alignment: .center) { background(for: day) }
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isEndpoint(day) ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func background(for day: Date) -> some View {
        ZStack {
            // Endpoints keep the band too, so it reads as one continuous
            // span rather than stopping short of the circles.
            if isWithinRange(day) {
                PackWiseColor.accent.opacity(0.14)
            }
            if isEndpoint(day) {
                Circle()
                    .fill(PackWiseColor.accent)
                    .frame(width: 36, height: 36)
            }
        }
    }

    private func foreground(for day: Date, selectable: Bool) -> Color {
        if isEndpoint(day) { return .white }
        if !selectable { return Color(.tertiaryLabel) }
        return .primary
    }

    private func isEndpoint(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: start) || calendar.isDate(day, inSameDayAs: end)
    }

    private func isWithinRange(_ day: Date) -> Bool {
        let target = calendar.startOfDay(for: day)
        return target >= calendar.startOfDay(for: start) && target <= calendar.startOfDay(for: end)
    }

    /// Days of the visible month, padded with nils so the first lands under
    /// its weekday column.
    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let range = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + dates
    }

    // MARK: - Selection

    private func select(_ day: Date) {
        let target = calendar.startOfDay(for: day)
        if awaitingEnd, target >= calendar.startOfDay(for: start) {
            end = target
            awaitingEnd = false
        } else {
            start = target
            end = target
            awaitingEnd = true
        }
    }

    private var canGoBack: Bool {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: visibleMonth),
              let interval = calendar.dateInterval(of: .month, for: previous) else {
            return false
        }
        return interval.end > calendar.startOfDay(for: earliest)
    }

    private func shiftMonth(by offset: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            visibleMonth = shifted
        }
    }
}

private extension Date {
    func isBefore(_ other: Date) -> Bool { self < other }
}
