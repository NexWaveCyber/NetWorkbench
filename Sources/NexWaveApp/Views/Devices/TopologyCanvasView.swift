//
//  TopologyCanvasView.swift
//  NexWaveApp
//
//  Interactive Visual Network Topology Canvas & Architecture Studio (Grade A++++)
//

import SwiftUI
import DeviceKit
import NetworkCore
import PacketKit
import AppKit

public enum TopologyPreset: String, CaseIterable, Identifiable {
    case enterprise = "Enterprise Campus (3-Tier)"
    case dataCenter = "Data Center (Spine-Leaf)"
    case discoveredLAN = "Local Discovered Subnet"
    case managedFleet = "Managed Fleet Inventory"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .enterprise: return "building.2.crop.circle.fill"
        case .dataCenter: return "server.rack"
        case .discoveredLAN: return "antenna.radiowaves.left.and.right"
        case .managedFleet: return "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

public enum TopologyLayoutMode: String, CaseIterable, Identifiable {
    case hierarchical = "Hierarchical"
    case radial = "Radial"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .hierarchical: return "list.bullet.indent"
        case .radial: return "circle.dashed"
        }
    }
}

public enum TrafficSpeed: String, CaseIterable, Identifiable {
    case slow = "Slow (0.1x)"
    case calm = "Calm (0.2x)"
    case brisk = "Brisk (0.35x)"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .slow: return "0.1x"
        case .calm: return "0.2x"
        case .brisk: return "0.35x"
        }
    }

    public var multiplier: Double {
        switch self {
        case .slow: return 0.10
        case .calm: return 0.20
        case .brisk: return 0.35
        }
    }
}

public struct TopologyCanvasView: View {
    @Bindable var state: AppState

    @State private var preset: TopologyPreset = .enterprise
    @State private var layoutMode: TopologyLayoutMode = .hierarchical
    @State private var graph: TopologyGraph = TopologyGraph()
    @State private var selectedNodeId: String? = nil
    @State private var selectedLinkId: String? = nil
    @State private var roleFilter: DeviceRole? = nil

    // Canvas Transform State
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragCurrent: CGSize = .zero

    // Active Node Drag State
    @State private var draggingNodeId: String? = nil
    @State private var dragOffset: CGSize = .zero

    // Simulation & Feature Flags
    @State private var simulateTraffic: Bool = true
    @State private var trafficSpeed: TrafficSpeed = .calm
    @State private var selectedVlanFilter: Int? = nil
    @State private var searchInput: String = ""
    @State private var showMiniMap: Bool = true

    // Path Trace Simulation (A -> B)
    @State private var isPathTraceMode: Bool = false
    @State private var pathTraceSourceId: String? = nil
    @State private var pathTraceTargetId: String? = nil

    // Interactive Cable Patching
    @State private var isPatchCableMode: Bool = false
    @State private var patchCableSourceId: String? = nil
    @State private var patchTargetNode: TopologyNode? = nil
    @State private var showingAddLinkSheet: Bool = false

    // Custom Device Addition
    @State private var showingAddDeviceSheet: Bool = false

    // Toast / Feedback Banner
    @State private var bannerMessage: String? = nil

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            topControlDeck
            Divider().overlay(Theme.borderLight)

            if let neighbor = PassiveNeighborDiscoveryEngine.shared.activeLinkNeighbor {
                activeSwitchBanner(neighbor: neighbor)
            }

            // Path Trace Active HUD
            if isPathTraceMode {
                pathTraceStatusBar
            }

            // Toast feedback banner
            if let banner = bannerMessage {
                feedbackBanner(text: banner)
            }

            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    canvasSurface(size: geo.size)
                        .clipped()

                    // Mini-Map Overview HUD (Bottom-Left)
                    if showMiniMap {
                        miniMapOverview
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(16)
                            .transition(.opacity)
                    }

                    // Floating Zoom & Viewport Controls (Bottom-Right)
                    canvasFloatingControls
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(16)

                    // Node Inspector Drawer (Trailing)
                    if let selected = selectedNode {
                        nodeInspectorDrawer(node: selected)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    // Link Inspector Drawer (Trailing)
                    if let selectedLink = selectedLink {
                        TopologyLinkInspectorView(
                            link: selectedLink,
                            graph: graph,
                            onClose: { selectedLinkId = nil },
                            onDisconnect: {
                                withAnimation {
                                    graph.removeLink(id: selectedLink.id)
                                    selectedLinkId = nil
                                    showToast("Link disconnected and removed from topology.")
                                }
                            }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .onAppear {
                    loadTopology(preset: preset, size: geo.size)
                }
                .onChange(of: state.discoveredNeighbors) { _, _ in
                    if preset == .discoveredLAN {
                        loadTopology(preset: .discoveredLAN, size: geo.size)
                    }
                }
            }
        }
        .background(Theme.surfaceBackground)
        .sheet(isPresented: $showingAddLinkSheet) {
            if let srcId = patchCableSourceId,
               let srcNode = graph.nodes.first(where: { $0.id == srcId }),
               let dstNode = patchTargetNode {
                AddLinkSheet(
                    isPresented: $showingAddLinkSheet,
                    sourceNode: srcNode,
                    targetNode: dstNode,
                    onAddLink: { newLink in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            graph.addLink(newLink)
                            showToast("Patched new cable: \(newLink.sourceInterface) ⟶ \(newLink.targetInterface)")
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddDeviceSheet) {
            AddCanvasDeviceSheet(isPresented: $showingAddDeviceSheet) { newNode in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    graph.addNode(newNode)
                    showToast("Added \(newNode.label) to canvas topology.")
                }
            }
        }
    }

    // MARK: - Selected Node & Link Helpers
    private var selectedNode: TopologyNode? {
        guard let id = selectedNodeId else { return nil }
        return graph.nodes.first(where: { $0.id == id })
    }

    private var selectedLink: TopologyLink? {
        guard let id = selectedLinkId else { return nil }
        return graph.links.first(where: { $0.id == id })
    }

    // MARK: - Active Path Trace Elements
    private var activePathTrace: (nodeIds: [String], linkIds: [String])? {
        guard let src = pathTraceSourceId, let dst = pathTraceTargetId else { return nil }
        return graph.findShortestPath(from: src, to: dst)
    }

    // MARK: - Active VLAN Overlay Elements
    private var activeVlanOverlay: (matchingNodeIds: Set<String>, matchingLinkIds: Set<String>)? {
        guard let vlan = selectedVlanFilter else { return nil }
        return graph.filterByVLAN(vlan)
    }

    // MARK: - Live Coordinates Map
    private func currentPosition(for node: TopologyNode) -> CGPoint {
        if node.id == draggingNodeId {
            return CGPoint(
                x: node.position.x + (dragOffset.width / zoomScale),
                y: node.position.y + (dragOffset.height / zoomScale)
            )
        }
        return node.position
    }

    private var nodePositionsMap: [String: CGPoint] {
        Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, currentPosition(for: $0)) })
    }

    // MARK: - Top Control Deck
    private var topControlDeck: some View {
        VStack(spacing: 8) {
            // Row 1: Presets, Layout, Search, Simulation, Export
            HStack(spacing: 12) {
                // Preset Architecture Picker
                Picker("Topology", selection: $preset) {
                    ForEach(TopologyPreset.allCases) { p in
                        Label(p.rawValue, systemImage: p.icon).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .onChange(of: preset) { _, newPreset in
                    if newPreset == .discoveredLAN && state.discoveredNeighbors.isEmpty {
                        Task { await state.runLocalDiscovery() }
                    }
                    loadTopology(preset: newPreset, size: CGSize(width: 1000, height: 700))
                }

                // Layout Mode Picker
                Picker("Layout", selection: $layoutMode) {
                    ForEach(TopologyLayoutMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .onChange(of: layoutMode) { _, newMode in
                    recalculateLayout(mode: newMode, size: CGSize(width: 1000, height: 700))
                }

                // Reset to Default Algorithmic Layout
                Button(action: {
                    state.resetCanvasLayout(preset: preset.rawValue)
                    recalculateLayout(mode: layoutMode, size: CGSize(width: 1000, height: 700))
                    showToast("Layout reset to default algorithmic positions")
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                .help("Reset custom node drag positions to algorithmic layout")

                // Spotlight Search Input
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search IP, Hostname, Role...", text: $searchInput)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(11))
                        .onSubmit {
                            focusSearchedDevice()
                        }
                    if !searchInput.isEmpty {
                        Button(action: { searchInput = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                .frame(width: 210)

                // Live Traffic Simulation & Speed Menu
                Menu {
                    Button(action: { withAnimation { simulateTraffic.toggle() } }) {
                        Label(simulateTraffic ? "Disable Traffic Simulation" : "Enable Traffic Simulation", systemImage: simulateTraffic ? "stop.circle" : "play.circle")
                    }
                    Divider()
                    Text("PACKET VELOCITY")
                        .font(Theme.monoText(9))
                        .foregroundStyle(.secondary)
                    ForEach(TrafficSpeed.allCases) { speed in
                        Button {
                            trafficSpeed = speed
                            simulateTraffic = true
                        } label: {
                            HStack {
                                Text(speed.rawValue)
                                if trafficSpeed == speed && simulateTraffic {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: simulateTraffic ? "waveform.path.ecg" : "waveform.path")
                        Text(simulateTraffic ? "Traffic (\(trafficSpeed.shortTitle))" : "Traffic Off")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)
                .tint(simulateTraffic ? Theme.cyanPulse : .secondary)
                .help("Configure live packet flow simulation velocity or toggle off")

                // Path Trace Simulator Mode Toggle
                Button(action: togglePathTraceMode) {
                    HStack(spacing: 4) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.filled.curvepath")
                        Text("Path Trace")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .tint(isPathTraceMode ? Theme.signalEmerald : .secondary)

                Spacer()

                // Patch Cable Tool
                Button(action: {
                    withAnimation {
                        isPatchCableMode.toggle()
                        patchCableSourceId = nil
                        if isPatchCableMode {
                            showToast("Cable Patching Mode: Click Source Device, then Target Device.")
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cable.connector")
                        Text(isPatchCableMode ? "Cancel Patch" : "Patch Cable")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .tint(isPatchCableMode ? Theme.solarAmber : Theme.cyanPulse)

                // Add Device Button
                Button(action: { showingAddDeviceSheet = true }) {
                    Label("Add Device", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.electricAzure)

                // Export Menu
                Menu {
                    Button(action: exportTopologyJSON) {
                        Label("Export Architecture JSON", systemImage: "doc.text")
                    }
                    Button(action: exportRetinaPNG) {
                        Label("Save PNG Diagram (Retina)", systemImage: "photo")
                    }
                    Button(action: {
                        recalculateLayout(mode: layoutMode, size: CGSize(width: 1000, height: 700))
                        withAnimation {
                            panOffset = .zero
                            zoomScale = 1.0
                        }
                    }) {
                        Label("Auto-Align All Positions", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.quantumViolet)
            }

            // Row 2: Role Filters, VLAN Overlay Selector, Telemetry Counters
            HStack(spacing: 8) {
                Text("ROLE:")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)

                filterChip(title: "All (\(graph.nodes.count))", role: nil)
                filterChip(title: "Routers (\(nodesForRole(.router).count))", role: .router)
                filterChip(title: "Switches (\(nodesForRole(.switchRole).count))", role: .switchRole)
                filterChip(title: "Firewalls (\(nodesForRole(.firewall).count))", role: .firewall)
                filterChip(title: "APs (\(nodesForRole(.accessPoint).count))", role: .accessPoint)
                filterChip(title: "Servers (\(nodesForRole(.server).count))", role: .server)

                Divider().frame(height: 14)

                // VLAN Isolation Overlay Dropdown
                HStack(spacing: 4) {
                    Text("VLAN OVERLAY:")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)

                    Picker("", selection: $selectedVlanFilter) {
                        Text("All VLANs (Normal)").tag(nil as Int?)
                        Text("VLAN 10 (Management)").tag(10 as Int?)
                        Text("VLAN 20 (Data)").tag(20 as Int?)
                        Text("VLAN 30 (Voice / VoIP)").tag(30 as Int?)
                        Text("VLAN 40 (DMZ / Compute)").tag(40 as Int?)
                        Text("VLAN 99 (Native)").tag(99 as Int?)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                Spacer()

                // Telemetry Tags
                metricTag(title: "NODES", value: "\(graph.nodes.count)", tint: Theme.cyanPulse)
                metricTag(title: "LINKS", value: "\(graph.links.count)", tint: Theme.electricAzure)
                let alarms = graph.nodes.reduce(0) { $0 + $1.alarmsCount }
                metricTag(
                    title: "ALARMS",
                    value: "\(alarms)",
                    tint: alarms > 0 ? Theme.crimsonCritical : Theme.signalEmerald
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.cardBackground.opacity(0.7))
    }

    // MARK: - Canvas Surface (Infinite Pan/Zoom + Isolated Layers)
    private func canvasSurface(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Infinite Canvas Panning Hit Surface
            Color.clear
                .frame(width: 8000, height: 8000)
                .offset(x: -3000, y: -3000)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { val in
                            guard draggingNodeId == nil else { return }
                            dragCurrent = val.translation
                        }
                        .onEnded { val in
                            panOffset.width += dragCurrent.width
                            panOffset.height += dragCurrent.height
                            dragCurrent = .zero
                        }
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedNodeId = nil
                        selectedLinkId = nil
                    }
                }

            // Background Cyber-Grid
            cyberGrid(size: size)

            // Links Base Layer (Static Cables, Badges, Hit Testing)
            linksBaseLayer

            // Animated Live Traffic Particle Overlay (Isolated strictly to its own TimelineView)
            if simulateTraffic {
                trafficParticlesOverlay
            }

            // Nodes Layer with Isolated Coordinate Frame (Stationary, NO 30FPS redraws, rock-solid context menus)
            nodesLayer
        }
        .scaleEffect(zoomScale)
        .offset(x: panOffset.width + dragCurrent.width, y: panOffset.height + dragCurrent.height)
    }

    // MARK: - Background Grid
    private func cyberGrid(size: CGSize) -> some View {
        Canvas { context, sz in
            let step: CGFloat = 40.0
            var path = Path()

            for x in stride(from: 0, through: sz.width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: sz.height))
            }
            for y in stride(from: 0, through: sz.height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: sz.width, y: y))
            }

            context.stroke(path, with: .color(Theme.borderLight.opacity(0.18)), lineWidth: 0.5)
        }
        .frame(width: max(3500, size.width * 3.5), height: max(3500, size.height * 3.5))
        .allowsHitTesting(false)
    }

    // MARK: - Live Traffic Particle Overlay (Isolated TimelineView)
    private var trafficParticlesOverlay: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { timeline in
            let posMap = nodePositionsMap
            let vlanOverlay = activeVlanOverlay
            let pathTrace = activePathTrace
            let timeOffset = timeline.date.timeIntervalSince1970
            let speed = trafficSpeed.multiplier

            ZStack(alignment: .topLeading) {
                ForEach(graph.links) { link in
                    if let src = posMap[link.sourceNodeId], let dst = posMap[link.targetNodeId] {
                        let isLinkInVlan = vlanOverlay == nil || (vlanOverlay?.matchingLinkIds.contains(link.id) == true)
                        if isLinkInVlan {
                            let isLinkInTrace = pathTrace?.linkIds.contains(link.id) == true
                            let strokeColor = isLinkInTrace ? Theme.signalEmerald : Color(hex: link.linkType.badgeColorHex)
                            let curveOffset = graph.curvatureOffset(for: link)

                            let mid = CGPoint(x: (src.x + dst.x) / 2.0, y: (src.y + dst.y) / 2.0)
                            let dx = dst.x - src.x
                            let dy = dst.y - src.y
                            let len = max(1.0, hypot(dx, dy))
                            let nx = -dy / len
                            let ny = dx / len
                            let controlPoint = CGPoint(x: mid.x + nx * curveOffset, y: mid.y + ny * curveOffset)

                            trafficParticles(
                                from: src,
                                to: dst,
                                control: controlPoint,
                                curveOffset: curveOffset,
                                timeOffset: timeOffset,
                                speedMultiplier: speed,
                                color: strokeColor
                            )
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Links Base Layer with Bezier Curvature & Port Badges
    private var linksBaseLayer: some View {
        let posMap = nodePositionsMap
        let vlanOverlay = activeVlanOverlay
        let pathTrace = activePathTrace

        return ForEach(graph.links) { link in
            if let src = posMap[link.sourceNodeId], let dst = posMap[link.targetNodeId] {
                let curveOffset = graph.curvatureOffset(for: link)
                let isLinkInVlan = vlanOverlay == nil || (vlanOverlay?.matchingLinkIds.contains(link.id) == true)
                let isLinkInTrace = pathTrace?.linkIds.contains(link.id) == true

                interactiveLinkView(
                    link: link,
                    from: src,
                    to: dst,
                    curveOffset: curveOffset,
                    isDimmed: !isLinkInVlan,
                    isPathTraced: isLinkInTrace
                )
            }
        }
    }

    private func interactiveLinkView(
        link: TopologyLink,
        from: CGPoint,
        to: CGPoint,
        curveOffset: CGFloat,
        isDimmed: Bool,
        isPathTraced: Bool
    ) -> some View {
        let isConnectedToDragged = draggingNodeId == link.sourceNodeId || draggingNodeId == link.targetNodeId
        let isSelected = selectedLinkId == link.id
        let strokeColor = isPathTraced ? Theme.signalEmerald : Color(hex: link.linkType.badgeColorHex)

        let mid = CGPoint(x: (from.x + to.x) / 2.0, y: (from.y + to.y) / 2.0)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = max(1.0, hypot(dx, dy))
        let nx = -dy / len
        let ny = dx / len
        let controlPoint = CGPoint(x: mid.x + nx * curveOffset, y: mid.y + ny * curveOffset)

        // Path calculation
        var linkPath = Path()
        linkPath.move(to: from)
        if abs(curveOffset) > 1.0 {
            linkPath.addQuadCurve(to: to, control: controlPoint)
        } else {
            linkPath.addLine(to: to)
        }

        let badgeMid = abs(curveOffset) > 1.0 ? controlPoint : mid

        return ZStack(alignment: .topLeading) {
            // Main Cable Stroke
            linkPath
                .stroke(
                    strokeColor.opacity(isDimmed ? 0.12 : (isPathTraced ? 1.0 : (isSelected ? 0.95 : (isConnectedToDragged ? 0.9 : 0.45)))),
                    style: StrokeStyle(
                        lineWidth: isPathTraced ? 3.5 : (isSelected ? 3.0 : (isConnectedToDragged ? 2.5 : 1.5)),
                        dash: link.linkType == .wireless ? [4, 4] : []
                    )
                )
                .shadow(color: isPathTraced ? Theme.signalEmerald.opacity(0.8) : (isSelected ? strokeColor.opacity(0.7) : .clear), radius: 8)

            // Clickable Hit Zone
            linkPath
                .stroke(Color.white.opacity(0.001), lineWidth: 14)
                .contentShape(linkPath)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedLinkId = link.id
                        selectedNodeId = nil
                    }
                }

            // Port Badges
            let srcBadgeOffset = CGPoint(x: from.x + (dx / len) * 44 + nx * (curveOffset * 0.3), y: from.y + (dy / len) * 44 + ny * (curveOffset * 0.3))
            let dstBadgeOffset = CGPoint(x: to.x - (dx / len) * 44 + nx * (curveOffset * 0.3), y: to.y - (dy / len) * 44 + ny * (curveOffset * 0.3))

            // Source Port Badge
            Text(link.sourceInterface)
                .font(Theme.monoText(8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Theme.surfaceBackground)
                .foregroundStyle(strokeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(strokeColor.opacity(0.4), lineWidth: 0.5))
                .offset(x: srcBadgeOffset.x - 18, y: srcBadgeOffset.y - 7)
                .opacity(isDimmed ? 0.2 : 1.0)
                .allowsHitTesting(false)

            // Destination Port Badge
            Text(link.targetInterface)
                .font(Theme.monoText(8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Theme.surfaceBackground)
                .foregroundStyle(strokeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(strokeColor.opacity(0.4), lineWidth: 0.5))
                .offset(x: dstBadgeOffset.x - 18, y: dstBadgeOffset.y - 7)
                .opacity(isDimmed ? 0.2 : 1.0)
                .allowsHitTesting(false)

            // High-Speed 100G Badge or Port-Channel Badge
            if link.speedMbps >= 100_000 || link.linkType == .portChannel {
                Text(link.linkType == .portChannel ? "LACP Po1" : "100G")
                    .font(Theme.monoText(8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(link.linkType == .portChannel ? Theme.solarAmber : Theme.quantumViolet)
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                    .offset(x: badgeMid.x - 18, y: badgeMid.y - 8)
                    .opacity(isDimmed ? 0.2 : 1.0)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Traffic Flow Animated Particles
    private func trafficParticles(
        from: CGPoint,
        to: CGPoint,
        control: CGPoint,
        curveOffset: CGFloat,
        timeOffset: Double,
        speedMultiplier: Double,
        color: Color
    ) -> some View {
        let particle1T = (timeOffset * speedMultiplier).truncatingRemainder(dividingBy: 1.0)
        let particle2T = ((timeOffset * speedMultiplier) + 0.5).truncatingRemainder(dividingBy: 1.0)

        let p1 = pointAlongCurve(t: CGFloat(particle1T), from: from, to: to, control: control, curveOffset: curveOffset)
        let p2 = pointAlongCurve(t: CGFloat(particle2T), from: from, to: to, control: control, curveOffset: curveOffset)

        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
                .shadow(color: color.opacity(0.9), radius: 4)
                .offset(x: p1.x - 2.25, y: p1.y - 2.25)

            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
                .shadow(color: color.opacity(0.9), radius: 4)
                .offset(x: p2.x - 2.25, y: p2.y - 2.25)
        }
        .allowsHitTesting(false)
    }

    private func pointAlongCurve(t: CGFloat, from: CGPoint, to: CGPoint, control: CGPoint, curveOffset: CGFloat) -> CGPoint {
        if abs(curveOffset) > 1.0 {
            // Quadratic Bezier interpolation: B(t) = (1-t)^2 * P0 + 2(1-t)t * P1 + t^2 * P2
            let oneMinusT = 1.0 - t
            let x = oneMinusT * oneMinusT * from.x + 2.0 * oneMinusT * t * control.x + t * t * to.x
            let y = oneMinusT * oneMinusT * from.y + 2.0 * oneMinusT * t * control.y + t * t * to.y
            return CGPoint(x: x, y: y)
        } else {
            // Linear interpolation
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    // MARK: - Nodes Layer (Strict Isolated Coordinates & Stationary Drag Anchor)
    private var nodesLayer: some View {
        ZStack(alignment: .topLeading) {
            let vlanOverlay = activeVlanOverlay
            let pathTrace = activePathTrace
            let searchLower = searchInput.trimmingCharacters(in: .whitespaces).lowercased()

            ForEach(visibleNodes) { node in
                let pos = currentPosition(for: node)
                let isBeingDragged = draggingNodeId == node.id
                let isSelected = selectedNodeId == node.id

                let isVlanMatch = vlanOverlay == nil || vlanOverlay?.matchingNodeIds.contains(node.id) == true
                let pathHopIndex = pathTrace?.nodeIds.firstIndex(of: node.id)
                let isSearchMatch = !searchLower.isEmpty && (node.label.lowercased().contains(searchLower) || node.ipAddress.contains(searchLower) || node.role.rawValue.lowercased().contains(searchLower))

                nodeCard(
                    node: node,
                    isBeingDragged: isBeingDragged,
                    isSelected: isSelected,
                    isDimmed: !isVlanMatch,
                    pathHopIndex: pathHopIndex,
                    isSearchMatch: isSearchMatch
                )
                .frame(width: 156, height: 92)
                .contentShape(Rectangle())
                .contextMenu {
                    nodeContextMenu(for: node)
                }
                .offset(x: pos.x - 78, y: pos.y - 46)
                .zIndex(isBeingDragged ? 300 : (pathHopIndex != nil ? 250 : (isSelected ? 200 : Double(node.tier.tierLevel * -1))))
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { val in
                            if draggingNodeId == nil {
                                draggingNodeId = node.id
                            }
                            if draggingNodeId == node.id {
                                dragOffset = val.translation
                            }
                        }
                        .onEnded { val in
                            if draggingNodeId == node.id {
                                let distSq = val.translation.width * val.translation.width + val.translation.height * val.translation.height
                                if distSq < 16 {
                                    handleNodeTap(node: node)
                                } else {
                                    // Commit Permanent Drag Offset
                                    if let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) {
                                        let deltaX = val.translation.width / zoomScale
                                        let deltaY = val.translation.height / zoomScale
                                        let newPos = CGPoint(
                                            x: graph.nodes[idx].position.x + deltaX,
                                            y: graph.nodes[idx].position.y + deltaY
                                        )
                                        graph.nodes[idx].position = newPos
                                        state.saveCanvasNodePosition(preset: preset.rawValue, nodeId: node.id, position: newPos)
                                    }
                                }
                            }
                            draggingNodeId = nil
                            dragOffset = .zero
                        }
                )
            }
        }
    }

    private func handleNodeTap(node: TopologyNode) {
        if isPathTraceMode {
            if pathTraceSourceId == nil {
                pathTraceSourceId = node.id
                showToast("Source set: \(node.label). Now click Destination Device.")
            } else if pathTraceTargetId == nil && node.id != pathTraceSourceId {
                pathTraceTargetId = node.id
                showToast("Tracing forwarding path: \(pathTraceSourceId ?? "") ⟶ \(node.label)")
            } else {
                pathTraceSourceId = node.id
                pathTraceTargetId = nil
            }
            return
        }

        if isPatchCableMode {
            if patchCableSourceId == nil {
                patchCableSourceId = node.id
                showToast("Source device selected: \(node.label). Now click target device.")
            } else if node.id != patchCableSourceId {
                patchTargetNode = node
                showingAddLinkSheet = true
                isPatchCableMode = false
            }
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if selectedNodeId == node.id {
                selectedNodeId = nil
            } else {
                selectedNodeId = node.id
                selectedLinkId = nil
            }
        }
    }

    // MARK: - Node Card View
    private func nodeCard(
        node: TopologyNode,
        isBeingDragged: Bool,
        isSelected: Bool,
        isDimmed: Bool,
        pathHopIndex: Int?,
        isSearchMatch: Bool
    ) -> some View {
        let roleColor = colorForRole(node.role)

        // Resolve friendly primary title - strictly never duplicate the IP address
        let titleText: String = {
            if !node.label.isEmpty && node.label != node.ipAddress {
                return node.label
            }
            if let plat = node.platform, !plat.isEmpty {
                return plat
            }
            if node.vendor != .generic {
                return "\(node.vendor.rawValue) Host"
            }
            let lastOctet = node.ipAddress.components(separatedBy: ".").last ?? ""
            return lastOctet.isEmpty ? "Network Host" : "Host .\(lastOctet)"
        }()

        // Resolve vendor badge text if known
        let vendorBadgeText: String? = {
            if node.vendor != .generic {
                return node.vendor.rawValue.uppercased()
            }
            if let plat = node.platform, !plat.isEmpty {
                let firstWord = plat.components(separatedBy: " ").first ?? plat
                return firstWord.uppercased()
            }
            return nil
        }()

        return VStack(spacing: 2.5) {
            ZStack {
                // Glow Halo
                Circle()
                    .fill(roleColor.opacity(isBeingDragged ? 0.42 : (pathHopIndex != nil ? 0.35 : (isSelected ? 0.28 : 0.12))))
                    .frame(width: isBeingDragged ? 42 : 36, height: isBeingDragged ? 42 : 36)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSearchMatch ? Theme.neonCyan : (isBeingDragged ? Theme.cyanPulse : (pathHopIndex != nil ? Theme.signalEmerald : (isSelected ? Theme.neonCyan : roleColor.opacity(0.6)))),
                                lineWidth: isSearchMatch ? 2.5 : (isBeingDragged ? 2.2 : (pathHopIndex != nil ? 2.0 : (isSelected ? 1.8 : 1.0)))
                            )
                    )
                    .shadow(color: isSearchMatch ? Theme.cyanPulse : (isBeingDragged ? Theme.cyanPulse.opacity(0.8) : (isSelected ? Theme.neonCyan.opacity(0.5) : .clear)), radius: isSearchMatch ? 12 : (isBeingDragged ? 10 : 6))

                // Role Icon
                Image(systemName: node.role.iconName)
                    .font(.system(size: isBeingDragged ? 16 : 14, weight: .bold))
                    .foregroundStyle(isBeingDragged ? Theme.cyanPulse : (pathHopIndex != nil ? Theme.signalEmerald : (isSelected ? Theme.neonCyan : roleColor)))

                // Alarm badge
                if node.alarmsCount > 0 {
                    Circle()
                        .fill(Theme.crimsonCritical)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Text("\(node.alarmsCount)")
                                .font(Theme.monoText(8, weight: .bold))
                                .foregroundStyle(Color.white)
                        )
                        .offset(x: 14, y: -14)
                }

                // Path Trace Hop Badge
                if let hop = pathHopIndex {
                    Circle()
                        .fill(Theme.signalEmerald)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Text("H\(hop + 1)")
                                .font(Theme.monoText(8, weight: .black))
                                .foregroundStyle(Color.black)
                        )
                        .offset(x: -14, y: -14)
                }
            }

            // Primary Hostname / Device Title (Never Duplicate IP!)
            Text(titleText)
                .font(Theme.monoText(9.5, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Theme.surfaceBackground.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSearchMatch ? Theme.cyanPulse : (isBeingDragged ? Theme.cyanPulse.opacity(0.8) : Color.clear), lineWidth: 1)
                )

            // IP Address (Single display in bright electric cyan)
            Text(node.ipAddress)
                .font(Theme.monoText(8.5, weight: .medium))
                .foregroundStyle(isBeingDragged ? Theme.cyanPulse : Theme.neonCyan)
                .lineLimit(1)

            // Hardware Metadata: Vendor Badge & MAC Address & IPv6 indicator
            HStack(spacing: 3) {
                if let vBadge = vendorBadgeText {
                    Text(vBadge)
                        .font(Theme.monoText(7, weight: .bold))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(Theme.azurePro.opacity(0.25))
                        .foregroundStyle(Theme.azurePro)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5))
                        .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Theme.azurePro.opacity(0.4), lineWidth: 0.5))
                        .lineLimit(1)
                }

                if node.ipv6Address != nil && node.ipv6Address != node.ipAddress {
                    Text("IPv6")
                        .font(Theme.monoText(7, weight: .bold))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(Theme.electricAzure.opacity(0.25))
                        .foregroundStyle(Theme.cyanPulse)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5))
                        .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Theme.cyanPulse.opacity(0.5), lineWidth: 0.5))
                        .lineLimit(1)
                }

                if let mac = node.macAddress, !mac.isEmpty {
                    Text(mac)
                        .font(Theme.monoText(7.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .scaleEffect(isBeingDragged ? 1.08 : 1.0)
        .opacity(isDimmed ? 0.18 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isBeingDragged)
    }

    // MARK: - Node Context Menu
    @ViewBuilder
    private func nodeContextMenu(for node: TopologyNode) -> some View {
        Button {
            state.targetInput = node.ipAddress
            state.selectedWorkspace = .diagnose
        } label: {
            Label("Diagnose Host (\(node.ipAddress))", systemImage: "stethoscope")
        }

        Button {
            state.selectedWorkspace = .snmp
        } label: {
            Label("Query SNMP MIBs", systemImage: "chart.bar.xaxis")
        }

        Button {
            state.terminalManager.openSSHSession(host: node.ipAddress)
            state.selectedWorkspace = .terminal
        } label: {
            Label("Open SSH Terminal", systemImage: "terminal.fill")
        }

        Divider()

        Button {
            pathTraceSourceId = node.id
            isPathTraceMode = true
            showToast("Path Trace: Source set to \(node.label). Click destination node.")
        } label: {
            Label("Trace Path from Here...", systemImage: "point.topleft.down.to.point.bottomright.filled.curvepath")
        }

        Button {
            isPatchCableMode = true
            patchCableSourceId = node.id
            showToast("Patch Cable: Source set to \(node.label). Click target device.")
        } label: {
            Label("Patch Cable from Port...", systemImage: "cable.connector")
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.ipAddress, forType: .string)
            showToast("Copied IP: \(node.ipAddress)")
        } label: {
            Label("Copy IP Address (\(node.ipAddress))", systemImage: "doc.on.doc")
        }

        if let mac = node.macAddress {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mac, forType: .string)
                showToast("Copied MAC: \(mac)")
            } label: {
                Label("Copy MAC Address (\(mac))", systemImage: "number")
            }
        }

        if let v6 = node.ipv6Address, v6 != node.ipAddress {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(v6, forType: .string)
                showToast("Copied IPv6: \(v6)")
            } label: {
                Label("Copy Unique IPv6 (\(v6))", systemImage: "network")
            }
        }

        Divider()

        Button(role: .destructive) {
            withAnimation {
                graph.removeNode(id: node.id)
                if selectedNodeId == node.id { selectedNodeId = nil }
                showToast("Removed \(node.label) from canvas.")
            }
        } label: {
            Label("Delete Node from Canvas", systemImage: "trash")
        }
    }

    // MARK: - Mini-Map Overview HUD
    private var miniMapOverview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "map.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.cyanPulse)
                Text("MINI-MAP")
                    .font(Theme.monoText(8, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        panOffset = .zero
                        zoomScale = 1.0
                    }
                }) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.cyanPulse)
                }
                .buttonStyle(.plain)
                .help("Fit & Center Map")
            }

            // Canvas Mini Footprint
            Canvas { context, sz in
                let scaleX = sz.width / 1100.0
                let scaleY = sz.height / 750.0

                // Draw links
                for link in graph.links {
                    if let src = graph.nodes.first(where: { $0.id == link.sourceNodeId })?.position,
                       let dst = graph.nodes.first(where: { $0.id == link.targetNodeId })?.position {
                        var path = Path()
                        path.move(to: CGPoint(x: src.x * scaleX, y: src.y * scaleY))
                        path.addLine(to: CGPoint(x: dst.x * scaleX, y: dst.y * scaleY))
                        context.stroke(path, with: .color(Color(hex: link.linkType.badgeColorHex).opacity(0.4)), lineWidth: 1)
                    }
                }

                // Draw nodes
                for node in graph.nodes {
                    let pt = CGPoint(x: node.position.x * scaleX, y: node.position.y * scaleY)
                    let rect = CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7)
                    let color = colorForRole(node.role)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
            .frame(width: 140, height: 85)
            .background(Theme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
        }
        .padding(8)
        .background(Theme.cardBackground.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
        .shadow(radius: 8)
    }

    // MARK: - Floating Zoom Controls
    private var canvasFloatingControls: some View {
        HStack(spacing: 6) {
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    zoomScale = max(0.4, zoomScale - 0.15)
                }
            }) {
                Image(systemName: "minus.magnifyingglass")
                    .padding(6)
            }
            .buttonStyle(.plain)

            Text("\(Int(zoomScale * 100))%")
                .font(Theme.monoText(10, weight: .bold))
                .frame(width: 42)

            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    zoomScale = min(2.5, zoomScale + 0.15)
                }
            }) {
                Image(systemName: "plus.magnifyingglass")
                    .padding(6)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 14)

            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    zoomScale = 1.0
                    panOffset = .zero
                }
            }) {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("Reset Zoom & Pan (100%)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.cardBackground.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.borderLight, lineWidth: 1))
        .shadow(radius: 6)
    }

    // MARK: - Node Inspector Drawer
    private func nodeInspectorDrawer(node: TopologyNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: node.role.iconName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colorForRole(node.role))
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.label)
                        .font(Theme.monoText(13, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("\(node.role.rawValue) • \(node.tier.rawValue)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { selectedNodeId = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Theme.borderLight)

            // Properties Grid
            VStack(spacing: 8) {
                inspectorRow(label: "IP Address", value: node.ipAddress)
                if let v6 = node.ipv6Address, v6 != node.ipAddress {
                    inspectorRow(label: "Unique IPv6", value: v6)
                }
                if let mac = node.macAddress {
                    inspectorRow(label: "MAC Address", value: mac)
                }
                inspectorRow(label: "Vendor", value: node.vendor.rawValue)
                if let platform = node.platform {
                    inspectorRow(label: "Platform", value: platform)
                }
                inspectorRow(label: "Status", value: node.status.rawValue)
                if !node.vlans.isEmpty {
                    inspectorRow(label: "Active VLANs", value: node.vlans.map { "\($0)" }.joined(separator: ", "))
                }
            }

            Divider().overlay(Theme.borderLight)

            // Connected Links & Neighbor Ports
            let connectedLinks = graph.links.filter { $0.sourceNodeId == node.id || $0.targetNodeId == node.id }
            Text("CONNECTED INTERFACES (\(connectedLinks.count))")
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(connectedLinks) { link in
                        connectedLinkRow(link: link, for: node)
                    }
                }
            }
            .frame(maxHeight: 160)

            Divider().overlay(Theme.borderLight)

            // Quick Actions
            VStack(spacing: 8) {
                Button(action: {
                    state.targetInput = node.ipAddress
                    state.selectedWorkspace = .diagnose
                }) {
                    Label("Diagnose Host", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)

                HStack(spacing: 8) {
                    Button(action: {
                        state.selectedWorkspace = .snmp
                    }) {
                        Label("Query SNMP", systemImage: "chart.bar.xaxis")
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.electricAzure)

                    Button(action: {
                        state.terminalManager.openSSHSession(host: node.ipAddress)
                        state.selectedWorkspace = .terminal
                    }) {
                        Label("Open Terminal", systemImage: "terminal.fill")
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.quantumViolet)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.cardBackground.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
        .shadow(radius: 12)
        .padding(16)
    }

    private func inspectorRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoText(11, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    private func connectedLinkRow(link: TopologyLink, for node: TopologyNode) -> some View {
        let isSource = link.sourceNodeId == node.id
        let localIntf = isSource ? link.sourceInterface : link.targetInterface
        let remoteIntf = isSource ? link.targetInterface : link.sourceInterface
        let remoteId = isSource ? link.targetNodeId : link.sourceNodeId
        let remoteNode = graph.nodes.first(where: { $0.id == remoteId })

        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(localIntf)
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Color(hex: link.linkType.badgeColorHex))
                Text("Link: \(link.linkType.rawValue)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(remoteNode?.label ?? remoteId)
                    .font(Theme.monoText(10, weight: .semibold))
                Text(remoteIntf)
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Theme.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Path Trace Status Bar HUD
    private var pathTraceStatusBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.filled.curvepath")
                .foregroundStyle(Theme.signalEmerald)
            VStack(alignment: .leading, spacing: 1) {
                Text("LAYER 2 / LAYER 3 PATH TRACE SIMULATOR")
                    .font(Theme.monoText(9, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
                if let trace = activePathTrace {
                    let nodeNames = trace.nodeIds.compactMap { id in graph.nodes.first(where: { $0.id == id })?.label ?? id }
                    Text("PATH: \(nodeNames.joined(separator: " ⟶ ")) (\(trace.linkIds.count) Hops)")
                        .font(Theme.monoText(11, weight: .bold))
                        .foregroundStyle(Color.white)
                } else if pathTraceSourceId != nil {
                    Text("SOURCE: \(graph.nodes.first(where: { $0.id == pathTraceSourceId })?.label ?? "") — Now click Destination Device on canvas")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white)
                } else {
                    Text("Click any node on the canvas to set Path Source")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Clear Trace") {
                withAnimation {
                    pathTraceSourceId = nil
                    pathTraceTargetId = nil
                    isPathTraceMode = false
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.signalEmerald)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.cardBackground.opacity(0.95))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.signalEmerald.opacity(0.4)), alignment: .bottom)
    }

    // MARK: - Feedback Banner
    private func feedbackBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.cyanPulse)
            Text(text)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(Color.white)
            Spacer()
            Button(action: { bannerMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.cyanPulse.opacity(0.18))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.cyanPulse.opacity(0.4)), alignment: .bottom)
    }

    private func showToast(_ message: String) {
        withAnimation {
            bannerMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation {
                if bannerMessage == message {
                    bannerMessage = nil
                }
            }
        }
    }

    // MARK: - Helper Actions
    private func togglePathTraceMode() {
        withAnimation {
            isPathTraceMode.toggle()
            if isPathTraceMode {
                pathTraceSourceId = nil
                pathTraceTargetId = nil
                showToast("Path Trace Mode active: Click Source device, then Target device.")
            } else {
                pathTraceSourceId = nil
                pathTraceTargetId = nil
            }
        }
    }

    private func focusSearchedDevice() {
        let q = searchInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return }
        if let match = graph.nodes.first(where: { $0.label.lowercased().contains(q) || $0.ipAddress.contains(q) }) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedNodeId = match.id
                selectedLinkId = nil
                // Center viewport on matched node
                panOffset = CGSize(width: 500 - match.position.x, height: 350 - match.position.y)
                zoomScale = 1.25
            }
            showToast("Focused on: \(match.label) (\(match.ipAddress))")
        }
    }

    private func exportTopologyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(graph),
           let jsonString = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
            showToast("Topology JSON Spec copied to Clipboard!")
        }
    }

    private func exportRetinaPNG() {
        // High-resolution diagram export
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "network_topology_\(preset.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")).png"

        savePanel.begin { result in
            if result == .OK, let targetURL = savePanel.url {
                let renderer = ImageRenderer(content:
                    ZStack {
                        Theme.surfaceBackground
                        cyberGrid(size: CGSize(width: 1400, height: 900))
                        linksBaseLayer
                        nodesLayer
                    }
                    .frame(width: 1400, height: 900)
                )
                renderer.scale = 2.0 // 2x Retina Resolution
                if let image = renderer.nsImage {
                    if let tiff = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: targetURL)
                        showToast("Saved 2x Retina PNG Diagram to \(targetURL.lastPathComponent)")
                    }
                }
            }
        }
    }

    private func metricTag(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(Theme.monoText(9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.borderLight, lineWidth: 1))
    }

    private func filterChip(title: String, role: DeviceRole?) -> some View {
        let isSelected = roleFilter == role
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                roleFilter = role
            }
        }) {
            Text(title)
                .font(Theme.monoText(10, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Theme.cyanPulse.opacity(0.18) : Theme.cardBackground)
                .foregroundStyle(isSelected ? Theme.cyanPulse : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Theme.cyanPulse.opacity(0.5) : Theme.borderLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func nodesForRole(_ role: DeviceRole) -> [TopologyNode] {
        graph.nodes.filter { $0.role == role }
    }

    private var visibleNodes: [TopologyNode] {
        if let role = roleFilter {
            return graph.nodes.filter { $0.role == role }
        }
        return graph.nodes
    }

    private func applySavedPositions(to graph: inout TopologyGraph, preset: TopologyPreset) {
        let saved = state.loadCanvasNodePositions(preset: preset.rawValue)
        guard !saved.isEmpty else { return }
        for i in 0..<graph.nodes.count {
            if let savedPos = saved[graph.nodes[i].id] {
                graph.nodes[i].position = savedPos
            }
        }
    }

    private func loadTopology(preset: TopologyPreset, size: CGSize) {
        switch preset {
        case .enterprise:
            var g = TopologyGraph.buildEnterpriseDemo(bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
            applySavedPositions(to: &g, preset: preset)
            self.graph = g

        case .dataCenter:
            var g = TopologyGraph.buildDataCenterDemo(bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
            applySavedPositions(to: &g, preset: preset)
            self.graph = g

        case .discoveredLAN:
            let liveGW = MenuBarMonitorEngine.shared.defaultGateway.isEmpty ? "192.168.10.1" : MenuBarMonitorEngine.shared.defaultGateway
            var g = TopologyGraph.buildFromDiscoveredLAN(neighbors: state.discoveredNeighbors, gatewayIP: liveGW, bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
            applySavedPositions(to: &g, preset: preset)
            self.graph = g

        case .managedFleet:
            var g = TopologyGraph.buildFromInventory(devices: state.managedDevices, bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
            applySavedPositions(to: &g, preset: preset)
            self.graph = g
        }
    }

    private func recalculateLayout(mode: TopologyLayoutMode, size: CGSize) {
        recalculateLayout(graph: &self.graph, mode: mode, size: size)
    }

    private func recalculateLayout(graph: inout TopologyGraph, mode: TopologyLayoutMode, size: CGSize) {
        switch mode {
        case .hierarchical:
            graph.applyHierarchicalLayout(bounds: size)
        case .radial:
            graph.applyRadialLayout(bounds: size)
        }
    }

    private func colorForRole(_ role: DeviceRole) -> Color {
        switch role {
        case .router: return Theme.neonCyan
        case .switchRole: return Theme.electricAzure
        case .firewall: return Theme.crimsonCritical
        case .accessPoint: return Theme.signalEmerald
        case .server: return Theme.quantumViolet
        case .workstation: return Theme.solarAmber
        case .other: return Color.gray
        }
    }

    // MARK: - Active Switch Link Banner & Auto-Wiring
    private func activeSwitchBanner(neighbor: DiscoveredSwitchNeighbor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.cyanPulse)

            Text("ETHERNET SWITCH DETECTED:")
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(Theme.cyanPulse)

            Text(neighbor.displayTitle)
                .font(Theme.monoText(11, weight: .medium))
                .foregroundStyle(Color.white)

            Spacer()

            Button(action: {
                addDiscoveredSwitchToGraph(neighbor: neighbor)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                    Text("Add Switch to Canvas")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.cyanPulse.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.cardBackground.opacity(0.95))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.cyanPulse.opacity(0.3)),
            alignment: .bottom
        )
    }

    private func addDiscoveredSwitchToGraph(neighbor: DiscoveredSwitchNeighbor) {
        let nodeId = "discovered-\(neighbor.systemName.lowercased())"
        if !graph.nodes.contains(where: { $0.id == nodeId }) {
            let newNode = TopologyNode(
                id: nodeId,
                label: neighbor.systemName,
                role: .switchRole,
                vendor: neighbor.sourceProtocol == "CDP" ? .cisco : .generic,
                ipAddress: neighbor.managementIP ?? "Dynamic",
                platform: neighbor.platform.isEmpty ? nil : neighbor.platform,
                status: .online,
                tier: .access,
                position: CGPoint(x: 450, y: 280),
                vlans: neighbor.vlan != nil ? [neighbor.vlan!] : [1]
            )
            graph.nodes.append(newNode)

            if let hostNode = graph.nodes.first(where: { $0.role == .workstation || $0.label.contains("Mac") || $0.role == .router }) {
                let link = TopologyLink(
                    sourceNodeId: hostNode.id,
                    targetNodeId: newNode.id,
                    sourceInterface: "en0",
                    targetInterface: neighbor.portName,
                    linkType: .ethernet,
                    speedMbps: 1_000,
                    status: .online,
                    vlanId: neighbor.vlan
                )
                graph.links.append(link)
            }
        }
    }
}
