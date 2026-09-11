import SwiftUI

/// Sleek real-time latency sparkline chart with guide lines and gradient fill.
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.cyanPulse)
                        .frame(width: 7, height: 7)
                    Text("RTT LATENCY PROFILE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    metricBadge(label: "MIN", val: String(format: "%.1f ms", minMs), color: Theme.emeraldHealthy)
                    metricBadge(label: "MED", val: String(format: "%.1f ms", medianMs), color: Theme.cyanPulse)
                    metricBadge(label: "MAX", val: String(format: "%.1f ms", maxMs), color: Theme.amberWarning)
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
                        let y = h - (norm * (h - 10)) - 5
                        return CGPoint(x: x, y: y)
                    }

                    ZStack {
                        // Median Guide line
                        let medY = h - (CGFloat(medianMs / effectiveMax) * (h - 10)) - 5
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: medY))
                            p.addLine(to: CGPoint(x: w, y: medY))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.primary.opacity(0.15))

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
                                colors: [Theme.cyanPulse.opacity(0.25), Theme.cyanPulse.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Sparkline Stroke
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() {
                                p.addLine(to: pt)
                            }
                        }
                        .stroke(Theme.cyanPulse, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Active Sample Points
                        ForEach(points.indices, id: \.self) { i in
                            Circle()
                                .fill(i == points.count - 1 ? Theme.cyanPulse : Theme.cardBackground)
                                .overlay(Circle().stroke(Theme.cyanPulse, lineWidth: 1.5))
                                .frame(width: i == points.count - 1 ? 8 : 5, height: i == points.count - 1 ? 8 : 5)
                                .position(points[i])
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        Text("Awaiting latency samples...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: h)
                }
            }
            .frame(height: 75)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
        }
    }

    private func metricBadge(label: String, val: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(val)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
