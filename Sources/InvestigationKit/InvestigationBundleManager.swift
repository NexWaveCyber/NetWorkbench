import Foundation
import PersistenceKit

/// Manages serialization, file packaging, and database import for `.nwi` investigation bundles
public enum InvestigationBundleManager {

    /// Creates an `.nwi` JSON/archive bundle payload
    public static func createBundle(
        investigation: InvestigationRecord,
        timelineEvents: [TimelineEventRecord] = [],
        diagnostics: [DiagnosticHistoryRecord] = [],
        configFiles: [AttachedConfigFile] = [],
        pcapData: Data? = nil,
        notes: String = ""
    ) throws -> Data {
        let bundle = InvestigationBundle(
            investigation: investigation,
            timelineEvents: timelineEvents,
            diagnosticSnapshots: diagnostics,
            attachedConfigFiles: configFiles,
            packetCaptureBase64: pcapData?.base64EncodedString(),
            notes: notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    /// Exports bundle data directly to a `.nwi` file URL
    public static func exportBundleToFile(
        investigation: InvestigationRecord,
        timelineEvents: [TimelineEventRecord] = [],
        diagnostics: [DiagnosticHistoryRecord] = [],
        configFiles: [AttachedConfigFile] = [],
        pcapData: Data? = nil,
        notes: String = "",
        to url: URL
    ) throws {
        let data = try createBundle(
            investigation: investigation,
            timelineEvents: timelineEvents,
            diagnostics: diagnostics,
            configFiles: configFiles,
            pcapData: pcapData,
            notes: notes
        )
        try data.write(to: url, options: .atomic)
    }

    /// Decodes an `.nwi` bundle from raw Data
    public static func loadBundle(from data: Data) throws -> InvestigationBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InvestigationBundle.self, from: data)
    }

    /// Loads and parses an `.nwi` bundle from a file URL
    public static func loadBundle(from url: URL) throws -> InvestigationBundle {
        let data = try Data(contentsOf: url)
        return try loadBundle(from: data)
    }

    /// Ingests and persists an imported investigation bundle into SQLite
    public static func importIntoDatabase(
        bundle: InvestigationBundle,
        investigationRepo: InvestigationRepository,
        historyRepo: DiagnosticHistoryRepository? = nil
    ) throws {
        try investigationRepo.insert(bundle.investigation)
        for event in bundle.timelineEvents {
            try investigationRepo.addTimelineEvent(event)
        }
        if let hRepo = historyRepo {
            for diag in bundle.diagnosticSnapshots {
                try hRepo.record(diag)
            }
        }
    }
}
