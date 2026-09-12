import Foundation

public enum ReportFormat: String, Sendable, Codable, CaseIterable {
    case markdown = "Markdown (.md)"
    case json = "JSON Data (.json)"
    case printableHTML = "Printable HTML (.html)"

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .printableHTML: return "html"
        }
    }

    public var mimeType: String {
        switch self {
        case .markdown: return "text/markdown"
        case .json: return "application/json"
        case .printableHTML: return "text/html"
        }
    }
}

public struct ReportMetadata: Sendable, Codable {
    public let reportID: UUID
    public let generatedAt: Date
    public let appVersion: String
    public let authorHost: String
    public let isSanitized: Bool

    public init(
        reportID: UUID = UUID(),
        generatedAt: Date = Date(),
        appVersion: String = "1.0.0 (Milestone 2)",
        authorHost: String = ProcessInfo.processInfo.hostName,
        isSanitized: Bool = true
    ) {
        self.reportID = reportID
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.authorHost = authorHost
        self.isSanitized = isSanitized
    }
}

public struct ExportedReport: Sendable, Codable, Identifiable {
    public var id: UUID { metadata.reportID }
    public let title: String
    public let format: ReportFormat
    public let metadata: ReportMetadata
    public let content: String

    public init(title: String, format: ReportFormat, metadata: ReportMetadata = ReportMetadata(), content: String) {
        self.title = title
        self.format = format
        self.metadata = metadata
        self.content = content
    }
}
