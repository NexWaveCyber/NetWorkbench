import SwiftUI
import NetworkCore
import DiagnosticsEngine

public struct NetworkInspectorView: View {
    let result: DiagnosticResult?

    public init(result: DiagnosticResult?) {
        self.result = result
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let res = result {
                    // Target Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TARGET METADATA")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(res.target.displayString)
                            .font(Theme.monoText(14, weight: .bold))

                        HStack(spacing: 8) {
                            Text(res.target.targetType.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.azurePro.opacity(0.12))
                                .foregroundStyle(Theme.azurePro)
                                .clipShape(Capsule())

                            Text("Port \(res.target.defaultPort.rawValue)")
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .engineeringCard(padding: 12)

                    // Quick Telemetry Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TELEMETRY STATS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if let lat = res.latency {
                            row(label: "Median RTT", val: String(format: "%.1f ms", lat.medianMs))
                            row(label: "P95 Latency", val: String(format: "%.1f ms", lat.p95Ms))
                            row(label: "Jitter", val: String(format: "%.1f ms", lat.jitterMs))
                            row(label: "Packet Loss", val: String(format: "%.1f%%", lat.lossPercentage))
                        }

                        if let path = res.path {
                            row(label: "Route Hops", val: "\(path.totalHops)")
                        }

                        if let dns = res.dns {
                            row(label: "DNS Time", val: String(format: "%.1f ms", dns.queryTimeMs))
                        }
                    }
                    .engineeringCard(padding: 12)

                    // Resolved Addresses
                    if let dns = res.dns, !dns.ipv4Addresses.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RESOLVED IP ADDRESSES")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            ForEach(dns.ipv4Addresses, id: \.self) { ip in
                                HStack {
                                    Text(ip.description)
                                        .font(Theme.monoText(12))
                                    Spacer()
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(ip.description, forType: .string)
                                    }) {
                                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .engineeringCard(padding: 12)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No active target selected. Run a diagnosis to inspect network parameters.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .engineeringCard(padding: 12)
                }
            }
            .padding(14)
        }
        .background(Theme.surfaceBackground)
        .frame(minWidth: 240, idealWidth: 280)
    }

    private func row(label: String, val: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(val).font(Theme.monoText(11, weight: .medium))
        }
    }
}
