import Foundation

public enum SocketExposure: String, Sendable, CaseIterable {
    case loopback = "Loopback Only"
    case localNetwork = "Local Interface"
    case exposed = "Exposed (0.0.0.0 / *)"

    public var badgeColor: String {
        switch self {
        case .loopback: return "signalEmerald"
        case .localNetwork: return "solarAmber"
        case .exposed: return "pulseCrimson"
        }
    }
}

public struct ListeningSocketRecord: Sendable, Identifiable {
    public var id: String { "\(pid)-\(proto)-\(port)-\(localAddress)-\(ipVersion)" }
    public let command: String
    public let pid: Int
    public let user: String
    public let proto: String
    public let ipVersion: String
    public let localAddress: String
    public let port: Int
    public let state: String
    public let exposure: SocketExposure

    public var isPrivilegedPort: Bool {
        return port < 1024
    }

    public init(
        command: String,
        pid: Int,
        user: String,
        proto: String,
        ipVersion: String,
        localAddress: String,
        port: Int,
        state: String
    ) {
        self.command = command
        self.pid = pid
        self.user = user
        self.proto = proto
        self.ipVersion = ipVersion
        self.localAddress = localAddress
        self.port = port
        self.state = state

        if localAddress == "127.0.0.1" || localAddress == "::1" || localAddress.hasPrefix("localhost") {
            self.exposure = .loopback
        } else if localAddress == "*" || localAddress == "0.0.0.0" || localAddress == "::" {
            self.exposure = .exposed
        } else {
            self.exposure = .localNetwork
        }
    }
}

public enum SocketInspector {
    public static func scanListeningSockets() async -> [ListeningSocketRecord] {
        return await Task.detached(priority: .userInitiated) {
            var results: [ListeningSocketRecord] = []
            var seenKeys = Set<String>()

            // 1. Run lsof for TCP LISTEN sockets
            let tcpOutput = runCommand("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"])
            parseLsof(output: tcpOutput, defaultProto: "TCP", results: &results, seenKeys: &seenKeys)

            // 2. Run lsof for UDP sockets
            let udpOutput = runCommand("/usr/sbin/lsof", arguments: ["-nP", "-iUDP"])
            parseLsof(output: udpOutput, defaultProto: "UDP", results: &results, seenKeys: &seenKeys)

            return results.sorted {
                if $0.port != $1.port {
                    return $0.port < $1.port
                }
                return $0.command < $1.command
            }
        }.value
    }

    private static func runCommand(_ path: String, arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func parseLsof(
        output: String,
        defaultProto: String,
        results: inout [ListeningSocketRecord],
        seenKeys: inout Set<String>
    ) {
        let lines = output.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }

        for line in lines.dropFirst() {
            let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            // Expected columns: COMMAND, PID, USER, FD, TYPE, DEVICE, SIZE/OFF, NODE, NAME, (LISTEN)
            guard tokens.count >= 9 else { continue }

            let command = tokens[0]
            guard let pid = Int(tokens[1]) else { continue }
            let user = tokens[2]
            let ipVersion = tokens[4] // IPv4 or IPv6
            let nameCol = tokens[tokens.count - 1]

            // If last token is "(LISTEN)", the address:port is token before it
            let addressPortStr: String
            let state: String
            if nameCol.uppercased().contains("LISTEN") {
                addressPortStr = tokens[tokens.count - 2]
                state = "LISTEN"
            } else {
                addressPortStr = nameCol
                state = defaultProto == "UDP" ? "BOUND" : "IDLE"
            }

            // Parse address and port from addressPortStr (e.g. "*:7000", "127.0.0.1:7768", "[::1]:8080", "*:60258")
            guard let lastColon = addressPortStr.lastIndex(of: ":") else { continue }
            let address = String(addressPortStr[..<lastColon])
            let portStr = String(addressPortStr[addressPortStr.index(after: lastColon)...])
            guard let port = Int(portStr) else { continue }

            let cleanAddress = address.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            let dedupeKey = "\(pid)-\(defaultProto)-\(port)-\(cleanAddress)"
            if seenKeys.contains(dedupeKey) { continue }
            seenKeys.insert(dedupeKey)

            let record = ListeningSocketRecord(
                command: command,
                pid: pid,
                user: user,
                proto: defaultProto,
                ipVersion: ipVersion,
                localAddress: cleanAddress,
                port: port,
                state: state
            )
            results.append(record)
        }
    }
}
