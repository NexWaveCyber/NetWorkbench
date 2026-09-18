import SwiftUI
import PingEngine
import NetworkCore

public struct PortProbeStatus: Identifiable, Sendable {
    public let port: NetworkPort
    public let service: String
    public let category: String
    public var result: ProbeResult?
    public var isProbing: Bool

    public var id: UInt16 { port.rawValue }

    public init(port: NetworkPort, service: String, category: String, result: ProbeResult? = nil, isProbing: Bool = false) {
        self.port = port
        self.service = service
        self.category = category
        self.result = result
        self.isProbing = isProbing
    }
}

public struct PortDiagnosticsView: View {
    @State private var targetHost = "1.1.1.1"
    @State private var selectedFilter = "All"
    @State private var isRunningAll = false

    // Custom port input
    @State private var customPortNumber = ""
    @State private var customServiceName = ""

    // Port Presets
    public static let corePorts: [PortProbeStatus] = [
        PortProbeStatus(port: .ssh, service: "SSH Secure Shell", category: "Management"),
        PortProbeStatus(port: .dns, service: "DNS Domain Name", category: "Infrastructure"),
        PortProbeStatus(port: .http, service: "HTTP Web", category: "Web"),
        PortProbeStatus(port: .https, service: "HTTPS Secure Web", category: "Web"),
        PortProbeStatus(port: .bgp, service: "BGP Routing", category: "Infrastructure"),
        PortProbeStatus(port: .doT, service: "DNS-over-TLS", category: "Infrastructure"),
        PortProbeStatus(port: .httpAlt, service: "HTTP Secondary (8080)", category: "Web"),
        PortProbeStatus(port: .httpsAlt, service: "HTTPS Secondary (8443)", category: "Web")
    ]

    public static let databasePorts: [PortProbeStatus] = [
        PortProbeStatus(port: NetworkPort(3306), service: "MySQL Database", category: "Database"),
        PortProbeStatus(port: NetworkPort(5432), service: "PostgreSQL Database", category: "Database"),
        PortProbeStatus(port: NetworkPort(6379), service: "Redis Cache Store", category: "Database"),
        PortProbeStatus(port: NetworkPort(27017), service: "MongoDB NoSQL", category: "Database"),
        PortProbeStatus(port: NetworkPort(1433), service: "Microsoft SQL Server", category: "Database"),
        PortProbeStatus(port: NetworkPort(9200), service: "Elasticsearch REST API", category: "Database")
    ]

    public static let remoteOpsPorts: [PortProbeStatus] = [
        PortProbeStatus(port: .ssh, service: "SSH Secure Shell (22)", category: "Remote"),
        PortProbeStatus(port: NetworkPort(23), service: "Telnet Legacy (23)", category: "Remote"),
        PortProbeStatus(port: NetworkPort(3389), service: "RDP Remote Desktop", category: "Remote"),
        PortProbeStatus(port: NetworkPort(5900), service: "VNC Screen Sharing", category: "Remote"),
        PortProbeStatus(port: NetworkPort(1194), service: "OpenVPN Tunnel", category: "Remote"),
        PortProbeStatus(port: NetworkPort(500), service: "IPsec IKEv2 Key Exchange", category: "Remote")
    ]

    public static let webMicroservicePorts: [PortProbeStatus] = [
        PortProbeStatus(port: .http, service: "HTTP Web (80)", category: "Web"),
        PortProbeStatus(port: .https, service: "HTTPS Secure (443)", category: "Web"),
        PortProbeStatus(port: NetworkPort(3000), service: "Node / React Dev (3000)", category: "Web"),
        PortProbeStatus(port: NetworkPort(8000), service: "Python / Django (8000)", category: "Web"),
        PortProbeStatus(port: .httpAlt, service: "HTTP Alt Proxy (8080)", category: "Web"),
        PortProbeStatus(port: .httpsAlt, service: "HTTPS Alt (8443)", category: "Web"),
        PortProbeStatus(port: NetworkPort(9090), service: "Prometheus Metrics (9090)", category: "Web")
    ]

    @State private var ports: [PortProbeStatus] = PortDiagnosticsView.corePorts

    private let prober = TCPPingProber()

    public init(initialHost: String = "1.1.1.1") {
        _targetHost = State(initialValue: initialHost)
    }

    public var filteredPorts: [PortProbeStatus] {
        if selectedFilter == "All" { return ports }
        return ports.filter { $0.category == selectedFilter }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Bar
                headerControlCard

                // Custom Port Insertion Bar
                customPortBar

                // Port Grid
                portGridSection
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Port Diagnostics")
        .onAppear {
            scanAllPorts()
        }
    }

    // MARK: - Header Control Card
    private var headerControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TCP / PORT REACHABILITY PROBER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("Concurrent SYN/ACK Handshake Latency Profiler")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.neonCyan)

                TextField("Enter target host or IP (e.g. 1.1.1.1, google.com)...", text: $targetHost)
                    .textFieldStyle(.plain)
                    .font(Theme.monoText(15))
                    .onSubmit {
                        scanAllPorts()
                    }

                Button(action: scanAllPorts) {
                    HStack(spacing: 6) {
                        if isRunningAll {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text("Scan All Ports (Concurrent)")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(targetHost.trimmingCharacters(in: .whitespaces).isEmpty || isRunningAll ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Theme.cyanGlowGradient))
                    .foregroundStyle(targetHost.trimmingCharacters(in: .whitespaces).isEmpty || isRunningAll ? Color.secondary : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(targetHost.trimmingCharacters(in: .whitespaces).isEmpty || isRunningAll)
            }
            .padding(12)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

            // Presets & Filter Pills
            HStack(spacing: 12) {
                // Preset Packs
                HStack(spacing: 6) {
                    Text("Packs:").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)

                    Button("Core (8)") { loadPack(Self.corePorts) }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button("Databases") { loadPack(Self.databasePorts) }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button("Remote / VPN") { loadPack(Self.remoteOpsPorts) }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button("Web & Apps") { loadPack(Self.webMicroservicePorts) }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                // Filter Pills
                HStack(spacing: 6) {
                    ForEach(["All", "Web", "Infrastructure", "Management", "Database", "Remote"], id: \.self) { cat in
                        let count = ports.filter { cat == "All" || $0.category == cat }.count
                        if count > 0 || cat == "All" {
                            Button(action: { selectedFilter = cat }) {
                                Text("\(cat)")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(selectedFilter == cat ? Theme.neonCyan.opacity(0.18) : Color.primary.opacity(0.04))
                                    .foregroundStyle(selectedFilter == cat ? Theme.neonCyan : Color.primary)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(selectedFilter == cat ? Theme.neonCyan : Theme.borderLight, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Custom Port Insertion Bar
    private var customPortBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.neonCyan)

            Text("Custom Port:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Port # (e.g. 3389)", text: $customPortNumber)
                .textFieldStyle(.plain)
                .font(Theme.monoText(12))
                .frame(width: 140)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("Service tag (optional, e.g. RDP)", text: $customServiceName)
                .textFieldStyle(.plain)
                .font(Theme.monoText(12))
                .frame(width: 200)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Button(action: addAndProbeCustomPort) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add & Probe")
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.azurePro.opacity(0.15))
                .foregroundStyle(Theme.azurePro)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(UInt16(customPortNumber.trimmingCharacters(in: .whitespaces)) == nil)

            Spacer()

            Button("Clear Results") {
                for i in ports.indices {
                    ports[i].result = nil
                }
            }
            .buttonStyle(.plain)
            .font(Theme.monoText(11))
            .foregroundStyle(.secondary)
        }
        .engineeringCard(padding: 12)
    }

    // MARK: - Port Grid Section
    private var portGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PORT STATUS & CONCURRENT HANDSHAKE MATRIX")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                let openCount = ports.filter { if case .success = $0.result { return true } else { return false } }.count
                let filteredCount = ports.filter { if case .timeout = $0.result { return true } else { return false } }.count
                let closedCount = ports.filter { if case .error = $0.result { return true } else { return false } }.count

                HStack(spacing: 8) {
                    if openCount > 0 {
                        Text("\(openCount) Open")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                    if filteredCount > 0 {
                        Text("\(filteredCount) Filtered")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.solarAmber)
                    }
                    if closedCount > 0 {
                        Text("\(closedCount) Closed")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.pulseCrimson)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(filteredPorts) { p in
                    portCard(p: p)
                }
            }
        }
    }

    private func loadPack(_ pack: [PortProbeStatus]) {
        self.ports = pack
        scanAllPorts()
    }

    private func addAndProbeCustomPort() {
        guard let pNum = UInt16(customPortNumber.trimmingCharacters(in: .whitespaces)) else { return }
        let sName = customServiceName.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom (\(pNum))" : customServiceName.trimmingCharacters(in: .whitespaces)

        let newStatus = PortProbeStatus(
            port: NetworkPort(pNum),
            service: sName,
            category: "Custom",
            result: nil,
            isProbing: false
        )

        if let existingIdx = ports.firstIndex(where: { $0.port.rawValue == pNum }) {
            ports[existingIdx] = newStatus
        } else {
            ports.append(newStatus)
        }

        customPortNumber = ""
        customServiceName = ""

        // Probe newly added port
        probeSinglePort(portRaw: pNum)
    }

    // MARK: - High-Performance Concurrent Scanner
    private func scanAllPorts() {
        let host = targetHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        isRunningAll = true

        for i in ports.indices {
            ports[i].isProbing = true
        }

        let snapshotPorts = ports

        Task {
            await withTaskGroup(of: (UInt16, ProbeResult).self) { group in
                for item in snapshotPorts {
                    let p = item.port
                    group.addTask {
                        let res = await self.prober.probe(host: host, port: p, timeoutSeconds: 1.5)
                        return (p.rawValue, res)
                    }
                }

                for await (pNum, result) in group {
                    await MainActor.run {
                        if let idx = self.ports.firstIndex(where: { $0.port.rawValue == pNum }) {
                            self.ports[idx].result = result
                            self.ports[idx].isProbing = false
                        }
                    }
                }
            }

            await MainActor.run {
                self.isRunningAll = false
            }
        }
    }

    private func probeSinglePort(portRaw: UInt16) {
        let host = targetHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }

        if let idx = ports.firstIndex(where: { $0.port.rawValue == portRaw }) {
            ports[idx].isProbing = true
        }

        Task {
            let res = await prober.probe(host: host, port: NetworkPort(portRaw), timeoutSeconds: 1.5)
            await MainActor.run {
                if let idx = ports.firstIndex(where: { $0.port.rawValue == portRaw }) {
                    ports[idx].result = res
                    ports[idx].isProbing = false
                }
            }
        }
    }

    private func portCard(p: PortProbeStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(p.port.rawValue)")
                    .font(Theme.monoText(16, weight: .bold))

                Spacer()

                if p.isProbing {
                    ProgressView().controlSize(.mini)
                } else if let res = p.result {
                    statusBadge(res: res)
                } else {
                    Text("Ready")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(p.service)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(p.category)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if let res = p.result, case .success(let ms) = res {
                        Text(String(format: "%.1f ms", ms))
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                    } else if !p.isProbing {
                        Button(action: { probeSinglePort(portRaw: p.port.rawValue) }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor(for: p.result), lineWidth: 1)
        )
    }

    private func cardBorderColor(for res: ProbeResult?) -> Color {
        guard let res = res else { return Theme.borderLight }
        switch res {
        case .success: return Theme.signalEmerald.opacity(0.4)
        case .timeout: return Theme.solarAmber.opacity(0.3)
        case .error: return Theme.borderLight
        }
    }

    private func statusBadge(res: ProbeResult) -> some View {
        switch res {
        case .success:
            return Text("OPEN")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.signalEmerald.opacity(0.18))
                .foregroundStyle(Theme.signalEmerald)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.signalEmerald.opacity(0.3), lineWidth: 0.75))
        case .timeout:
            return Text("FILTERED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.solarAmber.opacity(0.18))
                .foregroundStyle(Theme.solarAmber)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.solarAmber.opacity(0.3), lineWidth: 0.75))
        case .error:
            return Text("CLOSED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.pulseCrimson.opacity(0.15))
                .foregroundStyle(Theme.pulseCrimson)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.pulseCrimson.opacity(0.3), lineWidth: 0.75))
        }
    }
}

