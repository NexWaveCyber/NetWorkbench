import SwiftUI
import PingEngine
import NetworkCore

public struct PortProbeStatus: Identifiable {
    public let port: NetworkPort
    public let service: String
    public let category: String
    public var result: ProbeResult?
    public var isProbing: Bool

    public var id: UInt16 { port.rawValue }
}

public struct PortDiagnosticsView: View {
    @State private var targetHost = "1.1.1.1"
    @State private var selectedFilter = "All"
    @State private var ports: [PortProbeStatus] = [
        PortProbeStatus(port: .ssh, service: "SSH Secure Shell", category: "Management", result: nil, isProbing: false),
        PortProbeStatus(port: .dns, service: "DNS Domain Name", category: "Infrastructure", result: nil, isProbing: false),
        PortProbeStatus(port: .http, service: "HTTP Web", category: "Web", result: nil, isProbing: false),
        PortProbeStatus(port: .https, service: "HTTPS Secure Web", category: "Web", result: nil, isProbing: false),
        PortProbeStatus(port: .bgp, service: "BGP Routing", category: "Infrastructure", result: nil, isProbing: false),
        PortProbeStatus(port: .doT, service: "DNS-over-TLS", category: "Infrastructure", result: nil, isProbing: false),
        PortProbeStatus(port: .httpAlt, service: "HTTP Secondary", category: "Web", result: nil, isProbing: false),
        PortProbeStatus(port: .httpsAlt, service: "HTTPS Secondary", category: "Web", result: nil, isProbing: false)
    ]
    @State private var isRunningAll = false

    private let prober = TCPPingProber()

    public init() {}

    public var filteredPorts: [PortProbeStatus] {
        if selectedFilter == "All" { return ports }
        return ports.filter { $0.category == selectedFilter }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Bar
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("TCP / PORT REACHABILITY PROBER")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                        Spacer()
                        Text("SYN/ACK Handshake Latency Profiler")
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
                                Text("Scan Common Ports")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(targetHost.trimmingCharacters(in: .whitespaces).isEmpty || isRunningAll)
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

                    // Filter Pills
                    HStack(spacing: 6) {
                        ForEach(["All", "Web", "Infrastructure", "Management"], id: \.self) { cat in
                            Button(action: { selectedFilter = cat }) {
                                Text(cat)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(selectedFilter == cat ? Theme.neonCyan.opacity(0.18) : Color.primary.opacity(0.04))
                                    .foregroundStyle(selectedFilter == cat ? Theme.neonCyan : Color.primary)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(selectedFilter == cat ? Theme.neonCyan : Theme.borderLight, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .engineeringCard(padding: 16)

                // Port Grid
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PORT STATUS & HANDSHAKE TIMING MATRIX")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        let openCount = ports.filter { if case .success = $0.result { return true } else { return false } }.count
                        Text("\(openCount) Ports Open")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(openCount > 0 ? Theme.signalEmerald : .secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(filteredPorts) { p in
                            portCard(p: p)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Port Diagnostics")
        .onAppear {
            scanAllPorts()
        }
    }

    private func scanAllPorts() {
        let host = targetHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        isRunningAll = true

        Task {
            for i in ports.indices {
                ports[i].isProbing = true
                let res = await prober.probe(host: host, port: ports[i].port, timeoutSeconds: 1.5)
                await MainActor.run {
                    ports[i].result = res
                    ports[i].isProbing = false
                }
            }
            await MainActor.run {
                isRunningAll = false
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
