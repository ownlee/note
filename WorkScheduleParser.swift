import Foundation

struct ParsedWorkSchedule: Sendable {
    let month: Date
    let title: String
    let kind: ScheduleKind
    let shifts: [ParsedWorkShift]
}

struct ParsedWorkShift: Identifiable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let details: String?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        details: String?
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.details = details
    }
}

struct ScheduleImportDraft: Identifiable, Sendable {
    let id = UUID()
    let rawText: String
    let schedule: ParsedWorkSchedule
    let suggestedConfidence: Double?

    init(
        rawText: String,
        schedule: ParsedWorkSchedule,
        suggestedConfidence: Double? = nil
    ) {
        self.rawText = rawText
        self.schedule = schedule
        self.suggestedConfidence = suggestedConfidence
    }
}

enum WorkScheduleParser {
    static func parse(
        _ text: String,
        calendar sourceCalendar: Calendar = .current,
        now: Date = .now
    ) -> ParsedWorkSchedule? {
        var calendar = sourceCalendar
        calendar.locale = Locale(identifier: "ko_KR")

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let header = lines.compactMap(parseMonthHeader).first else {
            return nil
        }

        let fallbackYear = calendar.component(.year, from: now)
        let year = header.year ?? fallbackYear
        guard let monthDate = calendar.date(
            from: DateComponents(year: year, month: header.month, day: 1)
        ) else {
            return nil
        }

        var pendingDay: Int?
        var shifts: [ParsedWorkShift] = []

        for line in lines {
            if let dateLine = parseDateLine(line), dateLine.month == header.month {
                pendingDay = dateLine.day

                if let time = parseTimeRange(dateLine.remainder),
                   let shift = makeShift(
                       year: year,
                       month: header.month,
                       day: dateLine.day,
                       time: time,
                       calendar: calendar
                   ) {
                    shifts.append(shift)
                    pendingDay = nil
                }
                continue
            }

            guard let day = pendingDay else { continue }

            if line == "-" || line == "–" || line == "—" {
                pendingDay = nil
                continue
            }

            guard let time = parseTimeRange(line),
                  let shift = makeShift(
                      year: year,
                      month: header.month,
                      day: day,
                      time: time,
                      calendar: calendar
                  ) else {
                continue
            }

            shifts.append(shift)
            pendingDay = nil
        }

        // Requiring several dated shifts prevents ordinary notes from being mistaken for a roster.
        guard shifts.count >= 3 else { return nil }
        let kind = inferredKind(from: text)
        return ParsedWorkSchedule(
            month: monthDate,
            title: kind.title,
            kind: kind,
            shifts: shifts
        )
    }

    private static func parseMonthHeader(_ line: String) -> (year: Int?, month: Int)? {
        guard line.localizedCaseInsensitiveContains("스케줄")
                || line.localizedCaseInsensitiveContains("schedule")
                || line.localizedCaseInsensitiveContains("근무표") else {
            return nil
        }

        let pattern = #"(?:(\d{4})\s*년\s*)?(\d{1,2})\s*월"#
        guard let match = firstMatch(pattern, in: line),
              let month = integer(in: line, range: match.range(at: 2)),
              (1...12).contains(month) else {
            return nil
        }

        return (integer(in: line, range: match.range(at: 1)), month)
    }

    private static func parseDateLine(
        _ line: String
    ) -> (month: Int, day: Int, remainder: String)? {
        let pattern = #"^(\d{1,2})\s*월\s*(\d{1,2})\s*일(?:\s*\([^)]*\))?(.*)$"#
        guard let match = firstMatch(pattern, in: line),
              let month = integer(in: line, range: match.range(at: 1)),
              let day = integer(in: line, range: match.range(at: 2)) else {
            return nil
        }

        let remainder = substring(in: line, range: match.range(at: 3))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (month, day, remainder)
    }

    private static func parseTimeRange(
        _ line: String
    ) -> (startHour: Int, startMinute: Int, endText: String, detail: String?)? {
        let pattern = #"(\d{1,2}):(\d{2})\s*[-–—~]\s*(\d{1,2}):(\d{2})(?:\s*\(([^)]*)\))?"#
        guard let match = firstMatch(pattern, in: line),
              let startHour = integer(in: line, range: match.range(at: 1)),
              let startMinute = integer(in: line, range: match.range(at: 2)),
              let endHour = integer(in: line, range: match.range(at: 3)),
              let endMinute = integer(in: line, range: match.range(at: 4)),
              (0...23).contains(startHour),
              (0...59).contains(startMinute),
              (0...23).contains(endHour),
              (0...59).contains(endMinute) else {
            return nil
        }

        return (
            startHour,
            startMinute,
            String(format: "%02d:%02d", endHour, endMinute),
            substring(in: line, range: match.range(at: 5))
        )
    }

    private static func makeShift(
        year: Int,
        month: Int,
        day: Int,
        time: (startHour: Int, startMinute: Int, endText: String, detail: String?),
        calendar: Calendar
    ) -> ParsedWorkShift? {
        guard let startDate = calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: time.startHour,
                minute: time.startMinute
            )
        ) else {
            return nil
        }

        let endComponents = time.endText.split(separator: ":").compactMap { Int($0) }
        guard endComponents.count == 2,
              var endDate = calendar.date(
                  from: DateComponents(
                      year: year,
                      month: month,
                      day: day,
                      hour: endComponents[0],
                      minute: endComponents[1]
                  )
              ) else {
            return nil
        }

        if endDate <= startDate {
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }

        let detail = time.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedWorkShift(
            startDate: startDate,
            endDate: endDate,
            details: detail.map(normalizedBreakDetail)
        )
    }

    private static func inferredKind(from text: String) -> ScheduleKind {
        let normalized = text.lowercased()
        if normalized.contains("근무") || normalized.contains("출근")
            || normalized.contains("휴게") || normalized.contains("shift") {
            return .work
        }
        if normalized.contains("운동") || normalized.contains("헬스")
            || normalized.contains("workout") || normalized.contains("training") {
            return .exercise
        }
        if normalized.contains("여행") || normalized.contains("비행") {
            return .travel
        }
        return .other
    }

    private static func normalizedBreakDetail(_ detail: String) -> String {
        let compact = detail.replacingOccurrences(of: " ", with: "")
        guard compact.hasPrefix("휴게"),
              let hours = compact.dropFirst(2).first,
              hours.isNumber else {
            return detail
        }
        return "휴게 \(hours)시간"
    }

    private static func firstMatch(_ pattern: String, in value: String) -> NSTextCheckingResult? {
        try? NSRegularExpression(pattern: pattern).firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        )
    }

    private static func integer(in value: String, range: NSRange) -> Int? {
        substring(in: value, range: range).flatMap(Int.init)
    }

    private static func substring(in value: String, range: NSRange) -> String? {
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: value) else {
            return nil
        }
        return String(value[swiftRange])
    }
}
