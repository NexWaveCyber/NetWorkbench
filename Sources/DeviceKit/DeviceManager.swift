import Foundation
import SQLite3
import PersistenceKit
import NetworkCore
import CoreGraphics

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
    private var lock: SQLiteDatabase { database }

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

    public func getDevice(byIP ip: String) throws -> NetworkDevice? {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT id, display_name, hostname, management_ip, mac_address, vendor, role,
               platform, model, site, environment_id, tags, status,
               credential_ref, snmp_community, snmp_port, snmp_version, last_seen
        FROM devices WHERE management_ip = ? LIMIT 1;
        """

        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (ip as NSString).utf8String, -1, nil)
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

    // MARK: - Bulk Fleet Operations

    public func bulkDeleteDevices(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        try database.execute(sql: "BEGIN TRANSACTION;")
        defer {
            _ = try? database.execute(sql: "COMMIT;")
        }

        let sql = "DELETE FROM devices WHERE id = ?;"
        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        for id in ids {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
            _ = sqlite3_step(stmt)
        }
    }

    public func bulkAddTags(ids: [UUID], tags: [String]) throws {
        guard !ids.isEmpty, !tags.isEmpty else { return }
        let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }.filter { !$0.isEmpty }
        guard !cleanTags.isEmpty else { return }

        for id in ids {
            if var dev = try getDevice(id: id) {
                var currentTags = dev.tags
                for tag in cleanTags {
                    if !currentTags.contains(tag) {
                        currentTags.append(tag)
                    }
                }
                dev.tags = currentTags
                try updateDevice(dev)
            }
        }
    }

    public func bulkRemoveTags(ids: [UUID], tags: [String]) throws {
        guard !ids.isEmpty, !tags.isEmpty else { return }
        let tagsToRemove = Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) })

        for id in ids {
            if var dev = try getDevice(id: id) {
                dev.tags = dev.tags.filter { !tagsToRemove.contains($0) }
                try updateDevice(dev)
            }
        }
    }

    public func bulkAssignSite(ids: [UUID], site: String?) throws {
        guard !ids.isEmpty else { return }
        let trimmedSite = site?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSite = (trimmedSite?.isEmpty == false) ? trimmedSite : nil

        for id in ids {
            if var dev = try getDevice(id: id) {
                dev.site = finalSite
                try updateDevice(dev)
            }
        }
    }

    // MARK: - CSV and JSON Device Importers

    public static func parseCSV(content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        let chars = Array(content)
        var i = 0
        let count = chars.count

        while i < count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes && i + 1 < count && chars[i + 1] == "\"" {
                    currentField.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else if (ch == "\r" || ch == "\n") && !inQuotes {
                if ch == "\r" && i + 1 < count && chars[i + 1] == "\n" {
                    i += 1
                }
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
                if !currentRow.allSatisfy({ $0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
            } else {
                currentField.append(ch)
            }
            i += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }
        return rows
    }

    public func importDevicesFromCSV(content: String) throws -> DeviceImportResult {
        let rows = Self.parseCSV(content: content)
        guard rows.count > 1 else {
            return DeviceImportResult(totalProcessed: 0, addedCount: 0, updatedCount: 0, errors: ["CSV file is empty or contains only header."])
        }

        let headers = rows[0].map { $0.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "") }
        var nameIdx: Int?
        var ipIdx: Int?
        var macIdx: Int?
        var hostIdx: Int?
        var vendorIdx: Int?
        var roleIdx: Int?
        var platformIdx: Int?
        var modelIdx: Int?
        var siteIdx: Int?
        var tagsIdx: Int?
        var statusIdx: Int?
        var snmpCommIdx: Int?
        var snmpPortIdx: Int?
        var snmpVerIdx: Int?

        for (idx, h) in headers.enumerated() {
            if h == "name" || h == "displayname" || h == "devicename" { nameIdx = idx }
            else if h == "ip" || h == "ipaddress" || h == "managementip" || h == "hostip" { ipIdx = idx }
            else if h == "mac" || h == "macaddress" || h == "ethernet" { macIdx = idx }
            else if h == "host" || h == "hostname" || h == "fqdn" { hostIdx = idx }
            else if h == "vendor" || h == "manufacturer" || h == "make" { vendorIdx = idx }
            else if h == "role" || h == "type" || h == "devicetype" { roleIdx = idx }
            else if h == "platform" || h == "os" { platformIdx = idx }
            else if h == "model" || h == "hardware" { modelIdx = idx }
            else if h == "site" || h == "location" || h == "datacenter" { siteIdx = idx }
            else if h == "tags" || h == "labels" || h == "tag" { tagsIdx = idx }
            else if h == "status" || h == "state" { statusIdx = idx }
            else if h == "snmp" || h == "snmpcommunity" || h == "community" { snmpCommIdx = idx }
            else if h == "snmpport" || h == "port" { snmpPortIdx = idx }
            else if h == "snmpver" || h == "snmpversion" || h == "version" { snmpVerIdx = idx }
        }

        guard let targetIPIdx = ipIdx else {
            return DeviceImportResult(totalProcessed: 0, addedCount: 0, updatedCount: 0, errors: ["Missing required 'IP Address' or 'Management IP' column in header."])
        }

        var added = 0
        var updated = 0
        var errors: [String] = []

        for rowIdx in 1..<rows.count {
            let row = rows[rowIdx]
            guard row.count > targetIPIdx else { continue }
            let ip = row[targetIPIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ip.isEmpty else { continue }

            let rawName = nameIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hostname = hostIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ip
            let displayName = (rawName?.isEmpty == false ? rawName : nil) ?? hostname
            let mac = macIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanMAC = (mac?.isEmpty == false) ? mac : nil

            // Resolve Vendor
            let vendorStr = vendorIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var resolvedVendor = resolveVendorString(vendorStr)
            if resolvedVendor == .generic, let m = cleanMAC, let resolvedOUI = OUIResolver.lookup(mac: m) {
                resolvedVendor = resolveVendorString(resolvedOUI)
            }

            // Resolve Role
            let roleStr = roleIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var resolvedRole = resolveRoleString(roleStr)
            if roleStr.isEmpty {
                resolvedRole = inferRoleFromVendor(resolvedVendor)
            }

            let platform = platformIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = modelIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)
            let site = siteIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Resolve Tags
            let rawTags = tagsIdx.flatMap { idx in row.count > idx ? row[idx] : nil } ?? ""
            let parsedTags = rawTags.components(separatedBy: CharacterSet(charactersIn: ",; "))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                .filter { !$0.isEmpty }

            // Resolve Status
            let rawStatus = statusIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status: DeviceStatus
            switch rawStatus.lowercased() {
            case "online", "up", "active": status = .online
            case "offline", "down": status = .offline
            case "unresponsive": status = .unresponsive
            default: status = .unknown
            }

            // Resolve SNMP
            var snmpConfig: SNMPDeviceConfig? = nil
            if let commIdx = snmpCommIdx, row.count > commIdx, !row[commIdx].isEmpty {
                let comm = row[commIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let port = snmpPortIdx.flatMap { idx in row.count > idx ? Int(row[idx]) : nil } ?? 161
                let ver = snmpVerIdx.flatMap { idx in row.count > idx ? row[idx] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "v2c"
                snmpConfig = SNMPDeviceConfig(community: comm, port: port, version: ver)
            }

            do {
                if var existing = try getDevice(byIP: ip) {
                    existing.displayName = displayName
                    existing.hostname = hostname
                    if let m = cleanMAC { existing.macAddress = m }
                    if resolvedVendor != .generic { existing.vendor = resolvedVendor }
                    existing.role = resolvedRole
                    if let p = platform, !p.isEmpty { existing.platform = p }
                    if let m = model, !m.isEmpty { existing.model = m }
                    if let s = site, !s.isEmpty { existing.site = s }
                    for t in parsedTags where !existing.tags.contains(t) { existing.tags.append(t) }
                    if status != .unknown { existing.status = status }
                    if let snmp = snmpConfig { existing.snmpConfig = snmp }
                    try updateDevice(existing)
                    updated += 1
                } else {
                    let newDevice = NetworkDevice(
                        id: UUID(),
                        displayName: displayName,
                        hostname: hostname,
                        managementIP: ip,
                        macAddress: cleanMAC,
                        vendor: resolvedVendor,
                        role: resolvedRole,
                        platform: (platform?.isEmpty == false) ? platform : nil,
                        model: (model?.isEmpty == false) ? model : nil,
                        site: (site?.isEmpty == false) ? site : nil,
                        tags: parsedTags,
                        status: status,
                        snmpConfig: snmpConfig,
                        lastSeen: Date()
                    )
                    try createDevice(newDevice)
                    added += 1
                }
            } catch {
                errors.append("Row \(rowIdx) (\(ip)): \(error.localizedDescription)")
            }
        }

        return DeviceImportResult(totalProcessed: rows.count - 1, addedCount: added, updatedCount: updated, errors: errors)
    }

    public func importDevicesFromJSON(data: Data) throws -> DeviceImportResult {
        // First try standard NetworkDevice array
        if let devices = try? JSONDecoder().decode([NetworkDevice].self, from: data) {
            var added = 0
            var updated = 0
            var errors: [String] = []

            for dev in devices {
                do {
                    if let _ = try getDevice(id: dev.id) {
                        try updateDevice(dev)
                        updated += 1
                    } else if var existing = try getDevice(byIP: dev.managementIP) {
                        existing.displayName = dev.displayName
                        existing.hostname = dev.hostname
                        if let m = dev.macAddress { existing.macAddress = m }
                        existing.vendor = dev.vendor
                        existing.role = dev.role
                        existing.tags = dev.tags
                        if let s = dev.site { existing.site = s }
                        try updateDevice(existing)
                        updated += 1
                    } else {
                        try createDevice(dev)
                        added += 1
                    }
                } catch {
                    errors.append("\(dev.displayName) (\(dev.managementIP)): \(error.localizedDescription)")
                }
            }
            return DeviceImportResult(totalProcessed: devices.count, addedCount: added, updatedCount: updated, errors: errors)
        }

        // Generic JSON Dictionary array fallback
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return DeviceImportResult(totalProcessed: 0, addedCount: 0, updatedCount: 0, errors: ["Data is not a valid JSON array of devices."])
        }

        var added = 0
        var updated = 0
        var errors: [String] = []

        for (idx, dict) in jsonArray.enumerated() {
            // Case-insensitive flexible key lookup
            func lookupKey(_ keys: [String]) -> String? {
                for k in keys {
                    if let val = dict[k] as? String, !val.isEmpty { return val }
                    if let entry = dict.first(where: { $0.key.caseInsensitiveCompare(k) == .orderedSame }),
                       let val = entry.value as? String, !val.isEmpty {
                        return val
                    }
                }
                return nil
            }

            let ip = lookupKey(["managementIP", "ip", "ip_address", "ipaddress", "management_ip", "host_ip"]) ?? ""
            guard !ip.isEmpty else {
                errors.append("Item #\(idx): missing IP address")
                continue
            }

            let name = lookupKey(["displayName", "name", "devicename", "device_name", "device", "hostname"]) ?? ip
            let host = lookupKey(["hostname", "host", "name"]) ?? ip
            let mac = lookupKey(["macAddress", "mac", "mac_address", "macaddress", "ethernet", "hwaddr"])
            let vendorStr = lookupKey(["vendor", "manufacturer", "make"]) ?? ""
            var vendor = resolveVendorString(vendorStr)
            if vendor == .generic, let m = mac {
                let inferred = OUIResolver.inferVendor(mac: m)
                if inferred != .generic {
                    vendor = inferred
                } else if let resolved = OUIResolver.lookup(mac: m) {
                    vendor = resolveVendorString(resolved)
                }
            }
            let roleStr = lookupKey(["role", "type", "devicetype", "device_role", "category"]) ?? ""
            let role = roleStr.isEmpty ? inferRoleFromVendor(vendor) : resolveRoleString(roleStr)
            let site = lookupKey(["site", "location", "facility", "datacenter", "dc", "building"])
            let platform = lookupKey(["platform", "os"])
            let model = lookupKey(["model", "hardware"])

            let tags: [String] = {
                if let tagArray = dict["tags"] as? [String] {
                    return tagArray
                }
                if let tagStr = lookupKey(["tags", "labels"]) {
                    return tagStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                return []
            }()

            do {
                if var existing = try getDevice(byIP: ip) {
                    existing.displayName = name
                    existing.hostname = host
                    if let m = mac { existing.macAddress = m }
                    if vendor != .generic { existing.vendor = vendor }
                    existing.role = role
                    if let s = site { existing.site = s }
                    if let p = platform { existing.platform = p }
                    if let m = model { existing.model = m }
                    for t in tags where !existing.tags.contains(t) { existing.tags.append(t) }
                    try updateDevice(existing)
                    updated += 1
                } else {
                    let newDev = NetworkDevice(
                        id: UUID(),
                        displayName: name,
                        hostname: host,
                        managementIP: ip,
                        macAddress: mac,
                        vendor: vendor,
                        role: role,
                        platform: platform,
                        model: model,
                        site: site,
                        tags: tags,
                        status: .unknown,
                        lastSeen: Date()
                    )
                    try createDevice(newDev)
                    added += 1
                }
            } catch {
                errors.append("Item #\(idx) (\(ip)): \(error.localizedDescription)")
            }
        }

        return DeviceImportResult(totalProcessed: jsonArray.count, addedCount: added, updatedCount: updated, errors: errors)
    }

    // MARK: - Topology Node Position Persistence

    public func saveNodePosition(preset: String, nodeId: String, position: CGPoint) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        INSERT INTO topology_node_positions (preset_id, node_id, x, y)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(preset_id, node_id) DO UPDATE SET x = excluded.x, y = excluded.y;
        """
        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (preset as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (nodeId as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, Double(position.x))
        sqlite3_bind_double(stmt, 4, Double(position.y))

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(database.rawHandle))
            throw DeviceManagerError.databaseError("Failed to save node position: \(err)")
        }
    }

    public func loadNodePositions(preset: String) throws -> [String: CGPoint] {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT node_id, x, y FROM topology_node_positions WHERE preset_id = ?;"
        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (preset as NSString).utf8String, -1, nil)
        var positions: [String: CGPoint] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nodeCStr = sqlite3_column_text(stmt, 0) else { continue }
            let nodeId = String(cString: nodeCStr)
            let x = sqlite3_column_double(stmt, 1)
            let y = sqlite3_column_double(stmt, 2)
            positions[nodeId] = CGPoint(x: x, y: y)
        }
        return positions
    }

    public func clearNodePositions(preset: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "DELETE FROM topology_node_positions WHERE preset_id = ?;"
        let stmt = try database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (preset as NSString).utf8String, -1, nil)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Resolution Helpers

    private func resolveVendorString(_ str: String) -> DeviceVendor {
        if let exact = DeviceVendor(rawValue: str) { return exact }
        let lower = str.lowercased()
        for v in DeviceVendor.allCases {
            if v.rawValue.lowercased() == lower { return v }
        }
        for v in DeviceVendor.allCases {
            if lower.contains(v.rawValue.lowercased()) { return v }
        }
        return .generic
    }

    private func resolveRoleString(_ str: String) -> DeviceRole {
        if let exact = DeviceRole(rawValue: str) { return exact }
        let lower = str.lowercased()
        for r in DeviceRole.allCases {
            if r.rawValue.lowercased() == lower { return r }
        }
        if lower.contains("switch") { return .switchRole }
        if lower.contains("router") || lower.contains("gateway") { return .router }
        if lower.contains("firewall") || lower.contains("sec") { return .firewall }
        if lower.contains("ap") || lower.contains("access point") || lower.contains("wifi") { return .accessPoint }
        if lower.contains("server") { return .server }
        if lower.contains("workstation") || lower.contains("pc") || lower.contains("mac") || lower.contains("laptop") { return .workstation }
        return .other
    }

    private func inferRoleFromVendor(_ vendor: DeviceVendor) -> DeviceRole {
        switch vendor {
        case .cisco, .arista, .juniper: return .switchRole
        case .linksys, .netgear, .tpLink, .asus, .avm, .zyxel, .dlink: return .router
        case .ubiquiti: return .accessPoint
        case .paloAlto, .fortinet: return .firewall
        case .apple, .dell, .lenovo, .microsoft: return .workstation
        case .linux, .vmware, .synology, .qnap: return .server
        default: return .switchRole
        }
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
