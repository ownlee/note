import Foundation
import SwiftData

@MainActor
final class NoteProcessor {
    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Analyzes the note, applies the result, and persists the SwiftData changes.
    func process(_ note: BrainNote, in modelContext: ModelContext) async throws -> NoteProcessingResult {
        let result = try await analyze(rawText: note.rawText)
        try Task.checkCancellation()

        note.category = result.category
        note.eventDate = result.eventDate
        note.tags = result.tags
        note.processingState = .complete

        try modelContext.save()
        return result
    }

    /// Converts raw note text into values that can be applied to a `BrainNote`.
    func analyze(rawText: String) async throws -> NoteProcessingResult {
        guard !apiKey.isEmpty, apiKey != "YOUR_OPENAI_API_KEY" else {
            throw NoteProcessorError.missingAPIKey
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let timeZone = TimeZone.current.identifier
        let requestBody = ResponsesRequest(
            model: "gpt-4o-mini",
            input: [
                .init(
                    role: "system",
                    content: """
                    Analyze a scratchpad note and classify its primary intent.

                    intent rules:
                    - task: something the user must complete. It remains unfinished after its
                      due time until the user checks it off.
                    - event: something the user mainly needs to attend or see on a calendar. It
                      naturally finishes when its time passes.
                    - scheduleSeries: a roster or repeated set of multiple dated time blocks.
                    - note: a thought or saved piece of information with no completion state.

                    A time mention alone does not make an event. "Send the email by 3 PM" is a
                    task; "Meeting at 3 PM" is an event.

                    Category describes notes and tasks. task must use Actionable. For event or
                    scheduleSeries, choose Reference. For note, use the closest category below.
                    Reflective means a thought, feeling, observation, or journal entry.
                    Creative means an idea for something to make, write, design, or explore.
                    Reference means information saved for later lookup.

                    Resolve dates using reference time \(now) in time zone \(timeZone). For a
                    task, eventDate is its due time. For an event, eventDate is its start and
                    endDate is its end; use one hour after the start when duration is absent.
                    Otherwise return null for both. title is a concise calendar-safe title with
                    dates and times removed. Choose the closest scheduleKind for events.
                    confidence is 0 to 1 and must be low when task vs event is ambiguous.
                    Return up to six short, lowercase tags without leading # characters.
                    """
                ),
                .init(role: "user", content: rawText)
            ],
            text: .init(format: .noteAnalysis),
            store: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NoteProcessorError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw NoteProcessorError.apiError(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message ?? "Unknown API error"
            )
        }

        let responseBody = try JSONDecoder().decode(ResponsesResponse.self, from: data)

        if let refusal = responseBody.refusal {
            throw NoteProcessorError.refused(refusal)
        }

        guard let outputText = responseBody.outputText,
              let outputData = outputText.data(using: .utf8) else {
            throw NoteProcessorError.missingOutput
        }

        do {
            let analysis = try JSONDecoder().decode(NoteAnalysisPayload.self, from: outputData)
            return NoteProcessingResult(
                intent: analysis.intent.brainNoteIntent,
                category: analysis.category.brainNoteCategory,
                eventDate: try parseEventDate(analysis.eventDate),
                endDate: try parseEventDate(analysis.endDate),
                title: analysis.title.trimmingCharacters(in: .whitespacesAndNewlines),
                scheduleKind: analysis.scheduleKind.scheduleKind,
                confidence: min(max(analysis.confidence, 0), 1),
                tags: normalizedTags(analysis.tags)
            )
        } catch {
            if let processorError = error as? NoteProcessorError {
                throw processorError
            }
            throw NoteProcessorError.invalidOutput(error)
        }
    }

    /// Labels an imported schedule once, so every event in the series shares a concise title.
    func analyzeScheduleContext(rawText: String) async throws -> ScheduleContextResult {
        guard !apiKey.isEmpty, apiKey != "YOUR_OPENAI_API_KEY" else {
            throw NoteProcessorError.missingAPIKey
        }

        let requestBody = ScheduleContextRequest(
            model: "gpt-4o-mini",
            input: [
                .init(
                    role: "system",
                    content: """
                    Identify what this repeated schedule represents. Return one concise title in
                    the user's language, such as 근무, 운동, 병원, 수업, or 이동. Never include
                    dates or times in the title. Choose the closest kind enum. Return confidence
                    from 0 to 1 based only on evidence in the text: use a low value when several
                    schedule types are plausible. This label applies to every event in the pasted
                    schedule.
                    """
                ),
                .init(role: "user", content: rawText)
            ],
            text: .init(format: .scheduleContext),
            store: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NoteProcessorError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw NoteProcessorError.apiError(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message ?? "Unknown API error"
            )
        }

        let responseBody = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        if let refusal = responseBody.refusal { throw NoteProcessorError.refused(refusal) }
        guard let outputText = responseBody.outputText,
              let outputData = outputText.data(using: .utf8) else {
            throw NoteProcessorError.missingOutput
        }

        do {
            let payload = try JSONDecoder().decode(ScheduleContextPayload.self, from: outputData)
            let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return ScheduleContextResult(
                title: title.isEmpty ? payload.kind.scheduleKind.title : title,
                kind: payload.kind.scheduleKind,
                confidence: min(max(payload.confidence, 0), 1)
            )
        } catch {
            throw NoteProcessorError.invalidOutput(error)
        }
    }

    /// Extracts a schedule from a screenshot or photo into the same draft shape as pasted text.
    func extractSchedule(
        from imageData: Data,
        mimeType: String
    ) async throws -> ScheduleImportDraft {
        guard !apiKey.isEmpty, apiKey != "YOUR_OPENAI_API_KEY" else {
            throw NoteProcessorError.missingAPIKey
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let timeZone = TimeZone.current.identifier
        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let requestBody = ImageScheduleRequest(
            model: "gpt-4o-mini",
            input: [
                .init(
                    role: "user",
                    content: [
                        .text(
                            """
                            Read every visible calendar or schedule event in this image. Resolve
                            dates using reference time \(now) and time zone \(timeZone). Preserve
                            overnight ranges by returning an endDate after startDate. If a year is
                            not visible, use the nearest plausible year. Identify the shared
                            schedule type and a concise title without dates or times. Confidence
                            must be 0 to 1 and low when the schedule type is ambiguous. Ignore UI
                            chrome, ads, and calendar navigation controls.
                            """
                        ),
                        .image(dataURL)
                    ]
                )
            ],
            text: .init(format: .imageSchedule),
            store: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NoteProcessorError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw NoteProcessorError.apiError(
                statusCode: httpResponse.statusCode,
                message: apiError?.error.message ?? "Unknown API error"
            )
        }

        let responseBody = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        if let refusal = responseBody.refusal { throw NoteProcessorError.refused(refusal) }
        guard let outputText = responseBody.outputText,
              let outputData = outputText.data(using: .utf8) else {
            throw NoteProcessorError.missingOutput
        }

        do {
            let payload = try JSONDecoder().decode(ImageSchedulePayload.self, from: outputData)
            guard !payload.events.isEmpty else { throw NoteProcessorError.noScheduleInImage }

            let shifts = try payload.events.map { event in
                guard let startDate = try parseEventDate(event.startDate),
                      let endDate = try parseEventDate(event.endDate),
                      endDate > startDate else {
                    throw NoteProcessorError.invalidScheduleRange
                }
                return ParsedWorkShift(
                    startDate: startDate,
                    endDate: endDate,
                    details: event.details?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .sorted { $0.startDate < $1.startDate }

            guard let firstDate = shifts.first?.startDate else {
                throw NoteProcessorError.noScheduleInImage
            }
            let month = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: firstDate)
            ) ?? firstDate
            let parsedKind = payload.kind.scheduleKind
            let cleanTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let schedule = ParsedWorkSchedule(
                month: month,
                title: cleanTitle.isEmpty ? parsedKind.title : cleanTitle,
                kind: parsedKind,
                shifts: shifts
            )

            return ScheduleImportDraft(
                rawText: "Image schedule · confidence \(min(max(payload.confidence, 0), 1))",
                schedule: schedule,
                suggestedConfidence: min(max(payload.confidence, 0), 1)
            )
        } catch {
            if let processorError = error as? NoteProcessorError { throw processorError }
            throw NoteProcessorError.invalidOutput(error)
        }
    }

    private func parseEventDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw NoteProcessorError.invalidEventDate(value)
        }
        return date
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()

        return tags.compactMap { tag in
            let normalized = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .lowercased()

            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
        .prefix(6)
        .map { $0 }
    }
}

struct NoteProcessingResult: Sendable {
    let intent: BrainNoteIntent
    let category: BrainNoteCategory
    let eventDate: Date?
    let endDate: Date?
    let title: String
    let scheduleKind: ScheduleKind
    let confidence: Double
    let tags: [String]
}

struct ScheduleContextResult: Sendable {
    let title: String
    let kind: ScheduleKind
    let confidence: Double
}

private struct ScheduleContextPayload: Decodable {
    let title: String
    let kind: ParsedScheduleKind
    let confidence: Double
}

private struct ImageSchedulePayload: Decodable {
    let title: String
    let kind: ParsedScheduleKind
    let confidence: Double
    let events: [Event]

    struct Event: Decodable {
        let startDate: String
        let endDate: String
        let details: String?
    }
}

private struct ImageScheduleRequest: Encodable {
    let model: String
    let input: [InputMessage]
    let text: TextConfiguration
    let store: Bool

    struct InputMessage: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let text: String?
        let imageURL: String?
        let detail: String?

        static func text(_ value: String) -> Content {
            Content(type: "input_text", text: value, imageURL: nil, detail: nil)
        }

        static func image(_ dataURL: String) -> Content {
            Content(type: "input_image", text: nil, imageURL: dataURL, detail: "high")
        }

        enum CodingKeys: String, CodingKey {
            case type, text, detail
            case imageURL = "image_url"
        }
    }

    struct TextConfiguration: Encodable {
        let format: OutputFormat
    }

    struct OutputFormat: Encodable {
        let type: String
        let name: String
        let strict: Bool
        let schema: Schema

        static let imageSchedule = OutputFormat(
            type: "json_schema",
            name: "image_schedule",
            strict: true,
            schema: .init()
        )
    }

    struct Schema: Encodable {
        let type = "object"
        let properties = Properties()
        let required = ["title", "kind", "confidence", "events"]
        let additionalProperties = false

        struct Properties: Encodable {
            let title = StringProperty()
            let kind = KindProperty()
            let confidence = NumberProperty()
            let events = EventsProperty()
        }

        struct StringProperty: Encodable { let type = "string" }
        struct NumberProperty: Encodable { let type = "number" }

        struct KindProperty: Encodable {
            let type = "string"
            let values = ["work", "exercise", "appointment", "personal", "travel", "other"]

            enum CodingKeys: String, CodingKey {
                case type
                case values = "enum"
            }
        }

        struct EventsProperty: Encodable {
            let type = "array"
            let items = EventProperty()
        }

        struct EventProperty: Encodable {
            let type = "object"
            let properties = EventProperties()
            let required = ["startDate", "endDate", "details"]
            let additionalProperties = false
        }

        struct EventProperties: Encodable {
            let startDate = DescribedStringProperty(
                description: "ISO 8601 timestamp with time-zone offset."
            )
            let endDate = DescribedStringProperty(
                description: "ISO 8601 timestamp after startDate with time-zone offset."
            )
            let details = NullableStringProperty()
        }

        struct DescribedStringProperty: Encodable {
            let type = "string"
            let description: String
        }

        struct NullableStringProperty: Encodable {
            let type = ["string", "null"]
        }
    }
}

private enum ParsedScheduleKind: String, Decodable {
    case work, exercise, appointment, personal, travel, other

    var scheduleKind: ScheduleKind {
        switch self {
        case .work: .work
        case .exercise: .exercise
        case .appointment: .appointment
        case .personal: .personal
        case .travel: .travel
        case .other: .other
        }
    }
}

private struct ScheduleContextRequest: Encodable {
    let model: String
    let input: [InputMessage]
    let text: TextConfiguration
    let store: Bool

    struct InputMessage: Encodable {
        let role: String
        let content: String
    }

    struct TextConfiguration: Encodable {
        let format: OutputFormat
    }

    struct OutputFormat: Encodable {
        let type: String
        let name: String
        let strict: Bool
        let schema: Schema

        static let scheduleContext = OutputFormat(
            type: "json_schema",
            name: "schedule_context",
            strict: true,
            schema: .init()
        )
    }

    struct Schema: Encodable {
        let type = "object"
        let properties = Properties()
        let required = ["title", "kind", "confidence"]
        let additionalProperties = false

        struct Properties: Encodable {
            let title = StringProperty()
            let kind = KindProperty()
            let confidence = NumberProperty()
        }

        struct StringProperty: Encodable {
            let type = "string"
        }

        struct KindProperty: Encodable {
            let type = "string"
            let values = ["work", "exercise", "appointment", "personal", "travel", "other"]

            enum CodingKeys: String, CodingKey {
                case type
                case values = "enum"
            }
        }

        struct NumberProperty: Encodable {
            let type = "number"
        }
    }
}

private struct NoteAnalysisPayload: Decodable {
    let intent: ParsedNoteIntent
    let category: ParsedCategory
    let eventDate: String?
    let endDate: String?
    let title: String
    let scheduleKind: ParsedScheduleKind
    let confidence: Double
    let tags: [String]
}

private enum ParsedNoteIntent: String, Decodable {
    case note, task, event, scheduleSeries

    var brainNoteIntent: BrainNoteIntent {
        switch self {
        case .note: .note
        case .task: .task
        case .event: .event
        case .scheduleSeries: .scheduleSeries
        }
    }
}

private enum ParsedCategory: String, Decodable {
    case actionable = "Actionable"
    case reflective = "Reflective"
    case creative = "Creative"
    case reference = "Reference"

    var brainNoteCategory: BrainNoteCategory {
        switch self {
        case .actionable: .actionable
        case .reflective: .reflective
        case .creative: .creative
        case .reference: .reference
        }
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: [InputMessage]
    let text: TextConfiguration
    let store: Bool

    struct InputMessage: Encodable {
        let role: String
        let content: String
    }

    struct TextConfiguration: Encodable {
        let format: OutputFormat
    }

    struct OutputFormat: Encodable {
        let type: String
        let name: String
        let strict: Bool
        let schema: NoteAnalysisSchema

        static let noteAnalysis = OutputFormat(
            type: "json_schema",
            name: "note_analysis",
            strict: true,
            schema: .init()
        )
    }

    struct NoteAnalysisSchema: Encodable {
        let type = "object"
        let properties = Properties()
        let required = [
            "intent", "category", "eventDate", "endDate", "title",
            "scheduleKind", "confidence", "tags"
        ]
        let additionalProperties = false

        struct Properties: Encodable {
            let intent = IntentProperty()
            let category = CategoryProperty()
            let eventDate = NullableStringProperty()
            let endDate = NullableStringProperty()
            let title = StringProperty()
            let scheduleKind = ScheduleKindProperty()
            let confidence = NumberProperty()
            let tags = TagsProperty()
        }

        struct IntentProperty: Encodable {
            let type = "string"
            let values = ["note", "task", "event", "scheduleSeries"]

            enum CodingKeys: String, CodingKey {
                case type
                case values = "enum"
            }
        }

        struct CategoryProperty: Encodable {
            let type = "string"
            let values = ["Actionable", "Reflective", "Creative", "Reference"]

            enum CodingKeys: String, CodingKey {
                case type
                case values = "enum"
            }
        }

        struct NullableStringProperty: Encodable {
            let type = ["string", "null"]
            let description = "ISO 8601 timestamp with time-zone offset, or null."
        }

        struct TagsProperty: Encodable {
            let type = "array"
            let items = StringProperty()
            let maxItems = 6
        }

        struct StringProperty: Encodable {
            let type = "string"
        }

        struct ScheduleKindProperty: Encodable {
            let type = "string"
            let values = ["work", "exercise", "appointment", "personal", "travel", "other"]

            enum CodingKeys: String, CodingKey {
                case type
                case values = "enum"
            }
        }

        struct NumberProperty: Encodable {
            let type = "number"
        }
    }
}

private struct ResponsesResponse: Decodable {
    let output: [OutputItem]

    var outputText: String? {
        output
            .flatMap { $0.content ?? [] }
            .first { $0.type == "output_text" }?
            .text
    }

    var refusal: String? {
        output
            .flatMap { $0.content ?? [] }
            .first { $0.type == "refusal" }?
            .refusal
    }

    struct OutputItem: Decodable {
        let content: [ContentItem]?
    }

    struct ContentItem: Decodable {
        let type: String
        let text: String?
        let refusal: String?
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

enum NoteProcessorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case missingOutput
    case refused(String)
    case invalidOutput(Error)
    case invalidEventDate(String)
    case noScheduleInImage
    case invalidScheduleRange

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "The OpenAI API key is missing."
        case .invalidResponse:
            "The server returned an invalid response."
        case let .apiError(statusCode, message):
            "OpenAI API error \(statusCode): \(message)"
        case .missingOutput:
            "The response did not contain an analysis."
        case let .refused(reason):
            "The model could not analyze this note: \(reason)"
        case let .invalidOutput(error):
            "The model returned an invalid analysis: \(error.localizedDescription)"
        case let .invalidEventDate(value):
            "The model returned an invalid event date: \(value)"
        case .noScheduleInImage:
            "No readable schedule was found in that image."
        case .invalidScheduleRange:
            "A schedule in the image had an invalid time range."
        }
    }
}
