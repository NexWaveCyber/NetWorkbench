import Foundation
import SQLite3
import NetworkCore

public enum DatabaseError: Error, LocalizedError {
    case connectionFailed(String)
    case executionFailed(String)
    case stepFailed(String)
    case prepareFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Database connection failed: \(msg)"
        case .executionFailed(let msg): return "SQL execution failed: \(msg)"
        case .stepFailed(let msg): return "SQL step failed: \(msg)"
        case .prepareFailed(let msg): return "SQL prepare statement failed: \(msg)"
        }
    }
}

/// Thread-safe SQLite database manager with WAL mode enabled.
public final class SQLiteDatabase: @unchecked Sendable {
    public let path: String
    private var db: OpaquePointer?
    private let internalLock = NSRecursiveLock()

    public init(path: String? = nil) throws {
        let dbPath: String
        if let path = path {
            dbPath = path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let dir = appSupport.appendingPathComponent("NexWave", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbPath = dir.appendingPathComponent("network_workbench.sqlite").path
        }
        self.path = dbPath

        var pointer: OpaquePointer?
        if sqlite3_open(dbPath, &pointer) != SQLITE_OK {
            let err = String(cString: sqlite3_errmsg(pointer))
            throw DatabaseError.connectionFailed(err)
        }
        self.db = pointer

        try configurePragmas()
        try runMigrations()
    }

    deinit {
        if let db = db {
            sqlite3_close_v2(db)
        }
    }

    private func configurePragmas() throws {
        try execute(sql: "PRAGMA journal_mode = WAL;")
        try execute(sql: "PRAGMA synchronous = NORMAL;")
        try execute(sql: "PRAGMA foreign_keys = ON;")
    }

    public func execute(sql: String) throws {
        internalLock.lock()
        defer { internalLock.unlock() }

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let err = errMsg != nil ? String(cString: errMsg!) : "Unknown error"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(err)
        }
    }

    public func prepare(sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let err = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(err)
        }
        guard let validStmt = stmt else {
            throw DatabaseError.prepareFailed("Failed to allocate SQLite statement pointer")
        }
        return validStmt
    }

    private func runMigrations() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS investigations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            environment_id TEXT,
            status TEXT NOT NULL,
            severity TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            resolved_at REAL,
            resolution TEXT
        );

        CREATE TABLE IF NOT EXISTS timeline_events (
            id TEXT PRIMARY KEY,
            investigation_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            title TEXT NOT NULL,
            detail TEXT,
            category TEXT NOT NULL,
            FOREIGN KEY (investigation_id) REFERENCES investigations(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS diagnostic_history (
            id TEXT PRIMARY KEY,
            target TEXT NOT NULL,
            target_type TEXT NOT NULL,
            timestamp REAL NOT NULL,
            dns_healthy INTEGER NOT NULL,
            ping_latency REAL,
            packet_loss REAL,
            tcp_healthy INTEGER NOT NULL,
            tls_healthy INTEGER NOT NULL,
            http_status INTEGER,
            summary TEXT NOT NULL,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS environments (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            hostname TEXT NOT NULL,
            management_ip TEXT NOT NULL,
            mac_address TEXT,
            vendor TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'switch',
            platform TEXT,
            model TEXT,
            site TEXT,
            environment_id TEXT,
            tags TEXT,
            status TEXT NOT NULL DEFAULT 'unknown',
            credential_ref TEXT,
            snmp_community TEXT,
            snmp_port INTEGER DEFAULT 161,
            snmp_version TEXT DEFAULT 'v2c',
            last_seen REAL
        );

        CREATE TABLE IF NOT EXISTS device_baselines (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            avg_latency_ms REAL,
            packet_loss_pct REAL,
            open_ports TEXT,
            snmp_sys_descr TEXT,
            notes TEXT,
            FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS target_monitor_series (
            id TEXT PRIMARY KEY,
            target TEXT NOT NULL,
            timestamp REAL NOT NULL,
            latency_ms REAL,
            is_timeout INTEGER NOT NULL DEFAULT 0,
            jitter_ms REAL
        );

        CREATE INDEX IF NOT EXISTS idx_monitor_target_time ON target_monitor_series(target, timestamp);

        CREATE TABLE IF NOT EXISTS monitor_sla_alerts (
            id TEXT PRIMARY KEY,
            target TEXT NOT NULL,
            target_name TEXT NOT NULL,
            timestamp REAL NOT NULL,
            alert_type TEXT NOT NULL,
            measured_value REAL NOT NULL,
            threshold_value REAL NOT NULL,
            message TEXT NOT NULL,
            is_acknowledged INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS monitor_targets (
            id TEXT PRIMARY KEY,
            target TEXT NOT NULL,
            name TEXT NOT NULL,
            interval_seconds REAL NOT NULL DEFAULT 2.5,
            latency_threshold_ms REAL NOT NULL DEFAULT 60.0,
            packet_loss_threshold_pct REAL NOT NULL DEFAULT 5.0,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            probe_protocol TEXT NOT NULL DEFAULT 'icmp',
            tcp_port INTEGER DEFAULT 443,
            created_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_monitor_targets_name ON monitor_targets(name);

        CREATE TABLE IF NOT EXISTS topology_node_positions (
            preset_id TEXT NOT NULL,
            node_id TEXT NOT NULL,
            x REAL NOT NULL,
            y REAL NOT NULL,
            PRIMARY KEY (preset_id, node_id)
        );

        CREATE TABLE IF NOT EXISTS evidence_items (
            id TEXT PRIMARY KEY,
            investigation_id TEXT NOT NULL,
            title TEXT NOT NULL,
            evidence_type TEXT NOT NULL,
            filename TEXT NOT NULL,
            sha256 TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            content TEXT NOT NULL,
            source_workbench TEXT NOT NULL,
            created_at REAL NOT NULL,
            notes TEXT,
            FOREIGN KEY (investigation_id) REFERENCES investigations(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS investigation_hypotheses (
            id TEXT PRIMARY KEY,
            investigation_id TEXT NOT NULL,
            statement TEXT NOT NULL,
            status TEXT NOT NULL,
            proposed_test TEXT,
            findings TEXT,
            updated_at REAL NOT NULL,
            FOREIGN KEY (investigation_id) REFERENCES investigations(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS investigation_action_items (
            id TEXT PRIMARY KEY,
            investigation_id TEXT NOT NULL,
            title TEXT NOT NULL,
            phase TEXT NOT NULL,
            is_completed INTEGER NOT NULL DEFAULT 0,
            assignee TEXT,
            completed_at REAL,
            notes TEXT,
            FOREIGN KEY (investigation_id) REFERENCES investigations(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS investigation_rca (
            id TEXT PRIMARY KEY,
            investigation_id TEXT NOT NULL UNIQUE,
            problem_statement TEXT,
            why1 TEXT,
            why2 TEXT,
            why3 TEXT,
            why4 TEXT,
            why5 TEXT,
            root_cause TEXT,
            preventative_strategy TEXT,
            FOREIGN KEY (investigation_id) REFERENCES investigations(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS site_environments (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            environment_type TEXT NOT NULL DEFAULT 'campus',
            gateway_ip TEXT NOT NULL,
            subnet_cidr TEXT NOT NULL,
            primary_dns TEXT NOT NULL DEFAULT '1.1.1.1',
            secondary_dns TEXT,
            vlan_range TEXT NOT NULL DEFAULT '1 - 100',
            runbook_notes TEXT,
            is_active INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS custom_commands (
            id TEXT PRIMARY KEY,
            intent TEXT NOT NULL,
            category TEXT NOT NULL,
            vendor TEXT NOT NULL,
            syntax TEXT NOT NULL,
            description TEXT,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            is_custom INTEGER NOT NULL DEFAULT 1,
            parameters_json TEXT,
            created_at REAL NOT NULL
        );
        """
        try execute(sql: schema)

        // Safe column additions for schema upgrades
        let alterStatements = [
            "ALTER TABLE devices ADD COLUMN mac_address TEXT;",
            "ALTER TABLE devices ADD COLUMN role TEXT NOT NULL DEFAULT 'switch';",
            "ALTER TABLE devices ADD COLUMN status TEXT NOT NULL DEFAULT 'unknown';",
            "ALTER TABLE devices ADD COLUMN snmp_community TEXT;",
            "ALTER TABLE devices ADD COLUMN snmp_port INTEGER DEFAULT 161;",
            "ALTER TABLE devices ADD COLUMN snmp_version TEXT DEFAULT 'v2c';",
            "ALTER TABLE devices ADD COLUMN last_seen REAL;",
            "ALTER TABLE investigations ADD COLUMN commander TEXT;",
            "ALTER TABLE investigations ADD COLUMN affected_services TEXT;",
            "ALTER TABLE investigations ADD COLUMN affected_devices TEXT;",
            "ALTER TABLE investigations ADD COLUMN blast_radius TEXT;",
            "ALTER TABLE investigations ADD COLUMN detected_at REAL;",
            "ALTER TABLE investigations ADD COLUMN mitigated_at REAL;",
            "ALTER TABLE investigations ADD COLUMN root_cause_category TEXT;",
            "ALTER TABLE investigations ADD COLUMN root_cause_summary TEXT;"
        ]
        for alter in alterStatements {
            _ = try? execute(sql: alter)
        }
    }

    public var rawHandle: OpaquePointer? {
        db
    }

    public func lock() {
        internalLock.lock()
    }

    public func unlock() {
        internalLock.unlock()
    }

    public func withLock<T>(_ block: () throws -> T) rethrows -> T {
        internalLock.lock()
        defer { internalLock.unlock() }
        return try block()
    }

    public func clearDiagnosticHistory() throws {
        try execute(sql: "DELETE FROM diagnostic_history;")
    }

    public func databaseFileSize() -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public func tableRowCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        let tables = ["investigations", "diagnostic_history", "timeline_events", "forensic_artifacts", "managed_devices", "custom_scripts"]
        for table in tables {
            do {
                let stmt = try prepare(sql: "SELECT COUNT(*) FROM \(table);")
                defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    counts[table] = Int(sqlite3_column_int(stmt, 0))
                }
            } catch {
                counts[table] = 0
            }
        }
        return counts
    }

    public func backupDatabase(to destinationURL: URL) throws {
        internalLock.lock()
        defer { internalLock.unlock() }

        var destDb: OpaquePointer?
        if sqlite3_open(destinationURL.path, &destDb) != SQLITE_OK {
            let err = destDb != nil ? String(cString: sqlite3_errmsg(destDb)) : "Unknown"
            throw DatabaseError.connectionFailed(err)
        }
        defer { sqlite3_close(destDb) }

        guard let backup = sqlite3_backup_init(destDb, "main", db, "main") else {
            let err = String(cString: sqlite3_errmsg(destDb))
            throw DatabaseError.executionFailed("Failed to initialize backup: \(err)")
        }

        sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
    }
}
