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
            VStack(alignment: .leading, spacing: 16) {
                // Inspector Header
                HStack {
                    Text("TELEMETRY INSPECTOR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                    Spacer()
                    Text("⌘I")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                if let res = result {
                    // Target Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(res.target.displayString)
                                .font(Theme.monoText(14, weight: .bold))
                                .lineLimit(1)
                            Spacer()
                            Circle()
                                .fill(statusColor(res.overallStatus))
                                .frame(width: 8, height: 8)
                        }

                        HStack(spacing: 8) {
                            Text(res.target.targetType.rawValue)
                                .font(Theme.monoText(10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.azurePro.opacity(0.15))
                                .foregroundStyle(Theme.azurePro)
                                .clipShape(Capsule())

                            Text("Default Port \(res.target.defaultPort.rawValue)")
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .engineeringCard(padding: 14)

                    // Quick Telemetry Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TELEMETRY METRICS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if let lat = res.latency {
                            row(label: "Median RTT", val: String(format: "%.1f ms", lat.medianMs), highlight: Theme.neonCyan)
                            row(label: "P95 Latency", val: String(format: "%.1f ms", lat.p95Ms))
                            row(label: "RFC 3550 Jitter", val: String(format: "%.1f ms", lat.jitterMs))
                            row(label: "Packet Loss", val: String(format: "%.1f%%", lat.lossPercentage), highlight: lat.lossPercentage == 0 ? Theme.signalEmerald : Theme.pulseCrimson)
                        }

                        if let path = res.path {
                            row(label: "Route Hops", val: "\(path.totalHops)")
                        }

                        if let dns = res.dns {
                            row(label: "DNS Query Time", val: String(format: "%.1f ms", dns.queryTimeMs))
                        }
                    }
                    .engineeringCard(padding: 14)

                    // Resolved Addresses
                    if let dns = res.dns, !dns.ipv4Addresses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RESOLVED IP ADDRESSES (\(dns.ipv4Addresses.count))")
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
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(6)
                                .background(Color.primary.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .engineeringCard(padding: 14)
                    }
                } else {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.neonCyan.opacity(0.06))
                                .frame(width: 52, height: 52)

                            Image(systemName: "sidebar.right")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.neonCyan.opacity(0.7))
                        }

                        Text("No Active Target")
                            .font(.system(size: 13, weight: .bold))

                        Text("Execute a diagnosis to inspect detailed network parameters, DNS records, and routing telemetry.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .engineeringCard(padding: 16)
                }
            }
            .padding(14)
        }
        .background(Theme.surfaceBackground)
        .frame(minWidth: 260, idealWidth: 290)
    }

    private func row(label: String, val: String, highlight: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(val)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(highlight ?? Color.primary)
        }
    }

    private func statusColor(_ status: OverallHealthStatus) -> Color {
        switch status {
        case .healthy: return Theme.signalEmerald
        case .degraded: return Theme.solarAmber
        case .critical: return Theme.pulseCrimson
        case .unreachable: return Theme.pulseCrimson
        }
    }
}
