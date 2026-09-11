import SwiftUI
import TracerouteEngine

/// Visual hop-by-hop route path node diagram with cyber-grade infrastructure aesthetics.
public struct PathTopologyView: View {
    let hops: [HopRecord]
    let latencyJumpHop: Int?

    public init(hops: [HopRecord], latencyJumpHop: Int? = nil) {
        self.hops = hops
        self.latencyJumpHop = latencyJumpHop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(Theme.neonCyan)
                    Text("DYNAMIC ROUTE TOPOLOGY GRAPH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                }

                Spacer()

                Text("\(hops.count) Hops Recorded")
                    .font(Theme.monoText(10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Local Source Node
                    hopNode(
                        number: "0",
                        icon: "laptopcomputer",
                        title: "Local Host",
                        subtitle: "Your Workstation",
                        rtt: "0.0 ms",
                        isAnomalous: false,
                        isTimeout: false,
                        isDestination: false
                    )

                    ForEach(hops) { hop in
                        connectorLine(isAnomalous: hop.hopNumber == latencyJumpHop)

                        hopNode(
                            number: "\(hop.hopNumber)",
                            icon: hop.hopNumber == hops.count ? "flag.checkered.circle.fill" : "network",
                            title: hop.address ?? "* * *",
                            subtitle: hop.isTimeout ? "No ICMP Echo" : (hop.hopNumber == hops.count ? "Destination" : "Transit Router"),
                            rtt: hop.rttMs != nil ? String(format: "%.1f ms", hop.rttMs!) : "Timeout",
                            isAnomalous: hop.hopNumber == latencyJumpHop,
                            isTimeout: hop.isTimeout,
                            isDestination: hop.hopNumber == hops.count && !hop.isTimeout
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    private func hopNode(
        number: String,
        icon: String,
        title: String,
        subtitle: String,
        rtt: String,
        isAnomalous: Bool,
        isTimeout: Bool,
        isDestination: Bool
    ) -> some View {
        let color = nodeColor(isAnomalous: isAnomalous, isTimeout: isTimeout, isDestination: isDestination)

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .strokeBorder(color.opacity(isAnomalous ? 0.9 : 0.4), lineWidth: isAnomalous ? 2.0 : 1.2)
                    )
                    .shadow(color: isAnomalous ? Theme.solarAmber.opacity(0.4) : (isDestination ? Theme.neonCyan.opacity(0.3) : .clear), radius: 6)

                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                    Text(number)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(color.opacity(0.9))
                }
            }

            VStack(spacing: 2) {
                Text(title)
                    .font(Theme.monoText(11, weight: .bold))
                    .lineLimit(1)
                    .frame(width: 118)

                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(rtt)
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(rttColor(isTimeout: isTimeout, isAnomalous: isAnomalous))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(rttColor(isTimeout: isTimeout, isAnomalous: isAnomalous).opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(width: 126)
    }

    private func connectorLine(isAnomalous: Bool) -> some View {
        HStack(spacing: 3) {
            Rectangle()
                .fill(isAnomalous ? Theme.solarAmber : Theme.azurePro.opacity(0.3))
                .frame(width: 22, height: isAnomalous ? 2.5 : 1.5)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(isAnomalous ? Theme.solarAmber : Theme.azurePro.opacity(0.5))
        }
        .padding(.bottom, 28)
    }

    private func nodeColor(isAnomalous: Bool, isTimeout: Bool, isDestination: Bool) -> Color {
        if isTimeout { return Theme.pulseCrimson }
        if isAnomalous { return Theme.solarAmber }
        if isDestination { return Theme.neonCyan }
        return Theme.azurePro
    }

    private func rttColor(isTimeout: Bool, isAnomalous: Bool) -> Color {
        if isTimeout { return Theme.pulseCrimson }
        if isAnomalous { return Theme.solarAmber }
        return Theme.signalEmerald
    }
}
