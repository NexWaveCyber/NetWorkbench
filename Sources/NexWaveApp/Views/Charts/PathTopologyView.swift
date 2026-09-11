import SwiftUI
import TracerouteEngine

/// Visual hop-by-hop route path node diagram.
public struct PathTopologyView: View {
    let hops: [HopRecord]
    let latencyJumpHop: Int?

    public init(hops: [HopRecord], latencyJumpHop: Int? = nil) {
        self.hops = hops
        self.latencyJumpHop = latencyJumpHop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(Theme.azurePro)
                    Text("ROUTE TOPOLOGY VISUALIZER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(hops.count) Hops Traversed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Local Source Node
                    hopNode(
                        number: "0",
                        title: "Local Host",
                        subtitle: "Your Mac",
                        rtt: "0.0 ms",
                        isAnomalous: false,
                        isTimeout: false,
                        isDestination: false
                    )

                    ForEach(hops) { hop in
                        connectorLine(isAnomalous: hop.hopNumber == latencyJumpHop)

                        hopNode(
                            number: "\(hop.hopNumber)",
                            title: hop.address ?? "* * *",
                            subtitle: hop.isTimeout ? "No Response" : (hop.hopNumber == hops.count ? "Destination" : "Transit Hop"),
                            rtt: hop.rttMs != nil ? String(format: "%.1f ms", hop.rttMs!) : "Timeout",
                            isAnomalous: hop.hopNumber == latencyJumpHop,
                            isTimeout: hop.isTimeout,
                            isDestination: hop.hopNumber == hops.count && !hop.isTimeout
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }

    private func hopNode(
        number: String,
        title: String,
        subtitle: String,
        rtt: String,
        isAnomalous: Bool,
        isTimeout: Bool,
        isDestination: Bool
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(nodeColor(isAnomalous: isAnomalous, isTimeout: isTimeout, isDestination: isDestination).opacity(0.15))
                    .frame(width: 32, height: 32)

                Circle()
                    .stroke(nodeColor(isAnomalous: isAnomalous, isTimeout: isTimeout, isDestination: isDestination), lineWidth: 1.5)
                    .frame(width: 32, height: 32)

                Text(number)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(nodeColor(isAnomalous: isAnomalous, isTimeout: isTimeout, isDestination: isDestination))
            }

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .frame(width: 110)

                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(rtt)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isTimeout ? Theme.crimsonCritical : (isAnomalous ? Theme.amberWarning : Theme.emeraldHealthy))
            }
        }
        .frame(width: 120)
    }

    private func connectorLine(isAnomalous: Bool) -> some View {
        HStack(spacing: 2) {
            Rectangle()
                .fill(isAnomalous ? Theme.amberWarning : Color.primary.opacity(0.15))
                .frame(width: 24, height: isAnomalous ? 2.5 : 1.5)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isAnomalous ? Theme.amberWarning : Color.primary.opacity(0.2))
        }
        .padding(.bottom, 24)
    }

    private func nodeColor(isAnomalous: Bool, isTimeout: Bool, isDestination: Bool) -> Color {
        if isTimeout { return Theme.crimsonCritical }
        if isAnomalous { return Theme.amberWarning }
        if isDestination { return Theme.cyanPulse }
        return Theme.azurePro
    }
}
