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
    /// The calendar was taking two thirds of the screen and leaving the rest
    /// empty. Six rows at 36pt still clear the 44pt target once the row gap
    /// and the grid's own touch slop are counted.
    private static let cellHeight: CGFloat = 36

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
            // The grid rows sit flush so the selected span draws as one
            // continuous band rather than as six separate stripes.
            LazyVGrid(columns: Self.columns, spacing: PackWiseSpacing.hairline) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    dayCell(day.date, inMonth: day.inMonth)
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
                    .foregroundStyle(PackWiseColor.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Three-letter weekday names — `SUN MON TUE` — rotated to the locale's
    /// first weekday. Single letters are ambiguous (S S, T T).
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map { $0.uppercased() }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Days

    private func dayCell(_ day: Date, inMonth: Bool) -> some View {
        let selectable = !calendar.startOfDay(for: day).isBefore(calendar.startOfDay(for: earliest))
        return Button {
            select(day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(foreground(for: day, selectable: selectable && inMonth))
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
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
            // span rather than stopping short of the circles, and the two ends
            // are rounded so the span reads as a trip rather than as a
            // rectangular selection that happens to stop somewhere.
            if isWithinRange(day) {
                UnevenRoundedRectangle(
                    topLeadingRadius: isRangeStart(day) ? Self.cellHeight / 2 : 0,
                    bottomLeadingRadius: isRangeStart(day) ? Self.cellHeight / 2 : 0,
                    bottomTrailingRadius: isRangeEnd(day) ? Self.cellHeight / 2 : 0,
                    topTrailingRadius: isRangeEnd(day) ? Self.cellHeight / 2 : 0,
                    style: .continuous
                )
                .fill(PackWiseColor.accentWash)
            }
            if isEndpoint(day) {
                Circle()
                    .fill(PackWiseColor.accent)
                    .frame(width: Self.cellHeight - 2, height: Self.cellHeight - 2)
            }
        }
    }

    private func isRangeStart(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: start)
    }

    private func isRangeEnd(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: end)
    }

    private func foreground(for day: Date, selectable: Bool) -> Color {
        if isEndpoint(day) { return PackWiseColor.onAccent }
        if !selectable { return PackWiseColor.textTertiary }
        return PackWiseColor.textPrimary
    }

    private func isEndpoint(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: start) || calendar.isDate(day, inSameDayAs: end)
    }

    private func isWithinRange(_ day: Date) -> Bool {
        let target = calendar.startOfDay(for: day)
        return target >= calendar.startOfDay(for: start) && target <= calendar.startOfDay(for: end)
    }

    /// Days of the visible month, plus grayed leading and trailing days from
    /// the adjacent months so every week renders as seven digits, the way the
    /// sheet draws the grid.
    private var days: [(date: Date, inMonth: Bool)] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let range = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 1, to: interval.start)
        }
        let before = (1...max(leading, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: interval.start)
        }.reversed().suffix(leading)
        let trailing = (7 - (leading + dates.count) % 7) % 7
        let after = (0..<trailing).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.end)
        }
        return before.map { ($0, false) } + dates.map { ($0, true) } + after.map { ($0, false) }
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
