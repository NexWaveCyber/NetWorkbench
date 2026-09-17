import Foundation

/// Records terminal sessions into the open, industry-standard Asciinema v2 format (.cast)
/// Each event captures a floating-point microsecond timestamp, event type ("o" for stdout), and payload data.
public final class AsciinemaRecorder: @unchecked Sendable {
    public private(set) var isRecording: Bool = false
    public private(set) var startTime: Date?
    public var cols: Int = 80
    public var rows: Int = 24
    public var title: String = "NexWave Terminal Session"

    private struct Event {
        let time: Double
        let type: String
        let data: String
    }

    private var events: [Event] = []
    private let lock = NSLock()

    public init(cols: Int = 80, rows: Int = 24, title: String = "NexWave Terminal Session") {
        self.cols = cols
        self.rows = rows
        self.title = title
    }

    /// Start recording session
    public func start(cols: Int? = nil, rows: Int? = nil, title: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if let c = cols { self.cols = c }
        if let r = rows { self.rows = r }
        if let t = title { self.title = t }

        self.events.removeAll()
        self.startTime = Date()
        self.isRecording = true
    }

    /// Record a chunk of terminal stdout data
    public func recordOutput(_ text: String) {
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        guard isRecording, let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        events.append(Event(time: elapsed, type: "o", data: text))
    }

    /// Current duration of the active recording in seconds
    public var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Event count captured so far
    public var eventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    /// Stop recording and generate .cast file content
    public func stop() -> String {
        lock.lock()
        defer { lock.unlock() }

        isRecording = false
        return generateCastString()
    }

    /// Export recording to a temporary or documents file URL
    public func exportToFile(filename: String? = nil) throws -> URL {
        let castContent = stop()
        let name = filename ?? "terminal_session_\(Int(Date().timeIntervalSince1970)).cast"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try castContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    /// Generate raw Asciinema v2 JSON Lines string
    public func generateCastString() -> String {
        let header = AsciinemaCastHeader(
            width: max(20, cols),
            height: max(5, rows),
            timestamp: Int(startTime?.timeIntervalSince1970 ?? Date().timeIntervalSince1970),
            title: title
        )

        var lines: [String] = []
        if let headerData = try? JSONEncoder().encode(header),
           let headerString = String(data: headerData, encoding: .utf8) {
            lines.append(headerString)
        } else {
            lines.append("{\"version\": 2, \"width\": \(cols), \"height\": \(rows), \"timestamp\": \(Int(Date().timeIntervalSince1970)), \"title\": \"\(title)\"}")
        }

        for event in events {
            // Escape json string safely
            if let eventData = try? JSONSerialization.data(withJSONObject: [event.time, event.type, event.data]),
               let eventString = String(data: eventData, encoding: .utf8) {
                lines.append(eventString)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
