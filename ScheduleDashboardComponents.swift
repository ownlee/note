import SwiftUI

struct ScheduleWorkspacePicker: View {
    @Binding var selection: ScheduleSharingMode
    let personalCount: Int
    let teamCount: Int
    let showsTeamCalendar: Bool

    var body: some View {
        HStack(spacing: 3) {
            workspaceButton(.personal, count: personalCount)
            if showsTeamCalendar {
                workspaceButton(.team, count: teamCount)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func workspaceButton(_ mode: ScheduleSharingMode, count: Int) -> some View {
        Button {
            withAnimation(.snappy) { selection = mode }
        } label: {
            Image(systemName: mode.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selection == mode ? Color.white : Color.primary)
                .frame(width: 38, height: 34)
                .background(
                    selection == mode
                        ? (mode == .team ? Color.indigo : Color.accentColor)
                        : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) calendar, \(count) schedules")
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
    }
}

struct TeamWorkspaceSelector: View {
    let workspaces: [ScheduleTeamWorkspace]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onManage: () -> Void

    private var selectedWorkspace: ScheduleTeamWorkspace? {
        workspaces.first(where: { $0.id == selectedID }) ?? workspaces.first
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(workspaces) { workspace in
                    Button {
                        onSelect(workspace.id)
                    } label: {
                        Label(
                            workspace.name,
                            systemImage: workspace.id == selectedWorkspace?.id
                                ? "checkmark"
                                : "person.2"
                        )
                    }
                }

                Divider()
                Button(action: onManage) {
                    Label("Manage teams", systemImage: "slider.horizontal.3")
                }
            } label: {
                Label(selectedWorkspace?.name ?? "Choose Team", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.indigo.opacity(0.11), in: Capsule())
            }
            .accessibilityLabel("Current team: \(selectedWorkspace?.name ?? "none")")

            Button(action: onManage) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add or manage teams")

            Spacer(minLength: 0)
        }
    }
}

struct TeamShareFailureBanner: View {
    let failedCount: Int
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(failedCount == 1 ? "Team sharing paused" : "\(failedCount) shares paused")
                    .font(.subheadline.weight(.semibold))
                Text("Schedules remain in this team only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onRetry) {
                if isRetrying {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Retry").font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRetrying)
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

struct MonthlyScheduleCalendar: View {
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let entries: [ScheduleEntry]
    let sharingMode: ScheduleSharingMode
    let onAdd: () -> Void
    let onBulkEdit: () -> Void
    let onImportImage: () -> Void

    private let calendar = Calendar.current
    private let weekdaySymbols = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(normalizedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.title3.weight(.bold))
                    Text(monthSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                monthButton("chevron.left", value: -1, label: "Previous month")
                monthButton("chevron.right", value: 1, label: "Next month")
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(index >= 5 ? Color.indigo : Color.secondary)
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
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    if sharingMode == .team {
                        Text("TEAM")
                            .font(.system(size: 62, weight: .black, design: .rounded))
                            .foregroundStyle(.indigo.opacity(0.08))
                            .rotationEffect(.degrees(-18))
                            .allowsHitTesting(false)
                    }
                }
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
    }

    private func dayCell(_ date: Date) -> some View {
        let dayEntries = entriesForDay(date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        return Button {
            selectedDay = date
        } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(.caption.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
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

    private func monthButton(_ image: String, value: Int, label: String) -> some View {
        Button {
            withAnimation(.snappy) {
                month = calendar.date(byAdding: .month, value: value, to: normalizedMonth) ?? month
                selectedDay = entries.first(where: {
                    calendar.isDate($0.startDate, equalTo: month, toGranularity: .month)
                })?.startDate
            }
        } label: {
            Image(systemName: image).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.06), in: Circle())
        .accessibilityLabel(label)
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
        let leading = (calendar.component(.weekday, from: normalizedMonth) + 5) % 7
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
                if !entry.assigneeNames.isEmpty {
                    Label(entry.assigneeNames.joined(separator: ", "), systemImage: "person.fill")
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
