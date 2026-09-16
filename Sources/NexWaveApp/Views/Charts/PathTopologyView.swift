import SwiftUI
import AppKit
import TracerouteEngine

// AppKit ScrollView subclass that intercepts vertical mouse wheel events and smoothly scrolls horizontally
private struct MouseWheelHorizontalScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> WheelScrollView {
        let scrollView = WheelScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ nsView: WheelScrollView, context: Context) {
        if let hosting = nsView.documentView as? NSHostingView<Content> {
            hosting.rootView = content
        }
    }
}

private class WheelScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if event.deltaX == 0 && event.deltaY != 0 {
            let clip = self.contentView
            var origin = clip.bounds.origin
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : (event.deltaY * 20.0)
            origin.x -= delta
            let maxWidth = max(0, (self.documentView?.bounds.width ?? 0) - clip.bounds.width)
            origin.x = max(0, min(origin.x, maxWidth))
            clip.scroll(to: origin)
            self.reflectScrolledClipView(clip)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// Visual hop-by-hop route path node diagram with cyber-grade infrastructure aesthetics, ASN telemetry, and Delta-RTT annotations.
/// Supports both Horizontal Strip flow and Vertical Ladder flow with smooth vertical mouse-wheel scrolling.
public struct PathTopologyView: View {
    let hops: [HopRecord]
    let latencyJumpHop: Int?

    @AppStorage("path_topology_layout_mode_v2") private var layoutModePreference: String = "auto"
    @State private var localMode: String? = nil

    private var effectiveLayoutMode: String {
        if let explicit = localMode { return explicit }
        if layoutModePreference == "vertical" { return "vertical" }
        if layoutModePreference == "horizontal" { return "horizontal" }
        // Auto: when more than 5 hops, default to vertical ladder so it fits on screen and mouse wheel scrolls
        return hops.count > 5 ? "vertical" : "horizontal"
    }

    public init(hops: [HopRecord], latencyJumpHop: Int? = nil) {
        self.hops = hops
        self.latencyJumpHop = latencyJumpHop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Bar with Controls
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(Theme.neonCyan)
                    Text("DYNAMIC ROUTE TOPOLOGY GRAPH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                }

                Spacer()

                HStack(spacing: 8) {
                    if let jump = latencyJumpHop {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Bottleneck at Hop \(jump)")
                        }
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Theme.solarAmber.opacity(0.12))
                        .foregroundStyle(Theme.solarAmber)
                        .clipShape(Capsule())
                    }

                    Text("\(hops.count) Hops")
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)

                    // Layout Mode Switcher
                    Picker("Layout Mode", selection: Binding(
                        get: { effectiveLayoutMode },
                        set: { newMode in
                            localMode = newMode
                            layoutModePreference = newMode
                        }
                    )) {
                        Label("Vertical Ladder", systemImage: "arrow.up.and.down").tag("vertical")
                        Label("Horizontal Flow", systemImage: "arrow.left.and.right").tag("horizontal")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
            }

            // Subtitle hint for mouse users
            HStack {
                if effectiveLayoutMode == "vertical" {
                    Label("Vertical Ladder: Roll mouse wheel anywhere to scroll down through all hops", systemImage: "computermouse.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.signalEmerald)
                } else {
                    Label("Horizontal Flow: Roll mouse wheel to scroll horizontally, or drag bottom scrollbar", systemImage: "computermouse.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.azurePro)
                }
                Spacer()
            }

            // Body: Switch between Horizontal Strip and Vertical Ladder
            if effectiveLayoutMode == "vertical" {
                verticalLadderView()
            } else {
                horizontalStripView()
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Horizontal Strip View
    private func horizontalStripView() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MouseWheelHorizontalScrollView {
                HStack(spacing: 0) {
                    // Local Source Node
                    hopNode(
                        number: "0",
                        icon: "laptopcomputer",
                        title: "Local Host",
                        subtitle: "Your Workstation",
                        asn: "Local Subnet",
                        rtt: "0.0 ms",
                        isAnomalous: false,
                        isTimeout: false,
                        isDestination: false,
                        rawAddress: "127.0.0.1"
                    )

                    ForEach(hops) { hop in
                        connectorLine(
                            isAnomalous: hop.hopNumber == latencyJumpHop,
                            deltaMs: hop.deltaMs
                        )

                        hopNode(
                            number: "\(hop.hopNumber)",
                            icon: hop.hopNumber == hops.count ? "flag.checkered.circle.fill" : "network",
                            title: hop.address ?? "* * *",
                            subtitle: hop.isTimeout ? "No ICMP Echo" : (hop.hopNumber == hops.count ? "Destination" : (hop.asName ?? "Transit Router")),
                            asn: hop.asn ?? (hop.isTimeout ? nil : "Transit"),
                            rtt: hop.rttMs != nil ? String(format: "%.1f ms", hop.rttMs!) : "Timeout",
                            isAnomalous: hop.hopNumber == latencyJumpHop,
                            isTimeout: hop.isTimeout,
                            isDestination: hop.hopNumber == hops.count && !hop.isTimeout,
                            rawAddress: hop.address
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            .frame(height: 125)
        }
    }

    // MARK: - Vertical Ladder View
    private func verticalLadderView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Source Node (Hop 0)
            verticalHopRow(
                number: "0",
                icon: "laptopcomputer",
                title: "Local Host",
                subtitle: "Your Workstation",
                asn: "Local Subnet",
                rtt: "0.0 ms",
                isAnomalous: false,
                isTimeout: false,
                isDestination: false,
                rawAddress: "127.0.0.1",
                deltaMs: nil,
                isLast: hops.isEmpty
            )

            ForEach(Array(hops.enumerated()), id: \.element.id) { index, hop in
                verticalHopRow(
                    number: "\(hop.hopNumber)",
                    icon: hop.hopNumber == hops.count ? "flag.checkered.circle.fill" : "network",
                    title: hop.address ?? "* * *",
                    subtitle: hop.isTimeout ? "No ICMP Echo (Filtered)" : (hop.hopNumber == hops.count ? "Destination Target" : (hop.asName ?? "Transit Router")),
                    asn: hop.asn ?? (hop.isTimeout ? nil : "Transit"),
                    rtt: hop.rttMs != nil ? String(format: "%.1f ms", hop.rttMs!) : "Timeout",
                    isAnomalous: hop.hopNumber == latencyJumpHop,
                    isTimeout: hop.isTimeout,
                    isDestination: hop.hopNumber == hops.count && !hop.isTimeout,
                    rawAddress: hop.address,
                    deltaMs: hop.deltaMs,
                    isLast: index == hops.count - 1
                )
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
    }

    private func verticalHopRow(
        number: String,
        icon: String,
        title: String,
        subtitle: String,
        asn: String?,
        rtt: String,
        isAnomalous: Bool,
        isTimeout: Bool,
        isDestination: Bool,
        rawAddress: String?,
        deltaMs: Double?,
        isLast: Bool
    ) -> some View {
        let color = nodeColor(isAnomalous: isAnomalous, isTimeout: isTimeout, isDestination: isDestination)

        return HStack(alignment: .top, spacing: 14) {
            // Left Timeline Column
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(color.opacity(isAnomalous ? 0.9 : 0.4), lineWidth: isAnomalous ? 2.0 : 1.2)
                        )
                        .shadow(color: isAnomalous ? Theme.solarAmber.opacity(0.4) : (isDestination ? Theme.neonCyan.opacity(0.3) : .clear), radius: 5)

                    VStack(spacing: 0) {
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(color)
                        Text(number)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(color.opacity(0.9))
                    }
                }

                if !isLast {
                    Rectangle()
                        .fill(isAnomalous ? Theme.solarAmber : Theme.azurePro.opacity(0.35))
                        .frame(width: isAnomalous ? 2.5 : 1.5, height: 26)
                }
            }
            .frame(width: 32)

            // Content Card
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.monoText(12, weight: .bold))
                        .foregroundStyle(isTimeout ? .secondary : Color.primary)

                    if let addr = rawAddress, addr != "* * *" {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(addr, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Copy IP \(addr)")
                    }

                    if let asInfo = asn {
                        Text(asInfo)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.azurePro)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Theme.azurePro.opacity(0.09))
                            .clipShape(Capsule())
                    }

                    if isAnomalous {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Latency Spike")
                        }
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Theme.solarAmber.opacity(0.12))
                        .foregroundStyle(Theme.solarAmber)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // RTT and Delta RTT
                    HStack(spacing: 6) {
                        if let delta = deltaMs, delta > 0.5 {
                            Text(String(format: "+%.1fms", delta))
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(isAnomalous ? Theme.solarAmber : .secondary)
                        }

                        Text(rtt)
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(rttColor(isTimeout: isTimeout, isAnomalous: isAnomalous))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(rttColor(isTimeout: isTimeout, isAnomalous: isAnomalous).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if isDestination {
                        Text("Target Reached")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.signalEmerald)
                    } else if isTimeout {
                        Text("No Echo / Filtered")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(isAnomalous ? Theme.solarAmber.opacity(0.04) : (isDestination ? Theme.neonCyan.opacity(0.04) : Color.primary.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isAnomalous ? Theme.solarAmber.opacity(0.4) : (isDestination ? Theme.neonCyan.opacity(0.3) : Theme.borderLight.opacity(0.5)), lineWidth: 1)
            )
        }
        .padding(.bottom, isLast ? 0 : 4)
    }

    private func hopNode(
        number: String,
        icon: String,
        title: String,
        subtitle: String,
        asn: String?,
        rtt: String,
        isAnomalous: Bool,
        isTimeout: Bool,
        isDestination: Bool,
        rawAddress: String?
    ) -> some View {
        let color = nodeColor(isAnomalous: isAnomalous, isTimeout: isTimeout, isDestination: isDestination)

        return VStack(spacing: 6) {
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

            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(Theme.monoText(10.5, weight: .bold))
                        .lineLimit(1)
                    
                    if let addr = rawAddress, addr != "* * *" {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(addr, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Copy IP \(addr)")
                    }
                }
                .frame(width: 122)

                Text(subtitle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 122)

                if let asInfo = asn {
                    Text(asInfo)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.azurePro)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Theme.azurePro.opacity(0.08))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                Text(rtt)
                    .font(Theme.monoText(9.5, weight: .bold))
                    .foregroundStyle(rttColor(isTimeout: isTimeout, isAnomalous: isAnomalous))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(rttColor(isTimeout: isTimeout, isAnomalous: isAnomalous).opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(width: 130)
    }

    private func connectorLine(isAnomalous: Bool, deltaMs: Double?) -> some View {
        VStack(spacing: 2) {
            if let delta = deltaMs, delta > 0.5 {
                Text(String(format: "+%.1fms", delta))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isAnomalous ? Theme.solarAmber : Theme.azurePro.opacity(0.8))
            } else {
                Text(" ")
                    .font(.system(size: 8))
            }

            HStack(spacing: 3) {
                Rectangle()
                    .fill(isAnomalous ? Theme.solarAmber : Theme.azurePro.opacity(0.35))
                    .frame(width: 24, height: isAnomalous ? 2.5 : 1.5)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(isAnomalous ? Theme.solarAmber : Theme.azurePro.opacity(0.6))
            }
        }
        .padding(.bottom, 36)
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
