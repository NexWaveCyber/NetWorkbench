import SwiftUI

/// Sleek real-time latency sparkline chart with guide lines, glowing stroke, gradient fill, and P95/AVG telemetry metrics.
public struct LatencySparklineView: View {
    let samples: [Double]
    let minMs: Double
    let maxMs: Double
    let medianMs: Double
    let avgMs: Double?
    let p95Ms: Double?

    @State private var hoveredIndex: Int? = nil

    public init(
        samples: [Double],
        minMs: Double,
        maxMs: Double,
        medianMs: Double,
        avgMs: Double? = nil,
        p95Ms: Double? = nil
    ) {
        self.samples = samples
        self.minMs = minMs
        self.maxMs = maxMs
        self.medianMs = medianMs
        self.avgMs = avgMs
        self.p95Ms = p95Ms
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    PulsingBeacon(color: Theme.neonCyan, size: 6, isLive: true)
                    Text("RTT LATENCY PROFILE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                }

                Spacer()

                // Telemetry Badges
                HStack(spacing: 6) {
                    metricBadge(label: "MIN", val: String(format: "%.1f ms", minMs), color: Theme.signalEmerald)
                    if let avg = avgMs {
                        metricBadge(label: "AVG", val: String(format: "%.1f ms", avg), color: Theme.electricAzure)
                    }
                    metricBadge(label: "MED", val: String(format: "%.1f ms", medianMs), color: Theme.neonCyan)
                    if let p95 = p95Ms {
                        metricBadge(label: "P95", val: String(format: "%.1f ms", p95), color: Theme.solarAmber)
                    }
                    metricBadge(label: "MAX", val: String(format: "%.1f ms", maxMs), color: Theme.pulseCrimson)
                    
                    Text("N=\(samples.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Canvas & Curve
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                if samples.count > 1 {
                    let effectiveMax = max(maxMs * 1.15, 1.0)
                    let points = samples.indices.map { i -> CGPoint in
                        let x = CGFloat(i) / CGFloat(samples.count - 1) * w
                        let norm = CGFloat(samples[i] / effectiveMax)
                        let y = h - (norm * (h - 16)) - 8
                        return CGPoint(x: x, y: y)
                    }

                    ZStack {
                        // Background Subtle Grid Lines
                        Path { p in
                            let step = h / 3
                            for i in 1...2 {
                                let y = step * CGFloat(i)
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                        }
                        .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [4, 6]))
                        .foregroundStyle(Color.primary.opacity(0.06))

                        // Median Reference Line
                        let medY = h - (CGFloat(medianMs / effectiveMax) * (h - 16)) - 8
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: medY))
                            p.addLine(to: CGPoint(x: w, y: medY))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(Theme.neonCyan.opacity(0.30))

                        // Gradient Area Fill
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h))
                            p.addLine(to: points[0])
                            for pt in points.dropFirst() {
                                p.addLine(to: pt)
                            }
                            p.addLine(to: CGPoint(x: w, y: h))
                            p.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.neonCyan.opacity(0.24),
                                    Theme.azurePro.opacity(0.06),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Outer Glow Stroke
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() {
                                p.addLine(to: pt)
                            }
                        }
                        .stroke(Theme.neonCyan.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .blur(radius: 2.5)

                        // Core Sharp Line
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() {
                                p.addLine(to: pt)
                            }
                        }
                        .stroke(
                            LinearGradient(
                                colors: [Theme.neonCyan, Theme.electricAzure],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                        )

                        // Sample Points
                        ForEach(points.indices, id: \.self) { i in
                            let isHovered = hoveredIndex == i
                            let isLast = i == points.count - 1

                            Circle()
                                .fill(isLast ? Theme.neonCyan : (isHovered ? Theme.cyanPulse : Theme.cardBackground))
                                .frame(width: isHovered ? 9 : (isLast ? 7 : 5), height: isHovered ? 9 : (isLast ? 7 : 5))
                                .overlay(
                                    Circle()
                                        .stroke(Theme.neonCyan, lineWidth: 1.5)
                                )
                                .shadow(color: isHovered || isLast ? Theme.neonCyan.opacity(0.8) : Color.clear, radius: 4)
                                .position(points[i])
                                .onHover { hovering in
                                    hoveredIndex = hovering ? i : nil
                                }
                                .help("Probe #\(i + 1): \(String(format: "%.2f", samples[i])) ms")
                        }
                    }
                } else if let single = samples.first {
                    // Single sample display
                    ZStack {
                        let y = h / 2
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Theme.neonCyan.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        Circle()
                            .fill(Theme.neonCyan)
                            .frame(width: 8, height: 8)
                            .shadow(color: Theme.neonCyan, radius: 4)
                            .position(x: w / 2, y: y)
                            .help("Single Probe: \(String(format: "%.2f", single)) ms")
                    }
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(Theme.neonCyan.opacity(0.5))
                            Text("Awaiting latency probe samples...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(height: h)
                }
            }
            .frame(height: 80)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
        }
    }

    private func metricBadge(label: String, val: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(val)
                .font(Theme.monoText(10.5, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.25), lineWidth: 0.75))
    }
}
