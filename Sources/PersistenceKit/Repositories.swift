import Foundation
import SQLite3

public final class InvestigationRepository: Sendable {
    private let db: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.db = database
    }

    public func insert(_ record: InvestigationRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO investigations (id, title, description, environment_id, status, severity, created_at, updated_at, resolved_at, resolution)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db.rawHandle)))
            }
        }
    }

    public func fetchAll() throws -> [InvestigationRecord] {
        let sql = "SELECT id, title, description, environment_id, status, severity, created_at, updated_at, resolved_at, resolution FROM investigations ORDER BY updated_at DESC;"
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
                    resolution: res
                ))
            }
            return results
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
}
