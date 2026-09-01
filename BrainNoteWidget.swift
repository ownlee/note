import SwiftUI
import WidgetKit

struct BrainNoteWidgetEntry: TimelineEntry {
    let date: Date
}

struct BrainNoteWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrainNoteWidgetEntry {
        BrainNoteWidgetEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (BrainNoteWidgetEntry) -> Void
    ) {
        completion(BrainNoteWidgetEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<BrainNoteWidgetEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [BrainNoteWidgetEntry(date: .now)],
                policy: .never
            )
        )
    }
}

struct BrainNoteQuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private let captureURL = URL(string: "brainnote://capture")!

    var body: some View {
        Group {
            if family == .systemSmall {
                smallCaptureSurface
            } else {
                mediumCaptureSurface
            }
        }
        .widgetURL(captureURL)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.2),
                    Color.indigo.opacity(0.09),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var smallCaptureSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetBrand

            Spacer(minLength: 12)

            Image(systemName: "square.and.pencil")
                .font(.title2.weight(.medium))
                .foregroundStyle(.purple)

            Text("Write a\nthought…")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 8)

            Text("Tap to type")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick capture. Tap to write a thought in BrainNote.")
    }

    private var mediumCaptureSurface: some View {
        VStack(alignment: .leading, spacing: 13) {
            widgetBrand

            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Write a thought…")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Tap anywhere to start typing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                    .padding(9)
                    .background(.purple.opacity(0.13), in: Circle())
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.primary.opacity(0.075), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick capture. Tap anywhere to write a thought in BrainNote.")
    }

    private var widgetBrand: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("BrainNote")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct BrainNoteQuickCaptureWidget: Widget {
    let kind = "BrainNoteQuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: BrainNoteWidgetProvider()
        ) { entry in
            BrainNoteQuickCaptureWidgetView()
        }
        .configurationDisplayName("Quick Capture")
        .description("Open BrainNote ready to capture a thought.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BrainNoteScheduleEntry: TimelineEntry {
    let date: Date
    let items: [BrainNoteWidgetScheduleItem]
}

struct BrainNoteScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrainNoteScheduleEntry {
        BrainNoteScheduleEntry(
            date: .now,
            items: [
                BrainNoteWidgetScheduleItem(
                    id: UUID(),
                    title: "Send the proposal",
                    eventDate: .now.addingTimeInterval(60 * 45)
                ),
                BrainNoteWidgetScheduleItem(
                    id: UUID(),
                    title: "Plan tomorrow's focus",
                    eventDate: .now.addingTimeInterval(60 * 60 * 4)
                ),
            ]
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (BrainNoteScheduleEntry) -> Void
    ) {
        completion(entry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<BrainNoteScheduleEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [entry()],
                policy: .after(.now.addingTimeInterval(60 * 15))
            )
        )
    }

    private func entry() -> BrainNoteScheduleEntry {
        BrainNoteScheduleEntry(
            date: .now,
            items: BrainNoteWidgetScheduleStore.load()
        )
    }
}

struct BrainNoteScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BrainNoteScheduleEntry

    private let scheduleURL = URL(string: "brainnote://schedule")!

    var body: some View {
        Group {
            if family == .systemSmall {
                smallSchedule
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    widgetHeader
                    if entry.items.isEmpty {
                        emptySchedule
                    } else if family == .systemLarge {
                        largeMonthCalendar
                    } else {
                        ForEach(upcomingItems.prefix(3)) { item in scheduleRow(item) }
                    }
                }
            }
        }
        .widgetURL(scheduleURL)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.18),
                    Color.blue.opacity(0.07),
                    Color(uiColor: .systemBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BrainNote schedule")
    }

    private var widgetHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar").foregroundStyle(.indigo)
            Text("Schedule")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptySchedule: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.green)
            Text("Nothing scheduled").font(.headline)
            Text("Paste a roster in BrainNote to fill your schedule.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var smallSchedule: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NEXT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.indigo)

            if let item = upcomingItems.first {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(compactDate(item.eventDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timeRange(item))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(color(for: item))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } else {
                Spacer()
                Text("No schedule").font(.headline)
                Spacer()
            }
        }
    }

    private func scheduleRow(_ item: BrainNoteWidgetScheduleItem) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(for: item))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(compactDate(item.eventDate)).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(timeRange(item))
                .font(.caption.weight(.bold))
                .foregroundStyle(color(for: item))
                .lineLimit(1)
        }
    }

    private var largeMonthCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.bold))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7),
                spacing: 6
            ) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(index >= 5 ? Color.indigo : Color.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthCells) { cell in
                    if let date = cell.date {
                        widgetDayCell(date)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(.indigo)
                    .frame(width: 7, height: 7)
                Text("\(itemsInDisplayMonth.count) scheduled events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func widgetDayCell(_ date: Date) -> some View {
        let dayItems = itemsInDisplayMonth.filter { item in
            Calendar.current.isDate(item.eventDate, inSameDayAs: date)
        }
        let isToday = Calendar.current.isDateInToday(date)

        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.day()))
                .font(.caption2.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 20, height: 20)
                .background(isToday ? Color.indigo : Color.clear, in: Circle())

            if let first = dayItems.first {
                Text(Self.timeText(first.eventDate))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: first))
                    .lineLimit(1)
                if dayItems.count > 1 {
                    Text("+\(dayItems.count - 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Color.clear.frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            dayItems.isEmpty ? Color.clear : Color.indigo.opacity(0.11),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var displayMonth: Date {
        let calendar = Calendar.current
        let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: entry.date)
        ) ?? entry.date

        if entry.items.contains(where: {
            calendar.isDate($0.eventDate, equalTo: currentMonth, toGranularity: .month)
        }) {
            return currentMonth
        }

        let nextItem = entry.items.first(where: { $0.eventDate >= entry.date }) ?? entry.items[0]
        return calendar.date(
            from: calendar.dateComponents([.year, .month], from: nextItem.eventDate)
        ) ?? nextItem.eventDate
    }

    private var itemsInDisplayMonth: [BrainNoteWidgetScheduleItem] {
        entry.items.filter {
            Calendar.current.isDate($0.eventDate, equalTo: displayMonth, toGranularity: .month)
        }
    }

    private var upcomingItems: [BrainNoteWidgetScheduleItem] {
        let future = entry.items.filter { ($0.endDate ?? $0.eventDate) >= entry.date }
        return future.isEmpty ? Array(entry.items.suffix(1)) : future
    }

    private var monthCells: [WidgetMonthCell] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: displayMonth) else {
            return []
        }

        let leadingBlankCount = (calendar.component(.weekday, from: displayMonth) + 5) % 7
        var cells = (0..<leadingBlankCount).map { _ in WidgetMonthCell(date: nil) }
        cells += range.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: displayMonth)
                .map { WidgetMonthCell(date: $0) }
        }
        return cells
    }

    private struct WidgetMonthCell: Identifiable {
        let id = UUID()
        let date: Date?
    }

    private func relativeLabel(for date: Date) -> String {
        if date < .now { return "OVERDUE" }
        if Calendar.current.isDateInToday(date) { return "UP NEXT" }
        return "UPCOMING"
    }

    private func rowDateLabel(for date: Date) -> String {
        if date < .now { return "Overdue" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func compactDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
    }

    private func timeRange(_ item: BrainNoteWidgetScheduleItem) -> String {
        let start = Self.timeText(item.eventDate)
        guard let endDate = item.endDate else { return start }
        return "\(start)–\(Self.timeText(endDate))"
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func color(for item: BrainNoteWidgetScheduleItem) -> Color {
        switch item.kind {
        case "work": .indigo
        case "exercise": .green
        case "appointment": .pink
        case "personal": .orange
        case "travel": .cyan
        default: .indigo
        }
    }
}

struct BrainNoteScheduleWidget: Widget {
    let kind = BrainNoteWidgetScheduleStore.scheduleWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BrainNoteScheduleProvider()) { entry in
            BrainNoteScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("Schedule Overview")
        .description("See your upcoming schedule at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct BrainNoteScheduleDetailWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BrainNoteScheduleEntry

    private let scheduleURL = URL(string: "brainnote://schedule")!

    var body: some View {
        Group {
            if let item = nextItem {
                if family == .systemSmall {
                    smallDetail(item)
                } else {
                    mediumDetail(item)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Schedule clear")
                        .font(.headline)
                    Text("Add your next plan in BrainNote.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(scheduleURL)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    detailColor.opacity(0.2),
                    detailColor.opacity(0.06),
                    Color(uiColor: .systemBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next schedule detail")
    }

    private func smallDetail(_ item: BrainNoteWidgetScheduleItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DETAIL")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color(for: item))

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            Spacer(minLength: 0)

            Text(timeRange(item))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color(for: item))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(fullDate(item.eventDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func mediumDetail(_ item: BrainNoteWidgetScheduleItem) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Schedule Detail", systemImage: icon(for: item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: item))

                Text(item.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)

                if let details = item.details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(fullDate(item.eventDate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Text(timeRange(item))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(color(for: item))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var nextItem: BrainNoteWidgetScheduleItem? {
        let future = entry.items.filter { ($0.endDate ?? $0.eventDate) >= entry.date }
        return future.first ?? entry.items.last
    }

    private var detailColor: Color {
        nextItem.map(color(for:)) ?? .indigo
    }

    private func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func timeRange(_ item: BrainNoteWidgetScheduleItem) -> String {
        let start = Self.timeText(item.eventDate)
        guard let endDate = item.endDate else { return start }
        return "\(start)–\(Self.timeText(endDate))"
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func icon(for item: BrainNoteWidgetScheduleItem) -> String {
        switch item.kind {
        case "work": "briefcase.fill"
        case "exercise": "figure.run"
        case "appointment": "person.2.fill"
        case "personal": "person.fill"
        case "travel": "airplane"
        default: "calendar"
        }
    }

    private func color(for item: BrainNoteWidgetScheduleItem) -> Color {
        switch item.kind {
        case "work": .indigo
        case "exercise": .green
        case "appointment": .pink
        case "personal": .orange
        case "travel": .cyan
        default: .indigo
        }
    }
}

struct BrainNoteScheduleDetailWidget: Widget {
    let kind = BrainNoteWidgetScheduleStore.scheduleDetailWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BrainNoteScheduleProvider()) { entry in
            BrainNoteScheduleDetailWidgetView(entry: entry)
        }
        .configurationDisplayName("Schedule Detail")
        .description("Read your next schedule with its full time and notes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BrainNoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        BrainNoteQuickCaptureWidget()
        BrainNoteScheduleWidget()
        BrainNoteScheduleDetailWidget()
    }
}
