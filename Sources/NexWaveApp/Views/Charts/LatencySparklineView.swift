import SwiftUI

/// Sleek real-time latency sparkline chart with guide lines, glowing stroke, and gradient fill.
public struct LatencySparklineView: View {
    let samples: [Double]
    let minMs: Double
    let maxMs: Double
    let medianMs: Double

    public init(samples: [Double], minMs: Double, maxMs: Double, medianMs: Double) {
        self.samples = samples
        self.minMs = minMs
        self.maxMs = maxMs
        self.medianMs = medianMs
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.neonCyan)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .stroke(Theme.neonCyan.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.6)
                        )

                    Text("ROUND-TRIP TIME (RTT) PROFILE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                }

                Spacer()

                HStack(spacing: 10) {
                    metricBadge(label: "MIN", val: String(format: "%.1f ms", minMs), color: Theme.signalEmerald)
                    metricBadge(label: "MED", val: String(format: "%.1f ms", medianMs), color: Theme.neonCyan)
                    metricBadge(label: "MAX", val: String(format: "%.1f ms", maxMs), color: Theme.solarAmber)
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                if samples.count > 1 {
                    let effectiveMax = max(maxMs * 1.15, 1.0)
                    let points = samples.indices.map { i -> CGPoint in
                        let x = CGFloat(i) / CGFloat(samples.count - 1) * w
                        let norm = CGFloat(samples[i] / effectiveMax)
                        let y = h - (norm * (h - 14)) - 7
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
                        let medY = h - (CGFloat(medianMs / effectiveMax) * (h - 14)) - 7
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: medY))
                            p.addLine(to: CGPoint(x: w, y: medY))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(Theme.neonCyan.opacity(0.35))

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
                                    Theme.neonCyan.opacity(0.28),
                                    Theme.azurePro.opacity(0.08),
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
                        .stroke(Theme.neonCyan.opacity(0.4), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .blur(radius: 3)

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
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                        )

                        // Sample Points
                        ForEach(points.indices, id: \.self) { i in
                            if i == points.count - 1 {
                                // Pulsing Head Point
                                Circle()
                                    .fill(Theme.neonCyan)
                                    .frame(width: 9, height: 9)
                                    .overlay(
                                        Circle()
                                            .stroke(Theme.neonCyan.opacity(0.5), lineWidth: 2)
                                            .scaleEffect(1.6)
                                    )
                                    .shadow(color: Theme.neonCyan, radius: 4)
                                    .position(points[i])
                            } else {
                                Circle()
                                    .fill(Theme.cardBackground)
                                    .overlay(Circle().stroke(Theme.neonCyan.opacity(0.8), lineWidth: 1.5))
                                    .frame(width: 5, height: 5)
                                    .position(points[i])
                            }
                        }
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
            .frame(height: 85)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
        }
    }

    private func metricBadge(label: String, val: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(val)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.2), lineWidth: 0.75))
    }
}
