import SwiftUI
import PingEngine
import NetworkCore

public struct PortProbeStatus: Identifiable {
    public let port: NetworkPort
    public let service: String
    public var result: ProbeResult?
    public var isProbing: Bool

    public var id: UInt16 { port.rawValue }
}

public struct PortDiagnosticsView: View {
    @State private var targetHost = "1.1.1.1"
    @State private var ports: [PortProbeStatus] = [
        PortProbeStatus(port: .ssh, service: "SSH", result: nil, isProbing: false),
        PortProbeStatus(port: .dns, service: "DNS", result: nil, isProbing: false),
        PortProbeStatus(port: .http, service: "HTTP", result: nil, isProbing: false),
        PortProbeStatus(port: .https, service: "HTTPS", result: nil, isProbing: false),
        PortProbeStatus(port: .bgp, service: "BGP", result: nil, isProbing: false),
        PortProbeStatus(port: .doT, service: "DNS-over-TLS", result: nil, isProbing: false),
        PortProbeStatus(port: .httpAlt, service: "HTTP Alt", result: nil, isProbing: false),
        PortProbeStatus(port: .httpsAlt, service: "HTTPS Alt", result: nil, isProbing: false)
    ]
    @State private var isRunningAll = false

    private let prober = TCPPingProber()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Bar
                VStack(alignment: .leading, spacing: 12) {
                    Text("TCP / PORT REACHABILITY PROBER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)

                    HStack(spacing: 12) {
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.azurePro)

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
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(targetHost.trimmingCharacters(in: .whitespaces).isEmpty || isRunningAll)
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                }
                .engineeringCard()

                // Port Grid
                VStack(alignment: .leading, spacing: 10) {
                    Text("PORT STATUS & HANDSHAKE TIMING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ports) { p in
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(p.port.rawValue)")
                    .font(Theme.monoText(15, weight: .bold))

                Spacer()

                if p.isProbing {
                    ProgressView().controlSize(.mini)
                } else if let res = p.result {
                    statusBadge(res: res)
                } else {
                    Text("Ready")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(p.service)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                if let res = p.result, case .success(let ms) = res {
                    Text(String(format: "%.1f ms", ms))
                        .font(Theme.monoText(11, weight: .semibold))
                        .foregroundStyle(Theme.cyanPulse)
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }

    private func statusBadge(res: ProbeResult) -> some View {
        switch res {
        case .success:
            return Text("OPEN")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.emeraldHealthy.opacity(0.15))
                .foregroundStyle(Theme.emeraldHealthy)
                .clipShape(Capsule())
        case .timeout:
            return Text("FILTERED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.amberWarning.opacity(0.15))
                .foregroundStyle(Theme.amberWarning)
                .clipShape(Capsule())
        case .error:
            return Text("CLOSED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.crimsonCritical.opacity(0.15))
                .foregroundStyle(Theme.crimsonCritical)
                .clipShape(Capsule())
        }
    }
}
