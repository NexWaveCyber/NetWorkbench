import Foundation
import SQLite3
import PersistenceKit
import NetworkCore

public enum DeviceManagerError: Error, LocalizedError {
    case deviceNotFound
    case databaseError(String)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Device was not found."
        case .databaseError(let msg): return "Database error: \(msg)"
        case .invalidData: return "Invalid device or baseline data."
        }
    }
}

/// Actor and thread-safe manager for device inventories and performance baselines.
public final class DeviceManager: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let lock = NSLock()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    // MARK: - Device CRUD Operations

    public func createDevice(_ device: NetworkDevice) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        INSERT INTO devices (
            id, display_name, hostname, management_ip, mac_address, vendor, role,
            platform, model, site, environment_id, tags, status,
            credential_ref, snmp_community, snmp_port, snmp_version, last_seen
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (device.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (device.displayName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (device.hostname as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (device.managementIP as NSString).utf8String, -1, nil)

        if let mac = device.macAddress {
            sqlite3_bind_text(stmt, 5, (mac as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 5) }

        sqlite3_bind_text(stmt, 6, (device.vendor.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (device.role.rawValue as NSString).utf8String, -1, nil)

        if let plat = device.platform {
            sqlite3_bind_text(stmt, 8, (plat as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 8) }

        if let mdl = device.model {
            sqlite3_bind_text(stmt, 9, (mdl as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 9) }

        if let ste = device.site {
            sqlite3_bind_text(stmt, 10, (ste as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 10) }

        if let env = device.environmentId {
            sqlite3_bind_text(stmt, 11, (env as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 11) }

        let tagsJoined = device.tags.joined(separator: ",")
        sqlite3_bind_text(stmt, 12, (tagsJoined as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 13, (device.status.rawValue as NSString).utf8String, -1, nil)

        if let cred = device.credentialRef {
            sqlite3_bind_text(stmt, 14, (cred.uuidString as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 14) }

        if let snmp = device.snmpConfig {
            sqlite3_bind_text(stmt, 15, (snmp.community as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 16, Int32(snmp.port))
            sqlite3_bind_text(stmt, 17, (snmp.version as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 15)
            sqlite3_bind_null(stmt, 16)
            sqlite3_bind_null(stmt, 17)
        }

        if let lastSeen = device.lastSeen {
            sqlite3_bind_double(stmt, 18, lastSeen.timeIntervalSince1970)
        } else { sqlite3_bind_null(stmt, 18) }

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(database.rawHandle))
            throw DeviceManagerError.databaseError("Failed to insert device: \(err)")
        }
    }

    public func listDevices() throws -> [NetworkDevice] {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT id, display_name, hostname, management_ip, mac_address, vendor, role,
               platform, model, site, environment_id, tags, status,
               credential_ref, snmp_community, snmp_port, snmp_version, last_seen
        FROM devices ORDER BY display_name ASC;
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        var devices: [NetworkDevice] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let dev = parseDevice(from: stmt) {
                devices.append(dev)
            }
        }
        return devices
    }

    public func updateDevice(_ device: NetworkDevice) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        UPDATE devices SET
            display_name = ?, hostname = ?, management_ip = ?, mac_address = ?, vendor = ?, role = ?,
            platform = ?, model = ?, site = ?, environment_id = ?, tags = ?, status = ?,
            credential_ref = ?, snmp_community = ?, snmp_port = ?, snmp_version = ?, last_seen = ?
        WHERE id = ?;
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (device.displayName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (device.hostname as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (device.managementIP as NSString).utf8String, -1, nil)

        if let mac = device.macAddress {
            sqlite3_bind_text(stmt, 4, (mac as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 4) }

        sqlite3_bind_text(stmt, 5, (device.vendor.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (device.role.rawValue as NSString).utf8String, -1, nil)

        if let plat = device.platform {
            sqlite3_bind_text(stmt, 7, (plat as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 7) }

        if let mdl = device.model {
            sqlite3_bind_text(stmt, 8, (mdl as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 8) }

        if let ste = device.site {
            sqlite3_bind_text(stmt, 9, (ste as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 9) }

        if let env = device.environmentId {
            sqlite3_bind_text(stmt, 10, (env as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 10) }

        let tagsJoined = device.tags.joined(separator: ",")
        sqlite3_bind_text(stmt, 11, (tagsJoined as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 12, (device.status.rawValue as NSString).utf8String, -1, nil)

        if let cred = device.credentialRef {
            sqlite3_bind_text(stmt, 13, (cred.uuidString as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 13) }

        if let snmp = device.snmpConfig {
            sqlite3_bind_text(stmt, 14, (snmp.community as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 15, Int32(snmp.port))
            sqlite3_bind_text(stmt, 16, (snmp.version as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 14)
            sqlite3_bind_null(stmt, 15)
            sqlite3_bind_null(stmt, 16)
        }

        if let lastSeen = device.lastSeen {
            sqlite3_bind_double(stmt, 17, lastSeen.timeIntervalSince1970)
        } else { sqlite3_bind_null(stmt, 17) }

        sqlite3_bind_text(stmt, 18, (device.id.uuidString as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(database.rawHandle))
            throw DeviceManagerError.databaseError("Failed to update device: \(err)")
        }
    }

    public func deleteDevice(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "DELETE FROM devices WHERE id = ?;"
        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(database.rawHandle))
            throw DeviceManagerError.databaseError("Failed to delete device: \(err)")
        }
    }

    public func getDevice(id: UUID) throws -> NetworkDevice? {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT id, display_name, hostname, management_ip, mac_address, vendor, role,
               platform, model, site, environment_id, tags, status,
               credential_ref, snmp_community, snmp_port, snmp_version, last_seen
        FROM devices WHERE id = ? LIMIT 1;
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseDevice(from: stmt)
        }
        return nil
    }

    public func saveDevice(_ device: NetworkDevice) throws {
        if (try? getDevice(id: device.id)) != nil {
            try updateDevice(device)
        } else {
            try createDevice(device)
        }
    }

    // MARK: - Baseline Operations

    public func saveBaseline(_ baseline: DeviceBaseline) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        INSERT INTO device_baselines (
            id, device_id, created_at, avg_latency_ms, packet_loss_pct, open_ports, snmp_sys_descr, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (baseline.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (baseline.deviceId.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, baseline.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, baseline.avgLatencyMs)
        sqlite3_bind_double(stmt, 5, baseline.packetLossPct)

        let portsStr = baseline.openPorts.map(String.init).joined(separator: ",")
        sqlite3_bind_text(stmt, 6, (portsStr as NSString).utf8String, -1, nil)

        if let descr = baseline.snmpSysDescr {
            sqlite3_bind_text(stmt, 7, (descr as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 7) }

        sqlite3_bind_text(stmt, 8, (baseline.notes as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(database.rawHandle))
            throw DeviceManagerError.databaseError("Failed to save baseline: \(err)")
        }
    }

    public func getLatestBaseline(forDeviceId deviceId: UUID) throws -> DeviceBaseline? {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT id, device_id, created_at, avg_latency_ms, packet_loss_pct, open_ports, snmp_sys_descr, notes
        FROM device_baselines WHERE device_id = ? ORDER BY created_at DESC LIMIT 1;
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (deviceId.uuidString as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseBaseline(from: stmt)
        }
        return nil
    }

    public func listBaselines(forDeviceId deviceId: UUID) throws -> [DeviceBaseline] {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT id, device_id, created_at, avg_latency_ms, packet_loss_pct, open_ports, snmp_sys_descr, notes
        FROM device_baselines WHERE device_id = ? ORDER BY created_at DESC;
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (deviceId.uuidString as NSString).utf8String, -1, nil)
        var baselines: [DeviceBaseline] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let b = parseBaseline(from: stmt) {
                baselines.append(b)
            }
        }
        return baselines
    }

    public func compareWithBaseline(
        currentLatency: Double,
        currentLoss: Double,
        currentOpenPorts: [Int],
        baseline: DeviceBaseline
    ) -> BaselineComparisonResult {
        let latDelta = currentLatency - baseline.avgLatencyMs
        let isLatDegraded = latDelta > 15.0 || (baseline.avgLatencyMs > 0 && latDelta / baseline.avgLatencyMs > 0.5)

        let lossDelta = currentLoss - baseline.packetLossPct
        let isLossDegraded = lossDelta > 1.0

        let baselinePortSet = Set(baseline.openPorts)
        let currentPortSet = Set(currentOpenPorts)

        let missing = Array(baselinePortSet.subtracting(currentPortSet)).sorted()
        let unexpected = Array(currentPortSet.subtracting(baselinePortSet)).sorted()

        var score = 100
        if isLatDegraded { score -= 25 }
        if isLossDegraded { score -= 35 }
        if !missing.isEmpty { score -= 20 }
        if !unexpected.isEmpty { score -= 10 }
        if score < 0 { score = 0 }

        return BaselineComparisonResult(
            latencyDeltaMs: latDelta,
            isLatencyDegraded: isLatDegraded,
            lossDeltaPct: lossDelta,
            isLossDegraded: isLossDegraded,
            missingPorts: missing,
            unexpectedPorts: unexpected,
            overallHealthScore: score
        )
    }

    // MARK: - Private Parsers

    private func parseDevice(from stmt: OpaquePointer) -> NetworkDevice? {
        guard let idStr = sqlite3_column_text(stmt, 0),
              let id = UUID(uuidString: String(cString: idStr)),
              let nameStr = sqlite3_column_text(stmt, 1),
              let hostStr = sqlite3_column_text(stmt, 2),
              let ipStr = sqlite3_column_text(stmt, 3) else {
            return nil
        }

        let displayName = String(cString: nameStr)
        let hostname = String(cString: hostStr)
        let managementIP = String(cString: ipStr)
        let macAddress = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

        let vendorStr = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "Generic"
        let vendor = DeviceVendor(rawValue: vendorStr) ?? .generic

        let roleStr = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "Switch"
        let role = DeviceRole(rawValue: roleStr) ?? .switchRole

        let platform = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
        let model = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let site = sqlite3_column_text(stmt, 9).map { String(cString: $0) }
        let envId = sqlite3_column_text(stmt, 10).map { String(cString: $0) }

        let tagsStr = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""
        let tags = tagsStr.isEmpty ? [] : tagsStr.components(separatedBy: ",")

        let statusStr = sqlite3_column_text(stmt, 12).map { String(cString: $0) } ?? "Unknown"
        let status = DeviceStatus(rawValue: statusStr) ?? .unknown

        let credRef = sqlite3_column_text(stmt, 13).flatMap { UUID(uuidString: String(cString: $0)) }

        var snmp: SNMPDeviceConfig? = nil
        if let communityCStr = sqlite3_column_text(stmt, 14) {
            let comm = String(cString: communityCStr)
            let port = Int(sqlite3_column_int(stmt, 15))
            let ver = sqlite3_column_text(stmt, 16).map { String(cString: $0) } ?? "v2c"
            snmp = SNMPDeviceConfig(community: comm, port: port == 0 ? 161 : port, version: ver)
        }

        var lastSeen: Date? = nil
        if sqlite3_column_type(stmt, 17) != SQLITE_NULL {
            lastSeen = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 17))
        }

        return NetworkDevice(
            id: id,
            displayName: displayName,
            hostname: hostname,
            managementIP: managementIP,
            macAddress: macAddress,
            vendor: vendor,
            role: role,
            platform: platform,
            model: model,
            site: site,
            environmentId: envId,
            tags: tags,
            status: status,
            credentialRef: credRef,
            snmpConfig: snmp,
            lastSeen: lastSeen
        )
    }

    private func parseBaseline(from stmt: OpaquePointer) -> DeviceBaseline? {
        guard let idStr = sqlite3_column_text(stmt, 0),
              let id = UUID(uuidString: String(cString: idStr)),
              let devIdStr = sqlite3_column_text(stmt, 1),
              let devId = UUID(uuidString: String(cString: devIdStr)) else {
            return nil
        }

        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let latency = sqlite3_column_double(stmt, 3)
        let loss = sqlite3_column_double(stmt, 4)

        let portsStr = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
        let ports = portsStr.split(separator: ",").compactMap { Int($0) }

        let descr = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let notes = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

        return DeviceBaseline(
            id: id,
            deviceId: devId,
            createdAt: createdAt,
            avgLatencyMs: latency,
            packetLossPct: loss,
            openPorts: ports,
            snmpSysDescr: descr,
            notes: notes
        )
    }
}
