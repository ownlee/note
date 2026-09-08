import SwiftUI

struct MonthlyScheduleCalendar: View {
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let entries: [ScheduleEntry]
    let onAdd: () -> Void
    let onBulkEdit: () -> Void
    let onImportImage: () -> Void

    @State private var isMonthPickerPresented = false
    @State private var pickerYear = Calendar.current.component(.year, from: .now)
    @State private var pickerMonth = Calendar.current.component(.month, from: .now)

    private let calendar = Calendar.current
    private let weekdaySymbols = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    pickerYear = calendar.component(.year, from: normalizedMonth)
                    pickerMonth = calendar.component(.month, from: normalizedMonth)
                    isMonthPickerPresented = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(normalizedMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.title3.weight(.bold))
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        Text(monthSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityHint("Opens a month and year picker")

                Spacer()
                Menu {
                    Button(action: onBulkEdit) {
                        Label("Manage schedules", systemImage: "slider.horizontal.3")
                    }
                    Button(action: onAdd) {
                        Label("Add manually", systemImage: "plus")
                    }
                    Button(action: onImportImage) {
                        Label("Import screenshot or photo", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .background(Color.indigo.opacity(0.14), in: Circle())
                .foregroundStyle(.indigo)
                .accessibilityLabel("Add or import schedule")
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(index == 0 ? Color.red : (index == 6 ? Color.blue : Color.secondary))
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthCells) { cell in
                    if let date = cell.date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 70)
                    }
                }
            }
            .simultaneousGesture(monthSwipeGesture)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.indigo.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.07), radius: 18, y: 7)
        .onAppear {
            month = normalizedMonth
            if selectedDay == nil { selectedDay = monthlyEntries.first?.startDate }
        }
        .sheet(isPresented: $isMonthPickerPresented) {
            monthYearPicker
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
    }

    private var monthYearPicker: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $pickerMonth) {
                    ForEach(1...12, id: \.self) { value in
                        Text(monthSymbols[value - 1]).tag(value)
                    }
                }
                .pickerStyle(.wheel)

                Picker("Year", selection: $pickerYear) {
                    ForEach(yearRange, id: \.self) { value in
                        Text(String(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("Jump to Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isMonthPickerPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        goToMonth(year: pickerYear, month: pickerMonth)
                        isMonthPickerPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                changeMonth(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    private var monthSymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        return formatter.standaloneMonthSymbols
    }

    private var yearRange: [Int] {
        let currentYear = calendar.component(.year, from: .now)
        return Array((currentYear - 5)...(currentYear + 5))
    }

    private func dayCell(_ date: Date) -> some View {
        let dayEntries = entriesForDay(date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let weekday = calendar.component(.weekday, from: date)
        let dayNumberColor: Color = isToday
            ? .white
            : (weekday == 1 ? .red : (weekday == 7 ? .blue : .primary))

        return Button {
            selectedDay = date
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.caption.weight(isToday ? .bold : .medium))
                    .foregroundStyle(dayNumberColor)
                    .frame(width: 23, height: 23)
                    .background(isToday ? Color.indigo : Color.clear, in: Circle())

                ForEach(dayEntries.prefix(2)) { entry in
                    Text(Self.timeText(entry.startDate))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(entry.tint.opacity(0.12), in: Capsule())
                }

                if dayEntries.count > 2 {
                    Text("+\(dayEntries.count - 2)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                } else if dayEntries.isEmpty {
                    Color.clear.frame(height: 19)
                }
            }
            .padding(3)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .top)
            .background(
                isSelected ? Color.indigo.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.indigo.opacity(0.55) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(.dateTime.month(.wide).day())), \(dayEntries.count) schedules")
    }

    private func changeMonth(by value: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: value, to: normalizedMonth) ?? month
            selectedDay = entries.first(where: {
                calendar.isDate($0.startDate, equalTo: month, toGranularity: .month)
            })?.startDate
        }
    }

    private func goToMonth(year: Int, month monthValue: Int) {
        guard let newMonth = calendar.date(from: DateComponents(year: year, month: monthValue, day: 1))
        else { return }
        withAnimation(.snappy) {
            month = newMonth
            selectedDay = entries.first(where: {
                calendar.isDate($0.startDate, equalTo: newMonth, toGranularity: .month)
            })?.startDate
        }
    }

    private var normalizedMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    private var monthlyEntries: [ScheduleEntry] {
        entries.filter {
            calendar.isDate($0.startDate, equalTo: normalizedMonth, toGranularity: .month)
        }
    }

    private var monthSummary: String {
        let kinds = Set(monthlyEntries.map(\.kind))
        let label = kinds.count == 1 ? monthlyEntries.first?.kind.title ?? "Schedule" : "Schedule"
        return "\(label) · \(monthlyEntries.count) events"
    }

    private var monthCells: [MonthCell] {
        guard let range = calendar.range(of: .day, in: .month, for: normalizedMonth) else { return [] }
        let leading = calendar.component(.weekday, from: normalizedMonth) - 1
        var result = (0..<leading).map { MonthCell(id: $0, date: nil) }
        result += range.enumerated().compactMap { offset, day in
            calendar.date(bySetting: .day, value: day, of: normalizedMonth).map {
                MonthCell(id: leading + offset, date: $0)
            }
        }
        return result
    }

    private func entriesForDay(_ date: Date) -> [ScheduleEntry] {
        entries.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private struct MonthCell: Identifiable {
        let id: Int
        let date: Date?
    }
}

struct SelectedDayAgenda: View {
    let day: Date
    let entries: [ScheduleEntry]
    let onEdit: (ScheduleEntry) -> Void
    let onDelete: (ScheduleEntry) -> Void

    private var dayEntries: [ScheduleEntry] {
        entries.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.headline)

            if dayEntries.isEmpty {
                Text("No schedule")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(dayEntries) { entry in
                    SwipeActionCard(
                        leadingAction: CardSwipeAction(
                            title: "Edit",
                            systemImage: "pencil",
                            tint: .indigo,
                            handler: { onEdit(entry) }
                        ),
                        trailingAction: CardSwipeAction(
                            title: "Delete",
                            systemImage: "trash",
                            tint: .red,
                            handler: { onDelete(entry) }
                        )
                    ) {
                        Button {
                            onEdit(entry)
                        } label: {
                            agendaRow(for: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func agendaRow(for entry: ScheduleEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.symbolName)
                .foregroundStyle(entry.tint)
                .frame(width: 28, height: 28)
                .background(entry.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                    if overlaps(entry) {
                        Label("Overlap", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(MonthlyScheduleCalendar.timeText(entry.startDate))–\(MonthlyScheduleCalendar.timeText(entry.endDate))")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                if let details = entry.details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(entry.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func overlaps(_ entry: ScheduleEntry) -> Bool {
        dayEntries.contains { other in
            other.id != entry.id
                && entry.startDate < other.endDate
                && other.startDate < entry.endDate
        }
    }
}
