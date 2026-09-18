import Foundation
import SQLite3

public final class InvestigationRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(_ record: InvestigationRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO investigations (
            id, title, description, environment_id, status, severity, created_at, updated_at, resolved_at, resolution,
            commander, affected_services, affected_devices, blast_radius, detected_at, mitigated_at, root_cause_category, root_cause_summary
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (record.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (record.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (record.description as NSString).utf8String, -1, nil)
            if let env = record.environmentId {
                sqlite3_bind_text(stmt, 4, (env as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_text(stmt, 5, (record.status as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (record.severity as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 7, record.createdAt)
            sqlite3_bind_double(stmt, 8, record.updatedAt)
            if let resAt = record.resolvedAt {
                sqlite3_bind_double(stmt, 9, resAt)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            if let res = record.resolution {
                sqlite3_bind_text(stmt, 10, (res as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 10)
            }

            if let cmd = record.commander {
                sqlite3_bind_text(stmt, 11, (cmd as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 11)
            }
            sqlite3_bind_text(stmt, 12, (record.affectedServices as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 13, (record.affectedDevices as NSString).utf8String, -1, nil)
            if let blast = record.blastRadius {
                sqlite3_bind_text(stmt, 14, (blast as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 14)
            }
            if let det = record.detectedAt {
                sqlite3_bind_double(stmt, 15, det)
            } else {
                sqlite3_bind_null(stmt, 15)
            }
            if let mit = record.mitigatedAt {
                sqlite3_bind_double(stmt, 16, mit)
            } else {
                sqlite3_bind_null(stmt, 16)
            }
            if let rcc = record.rootCauseCategory {
                sqlite3_bind_text(stmt, 17, (rcc as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 17)
            }
            if let rcs = record.rootCauseSummary {
                sqlite3_bind_text(stmt, 18, (rcs as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 18)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetchAll() throws -> [InvestigationRecord] {
        let sql = """
        SELECT id, title, description, environment_id, status, severity, created_at, updated_at, resolved_at, resolution,
               commander, affected_services, affected_devices, blast_radius, detected_at, mitigated_at, root_cause_category, root_cause_summary
        FROM investigations ORDER BY updated_at DESC;
        """
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [InvestigationRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let desc = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : ""
                let env = sqlite3_column_text(stmt, 3) != nil ? String(cString: sqlite3_column_text(stmt, 3)) : nil
                let status = String(cString: sqlite3_column_text(stmt, 4))
                let severity = String(cString: sqlite3_column_text(stmt, 5))
                let createdAt = sqlite3_column_double(stmt, 6)
                let updatedAt = sqlite3_column_double(stmt, 7)
                let resolvedAt = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? sqlite3_column_double(stmt, 8) : nil
                let res = sqlite3_column_text(stmt, 9) != nil ? String(cString: sqlite3_column_text(stmt, 9)) : nil

                let cmd = sqlite3_column_text(stmt, 10) != nil ? String(cString: sqlite3_column_text(stmt, 10)) : nil
                let affSvc = sqlite3_column_text(stmt, 11) != nil ? String(cString: sqlite3_column_text(stmt, 11)) : ""
                let affDev = sqlite3_column_text(stmt, 12) != nil ? String(cString: sqlite3_column_text(stmt, 12)) : ""
                let blast = sqlite3_column_text(stmt, 13) != nil ? String(cString: sqlite3_column_text(stmt, 13)) : nil
                let detAt = sqlite3_column_type(stmt, 14) != SQLITE_NULL ? sqlite3_column_double(stmt, 14) : nil
                let mitAt = sqlite3_column_type(stmt, 15) != SQLITE_NULL ? sqlite3_column_double(stmt, 15) : nil
                let rcCat = sqlite3_column_text(stmt, 16) != nil ? String(cString: sqlite3_column_text(stmt, 16)) : nil
                let rcSum = sqlite3_column_text(stmt, 17) != nil ? String(cString: sqlite3_column_text(stmt, 17)) : nil

                results.append(InvestigationRecord(
                    id: id,
                    title: title,
                    description: desc,
                    environmentId: env,
                    status: status,
                    severity: severity,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    resolvedAt: resolvedAt,
                    resolution: res,
                    commander: cmd,
                    affectedServices: affSvc,
                    affectedDevices: affDev,
                    blastRadius: blast,
                    detectedAt: detAt,
                    mitigatedAt: mitAt,
                    rootCauseCategory: rcCat,
                    rootCauseSummary: rcSum
                ))
            }
            return results
        }
    }

    public func updateStatus(
        id: String,
        status: String,
        resolution: String? = nil,
        resolvedAt: Double? = nil,
        mitigatedAt: Double? = nil,
        rootCauseSummary: String? = nil
    ) throws {
        let now = Date().timeIntervalSince1970
        let sql = """
        UPDATE investigations
        SET status = ?, resolution = COALESCE(?, resolution), resolved_at = COALESCE(?, resolved_at),
            mitigated_at = COALESCE(?, mitigated_at), root_cause_summary = COALESCE(?, root_cause_summary), updated_at = ?
        WHERE id = ?;
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (status as NSString).utf8String, -1, nil)
            if let res = resolution {
                sqlite3_bind_text(stmt, 2, (res as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            if let resAt = resolvedAt {
                sqlite3_bind_double(stmt, 3, resAt)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let mit = mitigatedAt {
                sqlite3_bind_double(stmt, 4, mit)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            if let rcs = rootCauseSummary {
                sqlite3_bind_text(stmt, 5, (rcs as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            sqlite3_bind_double(stmt, 6, now)
            sqlite3_bind_text(stmt, 7, (id as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func delete(id: String) throws {
        let sql = "DELETE FROM investigations WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func addTimelineEvent(_ event: TimelineEventRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO timeline_events (id, investigation_id, timestamp, title, detail, category)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (event.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (event.investigationId as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 3, event.timestamp)
            sqlite3_bind_text(stmt, 4, (event.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (event.detail as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (event.category as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func deleteTimelineEvent(id: String) throws {
        let sql = "DELETE FROM timeline_events WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetchEvents(forInvestigationId investigationId: String) throws -> [TimelineEventRecord] {
        let sql = "SELECT id, investigation_id, timestamp, title, detail, category FROM timeline_events WHERE investigation_id = ? ORDER BY timestamp ASC;"
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (investigationId as NSString).utf8String, -1, nil)

            var results: [TimelineEventRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let invId = String(cString: sqlite3_column_text(stmt, 1))
                let ts = sqlite3_column_double(stmt, 2)
                let title = String(cString: sqlite3_column_text(stmt, 3))
                let detail = sqlite3_column_text(stmt, 4) != nil ? String(cString: sqlite3_column_text(stmt, 4)) : ""
                let cat = String(cString: sqlite3_column_text(stmt, 5))

                results.append(TimelineEventRecord(
                    id: id,
                    investigationId: invId,
                    timestamp: ts,
                    title: title,
                    detail: detail,
                    category: cat
                ))
            }
            return results
        }
    }
}

// MARK: - Evidence Repository

public final class EvidenceRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(_ item: EvidenceItemRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO evidence_items (
            id, investigation_id, title, evidence_type, filename, sha256, byte_size, content, source_workbench, created_at, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (item.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (item.investigationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (item.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (item.evidenceType as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (item.filename as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (item.sha256 as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 7, Int32(item.byteSize))
            sqlite3_bind_text(stmt, 8, (item.content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 9, (item.sourceWorkbench as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 10, item.createdAt)
            sqlite3_bind_text(stmt, 11, (item.notes as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetch(forInvestigationId investigationId: String) throws -> [EvidenceItemRecord] {
        let sql = """
        SELECT id, investigation_id, title, evidence_type, filename, sha256, byte_size, content, source_workbench, created_at, notes
        FROM evidence_items WHERE investigation_id = ? ORDER BY created_at ASC;
        """
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (investigationId as NSString).utf8String, -1, nil)

            var results: [EvidenceItemRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let invId = String(cString: sqlite3_column_text(stmt, 1))
                let title = String(cString: sqlite3_column_text(stmt, 2))
                let evType = String(cString: sqlite3_column_text(stmt, 3))
                let fn = String(cString: sqlite3_column_text(stmt, 4))
                let hash = String(cString: sqlite3_column_text(stmt, 5))
                let size = Int(sqlite3_column_int(stmt, 6))
                let content = sqlite3_column_text(stmt, 7) != nil ? String(cString: sqlite3_column_text(stmt, 7)) : ""
                let source = String(cString: sqlite3_column_text(stmt, 8))
                let ts = sqlite3_column_double(stmt, 9)
                let notes = sqlite3_column_text(stmt, 10) != nil ? String(cString: sqlite3_column_text(stmt, 10)) : ""

                results.append(EvidenceItemRecord(
                    id: id,
                    investigationId: invId,
                    title: title,
                    evidenceType: evType,
                    filename: fn,
                    sha256: hash,
                    byteSize: size,
                    content: content,
                    sourceWorkbench: source,
                    createdAt: ts,
                    notes: notes
                ))
            }
            return results
        }
    }

    public func delete(id: String) throws {
        let sql = "DELETE FROM evidence_items WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }
}

// MARK: - Hypothesis Repository

public final class HypothesisRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(_ item: HypothesisRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO investigation_hypotheses (
            id, investigation_id, statement, status, proposed_test, findings, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (item.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (item.investigationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (item.statement as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (item.status as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (item.proposedTest as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (item.findings as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 7, item.updatedAt)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetch(forInvestigationId investigationId: String) throws -> [HypothesisRecord] {
        let sql = """
        SELECT id, investigation_id, statement, status, proposed_test, findings, updated_at
        FROM investigation_hypotheses WHERE investigation_id = ? ORDER BY updated_at ASC;
        """
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (investigationId as NSString).utf8String, -1, nil)

            var results: [HypothesisRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let invId = String(cString: sqlite3_column_text(stmt, 1))
                let statement = String(cString: sqlite3_column_text(stmt, 2))
                let status = String(cString: sqlite3_column_text(stmt, 3))
                let test = sqlite3_column_text(stmt, 4) != nil ? String(cString: sqlite3_column_text(stmt, 4)) : ""
                let findings = sqlite3_column_text(stmt, 5) != nil ? String(cString: sqlite3_column_text(stmt, 5)) : ""
                let ts = sqlite3_column_double(stmt, 6)

                results.append(HypothesisRecord(
                    id: id,
                    investigationId: invId,
                    statement: statement,
                    status: status,
                    proposedTest: test,
                    findings: findings,
                    updatedAt: ts
                ))
            }
            return results
        }
    }

    public func delete(id: String) throws {
        let sql = "DELETE FROM investigation_hypotheses WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }
}

// MARK: - Action Item Repository

public final class ActionItemRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(_ item: ActionItemRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO investigation_action_items (
            id, investigation_id, title, phase, is_completed, assignee, completed_at, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (item.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (item.investigationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (item.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (item.phase as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 5, item.isCompleted ? 1 : 0)
            if let ass = item.assignee {
                sqlite3_bind_text(stmt, 6, (ass as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let compAt = item.completedAt {
                sqlite3_bind_double(stmt, 7, compAt)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_text(stmt, 8, (item.notes as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetch(forInvestigationId investigationId: String) throws -> [ActionItemRecord] {
        let sql = """
        SELECT id, investigation_id, title, phase, is_completed, assignee, completed_at, notes
        FROM investigation_action_items WHERE investigation_id = ? ORDER BY is_completed ASC, rowid ASC;
        """
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (investigationId as NSString).utf8String, -1, nil)

            var results: [ActionItemRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let invId = String(cString: sqlite3_column_text(stmt, 1))
                let title = String(cString: sqlite3_column_text(stmt, 2))
                let phase = String(cString: sqlite3_column_text(stmt, 3))
                let isComp = sqlite3_column_int(stmt, 4) == 1
                let assignee = sqlite3_column_text(stmt, 5) != nil ? String(cString: sqlite3_column_text(stmt, 5)) : nil
                let compAt = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? sqlite3_column_double(stmt, 6) : nil
                let notes = sqlite3_column_text(stmt, 7) != nil ? String(cString: sqlite3_column_text(stmt, 7)) : ""

                results.append(ActionItemRecord(
                    id: id,
                    investigationId: invId,
                    title: title,
                    phase: phase,
                    isCompleted: isComp,
                    assignee: assignee,
                    completedAt: compAt,
                    notes: notes
                ))
            }
            return results
        }
    }

    public func toggleCompleted(id: String, isCompleted: Bool) throws {
        let now = isCompleted ? Date().timeIntervalSince1970 : nil
        let sql = "UPDATE investigation_action_items SET is_completed = ?, completed_at = ? WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, isCompleted ? 1 : 0)
            if let ts = now {
                sqlite3_bind_double(stmt, 2, ts)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func delete(id: String) throws {
        let sql = "DELETE FROM investigation_action_items WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }
}

// MARK: - RCA Repository

public final class RCARepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insertOrUpdate(_ rca: InvestigationRCARecord) throws {
        let sql = """
        INSERT OR REPLACE INTO investigation_rca (
            id, investigation_id, problem_statement, why1, why2, why3, why4, why5, root_cause, preventative_strategy
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (rca.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (rca.investigationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (rca.problemStatement as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (rca.why1 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (rca.why2 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (rca.why3 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 7, (rca.why4 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 8, (rca.why5 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 9, (rca.rootCause as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 10, (rca.preventativeStrategy as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetch(forInvestigationId investigationId: String) throws -> InvestigationRCARecord? {
        let sql = """
        SELECT id, investigation_id, problem_statement, why1, why2, why3, why4, why5, root_cause, preventative_strategy
        FROM investigation_rca WHERE investigation_id = ? LIMIT 1;
        """
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (investigationId as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let invId = String(cString: sqlite3_column_text(stmt, 1))
                let ps = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : ""
                let w1 = sqlite3_column_text(stmt, 3) != nil ? String(cString: sqlite3_column_text(stmt, 3)) : ""
                let w2 = sqlite3_column_text(stmt, 4) != nil ? String(cString: sqlite3_column_text(stmt, 4)) : ""
                let w3 = sqlite3_column_text(stmt, 5) != nil ? String(cString: sqlite3_column_text(stmt, 5)) : ""
                let w4 = sqlite3_column_text(stmt, 6) != nil ? String(cString: sqlite3_column_text(stmt, 6)) : ""
                let w5 = sqlite3_column_text(stmt, 7) != nil ? String(cString: sqlite3_column_text(stmt, 7)) : ""
                let rc = sqlite3_column_text(stmt, 8) != nil ? String(cString: sqlite3_column_text(stmt, 8)) : ""
                let prev = sqlite3_column_text(stmt, 9) != nil ? String(cString: sqlite3_column_text(stmt, 9)) : ""

                return InvestigationRCARecord(
                    id: id,
                    investigationId: invId,
                    problemStatement: ps,
                    why1: w1,
                    why2: w2,
                    why3: w3,
                    why4: w4,
                    why5: w5,
                    rootCause: rc,
                    preventativeStrategy: prev
                )
            }
            return nil
        }
    }
}

// MARK: - Diagnostic History Repository

public final class DiagnosticHistoryRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func record(_ item: DiagnosticHistoryRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO diagnostic_history (id, target, target_type, timestamp, dns_healthy, ping_latency, packet_loss, tcp_healthy, tls_healthy, http_status, summary, raw_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (item.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (item.target as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (item.targetType as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 4, item.timestamp)
            sqlite3_bind_int(stmt, 5, item.dnsHealthy ? 1 : 0)
            if let lat = item.pingLatency {
                sqlite3_bind_double(stmt, 6, lat)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let loss = item.packetLoss {
                sqlite3_bind_double(stmt, 7, loss)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_int(stmt, 8, item.tcpHealthy ? 1 : 0)
            sqlite3_bind_int(stmt, 9, item.tlsHealthy ? 1 : 0)
            if let st = item.httpStatus {
                sqlite3_bind_int(stmt, 10, Int32(st))
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            sqlite3_bind_text(stmt, 11, (item.summary as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 12, (item.rawJson as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetchRecent(limit: Int = 50) throws -> [DiagnosticHistoryRecord] {
        let sql = "SELECT id, target, target_type, timestamp, dns_healthy, ping_latency, packet_loss, tcp_healthy, tls_healthy, http_status, summary, raw_json FROM diagnostic_history ORDER BY timestamp DESC LIMIT ?;"
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            var results: [DiagnosticHistoryRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let target = String(cString: sqlite3_column_text(stmt, 1))
                let targetType = String(cString: sqlite3_column_text(stmt, 2))
                let ts = sqlite3_column_double(stmt, 3)
                let dns = sqlite3_column_int(stmt, 4) == 1
                let ping = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? sqlite3_column_double(stmt, 5) : nil
                let loss = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? sqlite3_column_double(stmt, 6) : nil
                let tcp = sqlite3_column_int(stmt, 7) == 1
                let tls = sqlite3_column_int(stmt, 8) == 1
                let http = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 9)) : nil
                let summary = String(cString: sqlite3_column_text(stmt, 10))
                let json = String(cString: sqlite3_column_text(stmt, 11))

                results.append(DiagnosticHistoryRecord(
                    id: id,
                    target: target,
                    targetType: targetType,
                    timestamp: ts,
                    dnsHealthy: dns,
                    pingLatency: ping,
                    packetLoss: loss,
                    tcpHealthy: tcp,
                    tlsHealthy: tls,
                    httpStatus: http,
                    summary: summary,
                    rawJson: json
                ))
            }
            return results
        }
    }

    public func delete(id: String) throws {
        let sql = "DELETE FROM diagnostic_history WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func deleteOlderThan(days: Int) throws {
        let cutoff = Date().addingTimeInterval(-Double(days * 86400)).timeIntervalSince1970
        let sql = "DELETE FROM diagnostic_history WHERE timestamp < ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, cutoff)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func clearAll() throws {
        try db.withLock {
            try db.execute(sql: "DELETE FROM diagnostic_history;")
        }
    }

    public func fetchTotalCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM diagnostic_history;"
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    public func seedDemoHistoryIfEmpty() throws {
        let count = try fetchTotalCount()
        guard count == 0 else { return }

        let now = Date().timeIntervalSince1970
        let demoRecords: [DiagnosticHistoryRecord] = [
            DiagnosticHistoryRecord(
                id: "demo-hist-1",
                target: "10.0.0.1",
                targetType: "IPv4 Address",
                timestamp: now - 300,
                dnsHealthy: true,
                pingLatency: 1.2,
                packetLoss: 0.0,
                tcpHealthy: true,
                tlsHealthy: true,
                httpStatus: nil,
                summary: "Core DC spine gateway operational. Normal RTT latency.",
                rawJson: """
                {
                  "target": "10.0.0.1",
                  "overallStatus": "Healthy",
                  "executionDurationMs": 14.5,
                  "latency": { "medianMs": 1.2, "minMs": 0.9, "maxMs": 1.8, "lossPercentage": 0.0, "jitterMs": 0.3 },
                  "tcp": { "isSuccess": true, "port": 22, "latencyMs": 1.4 }
                }
                """
            ),
            DiagnosticHistoryRecord(
                id: "demo-hist-2",
                target: "api.cloudflare.com",
                targetType: "Hostname",
                timestamp: now - 1800,
                dnsHealthy: true,
                pingLatency: 12.8,
                packetLoss: 0.0,
                tcpHealthy: true,
                tlsHealthy: true,
                httpStatus: 200,
                summary: "Public API edge reachable. TLS 1.3 negotiated with valid cert.",
                rawJson: """
                {
                  "target": "api.cloudflare.com",
                  "overallStatus": "Healthy",
                  "executionDurationMs": 48.2,
                  "dns": { "isHealthy": true, "latencyMs": 8.4, "addresses": ["104.16.132.229", "104.16.133.229"] },
                  "latency": { "medianMs": 12.8, "minMs": 11.2, "maxMs": 14.1, "lossPercentage": 0.0, "jitterMs": 0.9 },
                  "tcp": { "isSuccess": true, "port": 443, "latencyMs": 13.1 },
                  "http": { "statusCode": 200, "ttfbMs": 28.5, "tlsVersion": "TLSv1.3", "cipherSuite": "TLS_AES_128_GCM_SHA256" }
                }
                """
            ),
            DiagnosticHistoryRecord(
                id: "demo-hist-3",
                target: "192.168.100.1",
                targetType: "IPv4 Address",
                timestamp: now - 3600,
                dnsHealthy: true,
                pingLatency: 84.6,
                packetLoss: 8.0,
                tcpHealthy: true,
                tlsHealthy: false,
                httpStatus: 503,
                summary: "Branch lab router degraded. High RTT and 8% packet loss detected.",
                rawJson: """
                {
                  "target": "192.168.100.1",
                  "overallStatus": "Degraded",
                  "executionDurationMs": 182.0,
                  "latency": { "medianMs": 84.6, "minMs": 42.1, "maxMs": 146.5, "lossPercentage": 8.0, "jitterMs": 22.4 },
                  "tcp": { "isSuccess": true, "port": 443, "latencyMs": 88.0 },
                  "http": { "statusCode": 503, "ttfbMs": 120.0, "tlsVersion": "TLSv1.2", "cipherSuite": "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384" }
                }
                """
            ),
            DiagnosticHistoryRecord(
                id: "demo-hist-4",
                target: "legacy-auth.internal",
                targetType: "Hostname",
                timestamp: now - 7200,
                dnsHealthy: false,
                pingLatency: nil,
                packetLoss: 100.0,
                tcpHealthy: false,
                tlsHealthy: false,
                httpStatus: nil,
                summary: "DNS resolution failed. NXDOMAIN returned by upstream server.",
                rawJson: """
                {
                  "target": "legacy-auth.internal",
                  "overallStatus": "Unreachable",
                  "executionDurationMs": 210.0,
                  "dns": { "isHealthy": false, "latencyMs": 200.0, "addresses": [] }
                }
                """
            )
        ]

        for rec in demoRecords {
            try record(rec)
        }
    }
}

// MARK: - Site Environment Repository

public final class EnvironmentRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(_ record: EnvironmentRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO site_environments (
            id, name, environment_type, gateway_ip, subnet_cidr, primary_dns,
            secondary_dns, vlan_range, runbook_notes, is_active, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (record.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (record.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (record.environmentType as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (record.gatewayIP as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (record.subnetCIDR as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (record.primaryDNS as NSString).utf8String, -1, nil)
            if let sec = record.secondaryDNS {
                sqlite3_bind_text(stmt, 7, (sec as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_text(stmt, 8, (record.vlanRange as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 9, (record.runbookNotes as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 10, record.isActive ? 1 : 0)
            sqlite3_bind_double(stmt, 11, record.createdAt)
            sqlite3_bind_double(stmt, 12, record.updatedAt)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func update(_ record: EnvironmentRecord) throws {
        try insert(record)
    }

    public func delete(id: String) throws {
        let sql = "DELETE FROM site_environments WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetchAll() throws -> [EnvironmentRecord] {
        let sql = """
        SELECT id, name, environment_type, gateway_ip, subnet_cidr, primary_dns,
               secondary_dns, vlan_range, runbook_notes, is_active, created_at, updated_at
        FROM site_environments ORDER BY is_active DESC, name ASC;
        """
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [EnvironmentRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let name = String(cString: sqlite3_column_text(stmt, 1))
                let envType = String(cString: sqlite3_column_text(stmt, 2))
                let gw = String(cString: sqlite3_column_text(stmt, 3))
                let cidr = String(cString: sqlite3_column_text(stmt, 4))
                let priDNS = String(cString: sqlite3_column_text(stmt, 5))
                let secDNS = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 6)) : nil
                let vlan = String(cString: sqlite3_column_text(stmt, 7))
                let runbook = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 8)) : ""
                let active = sqlite3_column_int(stmt, 9) == 1
                let created = sqlite3_column_double(stmt, 10)
                let updated = sqlite3_column_double(stmt, 11)

                results.append(EnvironmentRecord(
                    id: id,
                    name: name,
                    environmentType: envType,
                    gatewayIP: gw,
                    subnetCIDR: cidr,
                    primaryDNS: priDNS,
                    secondaryDNS: secDNS,
                    vlanRange: vlan,
                    runbookNotes: runbook,
                    isActive: active,
                    createdAt: created,
                    updatedAt: updated
                ))
            }
            return results
        }
    }

    public func fetchActive() throws -> EnvironmentRecord? {
        let all = try fetchAll()
        return all.first { $0.isActive } ?? all.first
    }

    public func setActive(id: String) throws {
        try db.withLock {
            try db.execute(sql: "UPDATE site_environments SET is_active = 0;")
            let sql = "UPDATE site_environments SET is_active = 1 WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func seedDefaultsIfEmpty() throws {
        let existing = try fetchAll()
        guard existing.isEmpty else { return }

        let defaults: [EnvironmentRecord] = [
            EnvironmentRecord(
                id: "env-dc-sanjose",
                name: "San Jose HQ - DC Core",
                environmentType: "datacenter",
                gatewayIP: "10.0.0.1",
                subnetCIDR: "10.0.0.0/24",
                primaryDNS: "1.1.1.1",
                secondaryDNS: "8.8.8.8",
                vlanRange: "10 - 50",
                runbookNotes: "Primary corporate DC spine-leaf fabric.\nTier 3 redundancy with BGP EVPN/VXLAN.\nDual upstream transit providers.",
                isActive: true
            ),
            EnvironmentRecord(
                id: "env-branch-austin",
                name: "Austin Branch Office",
                environmentType: "branch",
                gatewayIP: "192.168.1.1",
                subnetCIDR: "192.168.1.0/24",
                primaryDNS: "8.8.8.8",
                secondaryDNS: "1.0.0.1",
                vlanRange: "100 - 150",
                runbookNotes: "Regional sales office with SD-WAN edge.\nLocal guest WiFi and PoE voice infrastructure.",
                isActive: false
            ),
            EnvironmentRecord(
                id: "env-cloud-aws-transit",
                name: "AWS US-East VPC Transit",
                environmentType: "cloud",
                gatewayIP: "172.16.0.1",
                subnetCIDR: "172.16.0.0/20",
                primaryDNS: "172.16.0.2",
                secondaryDNS: "1.1.1.1",
                vlanRange: "N/A (VXLAN)",
                runbookNotes: "Cloud transit gateway interconnecting DirectConnect and SD-WAN virtual routers.",
                isActive: false
            )
        ]

        for env in defaults {
            try insert(env)
        }
    }
}

// MARK: - Custom Command Repository

public final class CustomCommandRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(_ record: CustomCommandRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO custom_commands (
            id, intent, category, vendor, syntax, description, is_favorite, is_custom, parameters_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (record.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (record.intent as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (record.category as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (record.vendor as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (record.syntax as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (record.description as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 7, record.isFavorite ? 1 : 0)
            sqlite3_bind_int(stmt, 8, record.isCustom ? 1 : 0)
            if let params = record.parametersJSON {
                sqlite3_bind_text(stmt, 9, (params as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            sqlite3_bind_double(stmt, 10, record.createdAt)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func delete(id: String) throws {
        let sql = "DELETE FROM custom_commands WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetchAll() throws -> [CustomCommandRecord] {
        let sql = """
        SELECT id, intent, category, vendor, syntax, description, is_favorite, is_custom, parameters_json, created_at
        FROM custom_commands ORDER BY is_favorite DESC, created_at DESC;
        """
        return try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [CustomCommandRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let intent = String(cString: sqlite3_column_text(stmt, 1))
                let category = String(cString: sqlite3_column_text(stmt, 2))
                let vendor = String(cString: sqlite3_column_text(stmt, 3))
                let syntax = String(cString: sqlite3_column_text(stmt, 4))
                let desc = sqlite3_column_type(stmt, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 5)) : ""
                let isFav = sqlite3_column_int(stmt, 6) == 1
                let isCust = sqlite3_column_int(stmt, 7) == 1
                let paramsJSON = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 8)) : nil
                let created = sqlite3_column_double(stmt, 9)

                results.append(CustomCommandRecord(
                    id: id,
                    intent: intent,
                    category: category,
                    vendor: vendor,
                    syntax: syntax,
                    description: desc,
                    isFavorite: isFav,
                    isCustom: isCust,
                    parametersJSON: paramsJSON,
                    createdAt: created
                ))
            }
            return results
        }
    }

    public func toggleFavorite(id: String) throws {
        let sql = "UPDATE custom_commands SET is_favorite = ((is_favorite == 0)) WHERE id = ?;"
        try db.withLock {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db.rawHandle, sql, -1, &stmt, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetchFavorites() throws -> [CustomCommandRecord] {
        let all = try fetchAll()
        return all.filter { $0.isFavorite }
    }
}

