import Foundation
import SQLite3
import PersistenceKit

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class TimeSeriesRepository: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func insert(sample: LatencySample) throws {
        try database.withLock {
            let sql = """
            INSERT INTO target_monitor_series (id, target, timestamp, latency_ms, is_timeout, jitter_ms)
            VALUES (?, ?, ?, ?, ?, ?);
            """
            let stmt = try database.prepare(sql: sql)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, sample.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sample.target, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, sample.timestamp.timeIntervalSince1970)

            if let lat = sample.latencyMs {
                sqlite3_bind_double(stmt, 4, lat)
            } else {
                sqlite3_bind_null(stmt, 4)
            }

            sqlite3_bind_int(stmt, 5, sample.isTimeout ? 1 : 0)

            if let jit = sample.jitterMs {
                sqlite3_bind_double(stmt, 6, jit)
            } else {
                sqlite3_bind_null(stmt, 6)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed("Failed to insert target monitor sample.")
            }
        }
    }

    public func insertBatch(samples: [LatencySample]) throws {
        guard !samples.isEmpty else { return }
        try database.withLock {
            try database.execute(sql: "BEGIN TRANSACTION;")
            do {
                let sql = """
                INSERT INTO target_monitor_series (id, target, timestamp, latency_ms, is_timeout, jitter_ms)
                VALUES (?, ?, ?, ?, ?, ?);
                """
                let stmt = try database.prepare(sql: sql)
                defer { sqlite3_finalize(stmt) }

                for sample in samples {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)

                    sqlite3_bind_text(stmt, 1, sample.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, sample.target, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(stmt, 3, sample.timestamp.timeIntervalSince1970)

                    if let lat = sample.latencyMs {
                        sqlite3_bind_double(stmt, 4, lat)
                    } else {
                        sqlite3_bind_null(stmt, 4)
                    }

                    sqlite3_bind_int(stmt, 5, sample.isTimeout ? 1 : 0)

                    if let jit = sample.jitterMs {
                        sqlite3_bind_double(stmt, 6, jit)
                    } else {
                        sqlite3_bind_null(stmt, 6)
                    }

                    if sqlite3_step(stmt) != SQLITE_DONE {
                        let errMsg = database.rawHandle != nil ? String(cString: sqlite3_errmsg(database.rawHandle)) : "Unknown"
                        throw DatabaseError.stepFailed("Failed to batch insert sample: \(errMsg)")
                    }
                }
                try database.execute(sql: "COMMIT;")
            } catch {
                try? database.execute(sql: "ROLLBACK;")
                throw error
            }
        }
    }

    public func fetchRaw(target: String, from: Date, to: Date) throws -> [LatencySample] {
        return try database.withLock {
            let sql = """
            SELECT id, target, timestamp, latency_ms, is_timeout, jitter_ms
            FROM target_monitor_series
            WHERE target = ? AND timestamp >= ? AND timestamp <= ?
            ORDER BY timestamp ASC;
            """
            let stmt = try database.prepare(sql: sql)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, target, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, to.timeIntervalSince1970)

            var results: [LatencySample] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idStr = String(cString: sqlite3_column_text(stmt, 0))
                let id = UUID(uuidString: idStr) ?? UUID()
                let tgt = String(cString: sqlite3_column_text(stmt, 1))
                let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))

                let lat: Double?
                if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                    lat = sqlite3_column_double(stmt, 3)
                } else {
                    lat = nil
                }

                let isTimeout = sqlite3_column_int(stmt, 4) == 1

                let jit: Double?
                if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                    jit = sqlite3_column_double(stmt, 5)
                } else {
                    jit = nil
                }

                results.append(LatencySample(
                    id: id,
                    target: tgt,
                    timestamp: ts,
                    latencyMs: lat,
                    isTimeout: isTimeout,
                    jitterMs: jit
                ))
            }
            return results
        }
    }

    /// Fetches time-downsampled statistical buckets for smooth 60 FPS rendering
    public func fetchBuckets(target: String, from: Date, to: Date, bucketCount: Int) throws -> [AggregatedBucket] {
        let rawSamples = try fetchRaw(target: target, from: from, to: to)
        return downsample(samples: rawSamples, from: from, to: to, bucketCount: max(10, bucketCount))
    }

    public func downsample(samples: [LatencySample], from: Date, to: Date, bucketCount: Int) -> [AggregatedBucket] {
        guard !samples.isEmpty, to > from, bucketCount > 0 else { return [] }

        let totalDuration = to.timeIntervalSince(from)
        let bucketDuration = totalDuration / Double(bucketCount)
        var buckets: [AggregatedBucket] = []

        for i in 0..<bucketCount {
            let bucketStart = from.addingTimeInterval(Double(i) * bucketDuration)
            let bucketEnd = bucketStart.addingTimeInterval(bucketDuration)

            let inBucket = samples.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }
            if inBucket.isEmpty {
                continue
            }

            let validLatencies = inBucket.compactMap { $0.latencyMs }
            let timeoutCount = inBucket.filter { $0.isTimeout || $0.latencyMs == nil }.count
            let lossPct = (Double(timeoutCount) / Double(inBucket.count)) * 100.0

            let minVal = validLatencies.min() ?? 0.0
            let maxVal = validLatencies.max() ?? 0.0
            let avgVal = validLatencies.isEmpty ? 0.0 : validLatencies.reduce(0, +) / Double(validLatencies.count)
            let jitterVal = computeRFC3550Jitter(validLatencies)

            buckets.append(AggregatedBucket(
                timestamp: bucketStart.addingTimeInterval(bucketDuration / 2),
                minMs: minVal,
                avgMs: avgVal,
                maxMs: maxVal,
                jitterMs: jitterVal,
                packetLossPct: lossPct,
                sampleCount: inBucket.count
            ))
        }

        return buckets
    }

    private func computeRFC3550Jitter(_ samples: [Double]) -> Double {
        guard samples.count >= 2 else { return 0.0 }
        var j: Double = 0.0
        for i in 1..<samples.count {
            let diff = abs(samples[i] - samples[i - 1])
            j = j + (diff - j) / 16.0
        }
        return j
    }

    // MARK: - SLA Alerts

    public func recordAlert(alert: SLAMonitorAlert) throws {
        try database.withLock {
            let sql = """
            INSERT INTO monitor_sla_alerts (id, target, target_name, timestamp, alert_type, measured_value, threshold_value, message, is_acknowledged)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let stmt = try database.prepare(sql: sql)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, alert.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, alert.target, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, alert.targetName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, alert.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 5, alert.alertType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 6, alert.measuredValue)
            sqlite3_bind_double(stmt, 7, alert.thresholdValue)
            sqlite3_bind_text(stmt, 8, alert.message, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 9, alert.isAcknowledged ? 1 : 0)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw DatabaseError.stepFailed("Failed to insert monitor SLA alert.")
            }
        }
    }

    public func fetchAlerts(target: String? = nil, limit: Int = 50) throws -> [SLAMonitorAlert] {
        return try database.withLock {
            let sql: String
            if let _ = target {
                sql = """
                SELECT id, target, target_name, timestamp, alert_type, measured_value, threshold_value, message, is_acknowledged
                FROM monitor_sla_alerts
                WHERE target = ?
                ORDER BY timestamp DESC
                LIMIT ?;
                """
            } else {
                sql = """
                SELECT id, target, target_name, timestamp, alert_type, measured_value, threshold_value, message, is_acknowledged
                FROM monitor_sla_alerts
                ORDER BY timestamp DESC
                LIMIT ?;
                """
            }

            let stmt = try database.prepare(sql: sql)
            defer { sqlite3_finalize(stmt) }

            if let target = target {
                sqlite3_bind_text(stmt, 1, target, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }

            var alerts: [SLAMonitorAlert] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idStr = String(cString: sqlite3_column_text(stmt, 0))
                let id = UUID(uuidString: idStr) ?? UUID()
                let tgt = String(cString: sqlite3_column_text(stmt, 1))
                let name = String(cString: sqlite3_column_text(stmt, 2))
                let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
                let typeStr = String(cString: sqlite3_column_text(stmt, 4))
                let alertType = SLAAlertType(rawValue: typeStr) ?? .latencySpike
                let measured = sqlite3_column_double(stmt, 5)
                let threshold = sqlite3_column_double(stmt, 6)
                let msg = String(cString: sqlite3_column_text(stmt, 7))
                let isAck = sqlite3_column_int(stmt, 8) == 1

                alerts.append(SLAMonitorAlert(
                    id: id,
                    target: tgt,
                    targetName: name,
                    timestamp: ts,
                    alertType: alertType,
                    measuredValue: measured,
                    thresholdValue: threshold,
                    message: msg,
                    isAcknowledged: isAck
                ))
            }
            return alerts
        }
    }

    public func pruneOldSamples(olderThanDays: Int = 7) throws {
        try database.withLock {
            let cutoff = Date().addingTimeInterval(-Double(olderThanDays * 86400)).timeIntervalSince1970
            let sql = "DELETE FROM target_monitor_series WHERE timestamp < ?;"
            let stmt = try database.prepare(sql: sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, cutoff)
            _ = sqlite3_step(stmt)
        }
    }
}
