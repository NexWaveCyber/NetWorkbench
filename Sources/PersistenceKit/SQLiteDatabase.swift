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
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    public init(path: String? = nil) throws {
        let dbPath: String
        if let path = path {
            dbPath = path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("NexWave", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbPath = dir.appendingPathComponent("network_workbench.sqlite").path
        }

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
            sqlite3_close(db)
        }
    }

    private func configurePragmas() throws {
        try execute(sql: "PRAGMA journal_mode = WAL;")
        try execute(sql: "PRAGMA synchronous = NORMAL;")
        try execute(sql: "PRAGMA foreign_keys = ON;")
    }

    public func execute(sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

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
        return stmt!
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
        """
        try execute(sql: schema)

        // Safe column additions for schema upgrades
        let alterStatements = [
            "ALTER TABLE devices ADD COLUMN role TEXT NOT NULL DEFAULT 'switch';",
            "ALTER TABLE devices ADD COLUMN status TEXT NOT NULL DEFAULT 'unknown';",
            "ALTER TABLE devices ADD COLUMN snmp_community TEXT;",
            "ALTER TABLE devices ADD COLUMN snmp_port INTEGER DEFAULT 161;",
            "ALTER TABLE devices ADD COLUMN snmp_version TEXT DEFAULT 'v2c';",
            "ALTER TABLE devices ADD COLUMN last_seen REAL;"
        ]
        for alter in alterStatements {
            _ = try? execute(sql: alter)
        }
    }

    public var rawHandle: OpaquePointer? {
        db
    }

    public func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block()
    }
}
