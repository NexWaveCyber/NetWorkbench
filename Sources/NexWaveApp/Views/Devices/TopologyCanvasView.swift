//
//  TopologyCanvasView.swift
//  NexWaveApp
//
//  Interactive Visual Network Topology Canvas & Architecture Map (Grade A++++)
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

public struct TopologyCanvasView: View {
    @Bindable var state: AppState

    @State private var preset: TopologyPreset = .enterprise
    @State private var layoutMode: TopologyLayoutMode = .hierarchical
    @State private var graph: TopologyGraph = TopologyGraph()
    @State private var selectedNodeId: String? = nil
    @State private var roleFilter: DeviceRole? = nil

    // Canvas Transform State
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragCurrent: CGSize = .zero

    // Active Node Drag State
    @State private var draggingNodeId: String? = nil
    @State private var dragOffset: CGSize = .zero

    // UI Feedback State
    @State private var copyBannerText: String? = nil
    @State private var showMiniMap: Bool = true

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbarDeck
            Divider().overlay(Theme.borderLight)

            if let neighbor = PassiveNeighborDiscoveryEngine.shared.activeLinkNeighbor {
                activeSwitchBanner(neighbor: neighbor)
            }

            if let banner = copyBannerText {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.signalEmerald)
                    Text(banner)
                        .font(Theme.monoText(11, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Button(action: { copyBannerText = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Theme.signalEmerald.opacity(0.18))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.signalEmerald.opacity(0.4)), alignment: .bottom)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    canvasSurface(size: geo.size)
                        .clipped()

                    // Mini-Map Navigator (Bottom-Left)
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

                    // Node Inspector Drawer (Trailing Side)
                    if let selected = selectedNode {
                        nodeInspectorDrawer(node: selected)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .onAppear {
                    loadTopology(preset: preset, size: geo.size)
                }
            }
        }
        .background(Theme.surfaceBackground)
    }

    // MARK: - Selected Node Helper
    private var selectedNode: TopologyNode? {
        guard let id = selectedNodeId else { return nil }
        return graph.nodes.first(where: { $0.id == id })
    }

    // MARK: - Current Live Node Coordinates
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

    // MARK: - Toolbar Deck
    private var toolbarDeck: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                // Preset Selector
                Picker("Topology Architecture", selection: $preset) {
                    ForEach(TopologyPreset.allCases) { p in
                        Label(p.rawValue, systemImage: p.icon).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)
                .onChange(of: preset) { _, newPreset in
                    loadTopology(preset: newPreset, size: CGSize(width: 1000, height: 700))
                }

                // Layout Mode Picker
                Picker("Layout", selection: $layoutMode) {
                    ForEach(TopologyLayoutMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: layoutMode) { _, newMode in
                    recalculateLayout(mode: newMode, size: CGSize(width: 1000, height: 700))
                }

                // Auto-Layout Button
                Button(action: {
                    recalculateLayout(mode: layoutMode, size: CGSize(width: 1000, height: 700))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        panOffset = .zero
                        zoomScale = 1.0
                    }
                }) {
                    Label("Auto-Layout", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.cyanPulse)

                // Export Topology Spec Button
                Button(action: { exportTopologyJSON() }) {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.electricAzure)

                // Toggle Mini-Map
                Button(action: { withAnimation { showMiniMap.toggle() } }) {
                    Label(showMiniMap ? "Hide Map" : "Show Map", systemImage: showMiniMap ? "map.fill" : "map")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(showMiniMap ? Theme.quantumViolet : .secondary)

                Spacer()

                // Telemetry pill
                HStack(spacing: 8) {
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

            // Role Filter Chips
            HStack(spacing: 6) {
                Text("FILTER:")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)

                filterChip(title: "All (\(graph.nodes.count))", role: nil)
                filterChip(title: "Routers (\(nodesForRole(.router).count))", role: .router)
                filterChip(title: "Switches (\(nodesForRole(.switchRole).count))", role: .switchRole)
                filterChip(title: "Firewalls (\(nodesForRole(.firewall).count))", role: .firewall)
                filterChip(title: "Access Points (\(nodesForRole(.accessPoint).count))", role: .accessPoint)
                filterChip(title: "Servers (\(nodesForRole(.server).count))", role: .server)

                Spacer()

                Text("Drag any device to reposition • Right-click for options • Scroll to pan")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cardBackground.opacity(0.6))
    }

    private func exportTopologyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(graph),
           let jsonString = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
            withAnimation {
                copyBannerText = "Topology Architecture Specification copied to Clipboard as formatted JSON!"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation {
                    if copyBannerText?.contains("Specification") == true {
                        copyBannerText = nil
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

    // MARK: - Visible Nodes
    private var visibleNodes: [TopologyNode] {
        if let role = roleFilter {
            return graph.nodes.filter { $0.role == role }
        }
        return graph.nodes
    }

    // MARK: - Canvas Surface
    private func canvasSurface(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Infinite Background Panning Hit Surface
            Color.clear
                .frame(width: 6000, height: 6000)
                .offset(x: -2000, y: -2000)
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
                    }
                }

            // Cyber-Grid Background Layer
            cyberGrid(size: size)

            // Links Layer (Non-blocking hit-test)
            linksLayer
                .allowsHitTesting(false)

            // Nodes Layer (Strict 140x75 hit-target frames)
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

            context.stroke(path, with: .color(Theme.borderLight.opacity(0.2)), lineWidth: 0.5)
        }
        .frame(width: max(3000, size.width * 3), height: max(3000, size.height * 3))
        .allowsHitTesting(false)
    }

    // MARK: - Links Layer
    private var linksLayer: some View {
        ZStack(alignment: .topLeading) {
            let posMap = nodePositionsMap
            ForEach(graph.links) { link in
                if let src = posMap[link.sourceNodeId], let dst = posMap[link.targetNodeId] {
                    linkView(link: link, from: src, to: dst)
                }
            }
        }
    }

    private func linkView(link: TopologyLink, from: CGPoint, to: CGPoint) -> some View {
        let isConnectedToDragged = draggingNodeId == link.sourceNodeId || draggingNodeId == link.targetNodeId
        let isSelected = selectedNodeId == link.sourceNodeId || selectedNodeId == link.targetNodeId
        let strokeColor = Color(hex: link.linkType.badgeColorHex)

        let mid = CGPoint(x: (from.x + to.x) / 2.0, y: (from.y + to.y) / 2.0)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = max(1.0, hypot(dx, dy))

        // Offsets for interface badges near endpoints
        let srcBadgeOffset = CGPoint(x: from.x + (dx / len) * 45, y: from.y + (dy / len) * 45)
        let dstBadgeOffset = CGPoint(x: to.x - (dx / len) * 45, y: to.y - (dy / len) * 45)

        return ZStack(alignment: .topLeading) {
            // Main Link Line
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .stroke(
                strokeColor.opacity(isConnectedToDragged ? 1.0 : (isSelected ? 0.9 : 0.45)),
                style: StrokeStyle(
                    lineWidth: isConnectedToDragged ? 2.8 : (isSelected ? 2.5 : 1.5),
                    dash: link.linkType == .wireless ? [4, 4] : []
                )
            )
            .shadow(color: isConnectedToDragged ? strokeColor.opacity(0.8) : .clear, radius: 6)

            // Interface Pill at Source End
            Text(link.sourceInterface)
                .font(Theme.monoText(8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Theme.surfaceBackground)
                .foregroundStyle(strokeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(strokeColor.opacity(0.4), lineWidth: 0.5))
                .offset(x: srcBadgeOffset.x - 20, y: srcBadgeOffset.y - 8)

            // Interface Pill at Destination End
            Text(link.targetInterface)
                .font(Theme.monoText(8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Theme.surfaceBackground)
                .foregroundStyle(strokeColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(strokeColor.opacity(0.4), lineWidth: 0.5))
                .offset(x: dstBadgeOffset.x - 20, y: dstBadgeOffset.y - 8)

            // Speed badge in middle if high-speed
            if link.speedMbps >= 100_000 {
                Text("100G")
                    .font(Theme.monoText(8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.quantumViolet)
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                    .offset(x: mid.x - 14, y: mid.y - 7)
            }
        }
    }

    // MARK: - Nodes Layer (Strict Isolated Coordinates & Drag Anchor)
    private var nodesLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleNodes) { node in
                let pos = currentPosition(for: node)
                let isBeingDragged = draggingNodeId == node.id
                let isSelected = selectedNodeId == node.id

                nodeCard(node: node, isBeingDragged: isBeingDragged, isSelected: isSelected)
                    .frame(width: 140, height: 75)
                    .contentShape(Rectangle())
                    .offset(x: pos.x - 70, y: pos.y - 37.5)
                    .zIndex(isBeingDragged ? 200 : (isSelected ? 100 : Double(node.tier.tierLevel * -1)))
                    .gesture(
                        DragGesture(minimumDistance: 2)
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
                                        // Tap / Click
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            if selectedNodeId == node.id {
                                                selectedNodeId = nil
                                            } else {
                                                selectedNodeId = node.id
                                            }
                                        }
                                    } else {
                                        // Commit Permanent Drag Offset
                                        if let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) {
                                            let deltaX = val.translation.width / zoomScale
                                            let deltaY = val.translation.height / zoomScale
                                            graph.nodes[idx].position = CGPoint(
                                                x: graph.nodes[idx].position.x + deltaX,
                                                y: graph.nodes[idx].position.y + deltaY
                                            )
                                        }
                                    }
                                }
                                draggingNodeId = nil
                                dragOffset = .zero
                            }
                    )
                    .contextMenu {
                        nodeContextMenu(for: node)
                    }
            }
        }
    }

    // MARK: - Node Card View
    private func nodeCard(node: TopologyNode, isBeingDragged: Bool, isSelected: Bool) -> some View {
        let roleColor = colorForRole(node.role)

        return VStack(spacing: 3) {
            ZStack {
                // Glow Halo
                Circle()
                    .fill(roleColor.opacity(isBeingDragged ? 0.38 : (isSelected ? 0.28 : 0.12)))
                    .frame(width: isBeingDragged ? 48 : 44, height: isBeingDragged ? 48 : 44)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isBeingDragged ? Theme.cyanPulse : (isSelected ? Theme.neonCyan : roleColor.opacity(0.6)),
                                lineWidth: isBeingDragged ? 2.6 : (isSelected ? 2.2 : 1.2)
                            )
                    )
                    .shadow(color: isBeingDragged ? Theme.cyanPulse.opacity(0.8) : (isSelected ? Theme.neonCyan.opacity(0.5) : .clear), radius: isBeingDragged ? 12 : 8)

                // Role Icon
                Image(systemName: node.role.iconName)
                    .font(.system(size: isBeingDragged ? 19 : 17, weight: .bold))
                    .foregroundStyle(isBeingDragged ? Theme.cyanPulse : (isSelected ? Theme.neonCyan : roleColor))

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
                        .offset(x: 16, y: -16)
                }
            }

            // Node Name Label
            Text(node.label)
                .font(Theme.monoText(10, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceBackground.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isBeingDragged ? Theme.cyanPulse.opacity(0.8) : Color.clear, lineWidth: 1)
                )

            // IP Address Subtitle
            Text(node.ipAddress)
                .font(Theme.monoText(9))
                .foregroundStyle(isBeingDragged ? Theme.cyanPulse : .secondary)
        }
        .scaleEffect(isBeingDragged ? 1.08 : 1.0)
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
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.ipAddress, forType: .string)
            withAnimation { copyBannerText = "Copied IP: \(node.ipAddress)" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { if copyBannerText?.contains(node.ipAddress) == true { copyBannerText = nil } }
            }
        } label: {
            Label("Copy IP Address (\(node.ipAddress))", systemImage: "doc.on.doc")
        }

        if let mac = node.macAddress {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mac, forType: .string)
                withAnimation { copyBannerText = "Copied MAC: \(mac)" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { if copyBannerText?.contains(mac) == true { copyBannerText = nil } }
                }
            } label: {
                Label("Copy MAC Address (\(mac))", systemImage: "number")
            }
        }

        Divider()

        Button {
            recalculateLayout(mode: layoutMode, size: CGSize(width: 1000, height: 700))
        } label: {
            Label("Auto-Align Graph", systemImage: "arrow.triangle.2.circlepath")
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
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.borderLight, lineWidth: 1)
            )
        }
        .padding(8)
        .background(Theme.cardBackground.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderLight, lineWidth: 1)
        )
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
                if let mac = node.macAddress {
                    inspectorRow(label: "MAC Address", value: mac)
                }
                inspectorRow(label: "Vendor", value: node.vendor.rawValue)
                if let platform = node.platform {
                    inspectorRow(label: "Platform", value: platform)
                }
                inspectorRow(label: "Status", value: node.status.rawValue)
                if !node.vlans.isEmpty {
                    inspectorRow(label: "VLANs", value: node.vlans.map { "\($0)" }.joined(separator: ", "))
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
            .frame(maxHeight: 180)

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

    // MARK: - Data Loading Helpers
    private func loadTopology(preset: TopologyPreset, size: CGSize) {
        switch preset {
        case .enterprise:
            var g = TopologyGraph.buildEnterpriseDemo(bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
            self.graph = g

        case .dataCenter:
            var g = TopologyGraph.buildDataCenterDemo(bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
            self.graph = g

        case .discoveredLAN:
            var g = TopologyGraph.buildFromDiscoveredLAN(neighbors: state.discoveredNeighbors, bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
            self.graph = g

        case .managedFleet:
            var g = TopologyGraph.buildFromInventory(devices: state.managedDevices, bounds: size)
            recalculateLayout(graph: &g, mode: layoutMode, size: size)
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
