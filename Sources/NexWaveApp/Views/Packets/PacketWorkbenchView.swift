import SwiftUI
import AppKit
import PacketKit
import ReportingKit

public struct PacketWorkbenchView: View {
    @Bindable var state: AppState

    @State private var summary: PacketCaptureSummary? = nil
    @State private var selectedPacket: PacketRecord? = nil
    @State private var activeTab: PacketTab = .packets
    @State private var protocolFilter: PacketFilter = .all
    @State private var searchText: String = ""
    @State private var rawCaptureData: Data? = nil
    @State private var currentFileName: String = "sample_traffic.pcap"

    // Live Capture Session State
    @State private var liveSession = LiveCaptureSession()
    @State private var availableInterfaces: [CaptureInterface] = []
    @State private var selectedInterfaceName: String = "en0"
    @State private var bpfFilterInput: String = ""
    @State private var autoScrollToBottom: Bool = true
    @State private var bpfStatus: BPFAccessStatus = .accessible

    // Wireshark & Export sheets
    @State private var isExportSheetPresented: Bool = false
    @State private var exportFormat: ReportFormat = .markdown
    @State private var exportedReport: ExportedReport? = nil
    @State private var showWiresharkAlert: Bool = false

    public enum PacketTab: String, CaseIterable, Identifiable {
        case packets = "Packets & Dissection"
        case topTalkers = "Top Talkers & Flows"
        case anomalies = "TCP Anomalies"

        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .packets: return "list.bullet.rectangle"
            case .topTalkers: return "chart.bar.xaxis"
            case .anomalies: return "exclamationmark.triangle.fill"
            }
        }
    }

    public enum PacketFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case tcp = "TCP"
        case udp = "UDP"
        case dns = "DNS"
        case tls = "TLS"
        case http = "HTTP"
        case icmp = "ICMP"
        case anomaliesOnly = "Anomalies Only"

        public var id: String { rawValue }
    }

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Theme.borderLight)

            liveCaptureControlDrawer
            Divider().overlay(Theme.borderLight)

            if let capture = summary {
                kpiBar(summary: capture)
                Divider().overlay(Theme.borderLight)

                tabSelectorBar(summary: capture)
                Divider().overlay(Theme.borderLight)

                switch activeTab {
                case .packets:
                    packetsAndDissectionView(summary: capture)
                case .topTalkers:
                    topTalkersAndFlowsView(summary: capture)
                case .anomalies:
                    anomaliesView(summary: capture)
                }
            } else {
                emptyDropStateView
            }
        }
        .background(Theme.surfaceBackground)
        .sheet(isPresented: $isExportSheetPresented) {
            exportSheetView
        }
        .alert("Wireshark Integration", isPresented: $showWiresharkAlert) {
            Button("Download Wireshark") {
                NSWorkspace.shared.open(WiresharkBridge.downloadURL)
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("Wireshark is not detected at /Applications/Wireshark.app. You can download the official macOS installer from Wireshark.org to enable deep binary protocol disassembly.")
        }
        .onAppear {
            availableInterfaces = LiveCaptureEngine.discoverInterfaces()
            if let first = availableInterfaces.first?.name {
                selectedInterfaceName = first
            }
            bpfStatus = LiveCaptureEngine.checkBPFAccess()
            if summary == nil {
                loadSyntheticCapture()
            }
        }
        .onChange(of: liveSession.summary?.totalPackets) { _, _ in
            if let cap = liveSession.summary {
                self.summary = cap
                if selectedPacket == nil {
                    self.selectedPacket = cap.packets.first
                }
            }
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PACKET WORKBENCH")
                        .font(Theme.monoText(13, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Zero-GPL Native Streaming PCAP/PCAPNG Summary & Anomaly Triage")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let cap = summary {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.signalEmerald)
                        .frame(width: 7, height: 7)
                    Text("\(currentFileName) • \(cap.formatName)")
                        .font(Theme.monoText(11, weight: .medium))
                        .foregroundStyle(Theme.signalEmerald)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.signalEmerald.opacity(0.12))
                .clipShape(Capsule())
            }

            // Actions
            HStack(spacing: 8) {
                Button(action: loadSyntheticCapture) {
                    Label("Sample Capture", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.cyanPulse)
                .accessibilityLabel("Load Sample Network Capture")

                Button(action: openCaptureFile) {
                    Label("Open File...", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.electricAzure)
                .accessibilityLabel("Open PCAP or PCAPNG Capture File")

                Button(action: handleOpenWireshark) {
                    Label("Open in Wireshark", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.quantumViolet)
                .accessibilityLabel("Open Current Capture in Wireshark")

                Button(action: openExportSheet) {
                    Label("Export Report", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.signalEmerald)
                .accessibilityLabel("Export Capture Triage Report")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cardBackground.opacity(0.7))
    }

    // MARK: - Live Capture Control Drawer
    private var liveCaptureControlDrawer: some View {
        VStack(spacing: 8) {
            // Row 1: Interface Picker + BPF Filter + Quick Presets
            HStack(spacing: 10) {
                // Interface selector
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.cyanPulse)
                    Picker("Interface", selection: $selectedInterfaceName) {
                        ForEach(availableInterfaces) { iface in
                            Text(iface.displayName).tag(iface.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 160, maxWidth: 220)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

                // BPF Filter Input
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.electricAzure)
                    TextField("BPF Capture Filter (e.g. port 53 or icmp, host 1.1.1.1)", text: $bpfFilterInput)
                        .font(Theme.monoText(11))
                        .textFieldStyle(.plain)
                    if !bpfFilterInput.isEmpty {
                        Button(action: { bpfFilterInput = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
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

                // Quick Presets
                HStack(spacing: 4) {
                    bpfPresetChip(title: "All", filter: "")
                    bpfPresetChip(title: "DNS", filter: "port 53")
                    bpfPresetChip(title: "Web", filter: "port 80 or port 443")
                    bpfPresetChip(title: "ICMP", filter: "icmp")
                    bpfPresetChip(title: "ARP", filter: "arp")
                }
            }

            // Row 2: Action Buttons + Live Telemetry Badge + Auto-scroll
            HStack(spacing: 10) {
                // Primary Start/Stop Capture button
                if liveSession.status == .capturing {
                    Button(action: { liveSession.stop() }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.crimsonCritical)
                                .frame(width: 8, height: 8)
                            Text("Stop Capture")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.crimsonCritical)

                    Button(action: { liveSession.pause() }) {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.amberWarning)
                } else if liveSession.status == .paused {
                    Button(action: { liveSession.resume() }) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.signalEmerald)

                    Button(action: { liveSession.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.crimsonCritical)
                } else {
                    Button(action: {
                        startLiveCapture()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 12, weight: .bold))
                            Text("Start Live Capture")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyanPulse)
                }

                // Simulate Live Stream button
                Button(action: {
                    startSimulationStream()
                }) {
                    Label(liveSession.status == .capturing && liveSession.selectedInterface.contains("Simulated") ? "Streaming..." : "Simulate Stream", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(Theme.quantumViolet)
                .disabled(liveSession.status == .capturing && !liveSession.selectedInterface.contains("Simulated"))

                // Clear buffer button
                Button(action: {
                    liveSession.clear()
                    selectedPacket = nil
                }) {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(liveSession.packets.isEmpty && summary == nil)

                Divider().frame(height: 18)

                // Telemetry Strip
                if liveSession.status == .capturing || liveSession.status == .paused {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(liveSession.status == .capturing ? Theme.signalEmerald : Theme.amberWarning)
                                .frame(width: 6, height: 6)
                            Text(liveSession.status == .capturing ? "LIVE" : "PAUSED")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(liveSession.status == .capturing ? Theme.signalEmerald : Theme.amberWarning)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((liveSession.status == .capturing ? Theme.signalEmerald : Theme.amberWarning).opacity(0.12))
                        .clipShape(Capsule())

                        Text("\(Int(liveSession.packetRate)) pkts/s")
                            .font(Theme.monoText(11, weight: .semibold))
                            .foregroundStyle(Theme.cyanPulse)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(String(format: "%.2f Mbps", liveSession.bitrateMbps))
                            .font(Theme.monoText(11, weight: .semibold))
                            .foregroundStyle(Color.white)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text("Buffer: \(liveSession.packets.count)/\(liveSession.maxBufferSize)")
                            .font(Theme.monoText(11))
                            .foregroundStyle(.secondary)

                        if liveSession.anomalyCount > 0 {
                            Text("•")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                Text("\(liveSession.anomalyCount) Anomalies")
                                    .font(Theme.monoText(10, weight: .bold))
                            }
                            .foregroundStyle(Theme.crimsonCritical)
                        }
                    }
                } else if case .error(let msg) = liveSession.status {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.crimsonCritical)
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.crimsonCritical)
                            .lineLimit(1)
                        Button("Use Simulation") {
                            startSimulationStream()
                        }
                        .font(.system(size: 11, weight: .bold))
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.cyanPulse)
                    }
                }

                Spacer()

                // Auto scroll checkbox
                Toggle(isOn: $autoScrollToBottom) {
                    Text("Auto-scroll")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surfaceBackground.opacity(0.85))
    }

    private func bpfPresetChip(title: String, filter: String) -> some View {
        Button(action: {
            bpfFilterInput = filter
            if liveSession.status == .capturing {
                startLiveCapture()
            }
        }) {
            Text(title)
                .font(Theme.monoText(10, weight: bpfFilterInput == filter ? .bold : .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(bpfFilterInput == filter ? Theme.cyanPulse.opacity(0.2) : Theme.cardBackground)
                .foregroundStyle(bpfFilterInput == filter ? Theme.cyanPulse : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func startLiveCapture() {
        currentFileName = "live_\(selectedInterfaceName).pcap"
        liveSession.startLiveCapture(interface: selectedInterfaceName, filter: bpfFilterInput)
    }

    private func startSimulationStream() {
        currentFileName = "simulated_stream.pcap"
        liveSession.startSimulation()
    }

    // MARK: - KPI Bar
    private func kpiBar(summary: PacketCaptureSummary) -> some View {
        HStack(spacing: 0) {
            kpiCard(title: "TOTAL PACKETS", value: "\(summary.totalPackets)", tint: Theme.cyanPulse, icon: "number")
            Divider().overlay(Theme.borderLight).frame(height: 36)
            kpiCard(title: "DATA VOLUME", value: ByteCountFormatter.string(fromByteCount: Int64(summary.totalBytes), countStyle: .binary), tint: Theme.electricAzure, icon: "internaldrive")
            Divider().overlay(Theme.borderLight).frame(height: 36)
            kpiCard(title: "TIME SPAN", value: String(format: "%.2fs", summary.duration), tint: Theme.amberWarning, icon: "clock")
            Divider().overlay(Theme.borderLight).frame(height: 36)
            kpiCard(title: "AVG BITRATE", value: String(format: "%.3f Mbps", summary.averageBitrateMbps), tint: Color.white, icon: "speedometer")
            Divider().overlay(Theme.borderLight).frame(height: 36)
            kpiCard(
                title: "TCP ANOMALIES",
                value: "\(summary.anomalies.count)",
                tint: summary.anomalies.isEmpty ? Theme.signalEmerald : Theme.crimsonCritical,
                icon: summary.anomalies.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )
        }
        .padding(.vertical, 8)
        .background(Theme.surfaceBackground)
    }

    private func kpiCard(title: String, value: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.monoText(9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(Theme.monoText(14, weight: .bold))
                    .foregroundStyle(tint)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Tab Selector Bar
    private func tabSelectorBar(summary: PacketCaptureSummary) -> some View {
        HStack(spacing: 12) {
            Picker("Workbench View", selection: $activeTab) {
                ForEach(PacketTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            Spacer()

            if activeTab == .packets {
                // Filter Segment
                Picker("Protocol", selection: $protocolFilter) {
                    ForEach(PacketFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Filter IP, port, or summary...", text: $searchText)
                        .font(Theme.monoText(11))
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                .frame(width: 220)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.cardBackground.opacity(0.3))
    }

    // MARK: - Tab 1: Packets & Dissection View
    private func packetsAndDissectionView(summary: PacketCaptureSummary) -> some View {
        VSplitView {
            // Upper: Packet List Table
            packetListTable(packets: filteredPackets(summary.packets))
                .frame(minHeight: 220)

            // Lower: Dual Inspector (Protocol Tree & Hex Dump)
            if let packet = selectedPacket {
                HSplitView {
                    dissectionTreeInspector(packet: packet)
                        .frame(minWidth: 320)
                    hexDumpInspector(packet: packet)
                        .frame(minWidth: 340)
                }
                .frame(minHeight: 240)
                .background(Theme.surfaceBackground)
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("Select a packet above to inspect protocol tree headers and raw hex dump")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 200)
                .background(Theme.cardBackground.opacity(0.2))
            }
        }
    }

    private func filteredPackets(_ packets: [PacketRecord]) -> [PacketRecord] {
        packets.filter { p in
            // Protocol filter
            switch protocolFilter {
            case .all: break
            case .tcp: guard p.protocolType == .tcp else { return false }
            case .udp: guard p.protocolType == .udp else { return false }
            case .dns: guard p.protocolType == .dns else { return false }
            case .tls: guard p.protocolType == .tls else { return false }
            case .http: guard p.protocolType == .http else { return false }
            case .icmp: guard p.protocolType == .icmp || p.protocolType == .icmpv6 else { return false }
            case .anomaliesOnly: guard !p.anomalies.isEmpty else { return false }
            }

            // Search text filter
            if !searchText.isEmpty {
                let term = searchText.lowercased()
                let match = p.sourceAddress.lowercased().contains(term) ||
                    p.destinationAddress.lowercased().contains(term) ||
                    p.summary.lowercased().contains(term) ||
                    "\(p.number)".contains(term) ||
                    p.protocolType.description.lowercased().contains(term)
                if !match { return false }
            }
            return true
        }
    }

    private func packetListTable(packets: [PacketRecord]) -> some View {
        VStack(spacing: 0) {
            // Table Header
            HStack(spacing: 0) {
                tableHeaderCell(title: "#", width: 50)
                tableHeaderCell(title: "Time (+s)", width: 85)
                tableHeaderCell(title: "Source", width: 170)
                tableHeaderCell(title: "Destination", width: 170)
                tableHeaderCell(title: "Proto", width: 70)
                tableHeaderCell(title: "Len", width: 60)
                tableHeaderCell(title: "Info / Protocol Summary", width: nil)
                tableHeaderCell(title: "Status", width: 130)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.cardBackground)
            Divider().overlay(Theme.borderLight)

            // Table Rows
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(packets) { packet in
                            packetRow(packet: packet)
                                .id(packet.number)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPacket = packet
                                }
                            Divider().overlay(Theme.borderLight.opacity(0.5))
                        }
                    }
                }
                .onChange(of: packets.last?.number) { _, lastNum in
                    if autoScrollToBottom, let num = lastNum {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(num, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Theme.surfaceBackground)
    }

    private func tableHeaderCell(title: String, width: CGFloat?) -> some View {
        Group {
            if let w = width {
                Text(title)
                    .frame(width: w, alignment: .leading)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(Theme.monoText(10, weight: .bold))
        .foregroundStyle(.secondary)
    }

    private func packetRow(packet: PacketRecord) -> some View {
        let isSelected = selectedPacket?.id == packet.id
        return HStack(spacing: 0) {
            // No.
            Text("\(packet.number)")
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            // Time
            Text(String(format: "+%.3fs", packet.relativeTime))
                .font(Theme.monoText(11))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 85, alignment: .leading)

            // Source
            Text(packet.sourcePort != nil ? "\(packet.sourceAddress):\(packet.sourcePort!)" : packet.sourceAddress)
                .font(Theme.monoText(11))
                .foregroundStyle(Theme.cyanPulse)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            // Destination
            Text(packet.destinationPort != nil ? "\(packet.destinationAddress):\(packet.destinationPort!)" : packet.destinationAddress)
                .font(Theme.monoText(11))
                .foregroundStyle(Theme.electricAzure)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            // Protocol Badge
            Text(packet.protocolType.description)
                .font(Theme.monoText(9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(protocolBadgeColor(packet.protocolType).opacity(0.18))
                .foregroundStyle(protocolBadgeColor(packet.protocolType))
                .clipShape(Capsule())
                .frame(width: 70, alignment: .leading)

            // Length
            Text("\(packet.wireLength)")
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            // Summary
            Text(packet.summary)
                .font(Theme.monoText(11))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Anomaly Badge
            HStack {
                if let anomaly = packet.anomalies.first {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(anomalyBadgeTitle(anomaly))
                            .font(Theme.monoText(9, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(anomaly.severity == .critical ? Theme.crimsonCritical.opacity(0.2) : Theme.amberWarning.opacity(0.2))
                    .foregroundStyle(anomaly.severity == .critical ? Theme.crimsonCritical : Theme.amberWarning)
                    .clipShape(Capsule())
                }
            }
            .frame(width: 130, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Theme.cyanPulse.opacity(0.15) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Theme.cyanPulse).frame(width: 3)
            }
        }
    }

    private func anomalyBadgeTitle(_ anomaly: TCPAnomaly) -> String {
        switch anomaly {
        case .retransmission: return "Retransmit"
        case .duplicateAck: return "Dup ACK"
        case .zeroWindow: return "Zero Window"
        case .windowUpdate: return "Win Update"
        case .connectionReset: return "TCP Reset"
        case .unansweredSyn: return "No SYN-ACK"
        }
    }

    private func protocolBadgeColor(_ proto: PacketProtocol) -> Color {
        switch proto {
        case .tcp: return Theme.cyanPulse
        case .udp: return Theme.electricAzure
        case .dns: return Theme.quantumViolet
        case .tls: return Theme.signalEmerald
        case .http: return Theme.amberWarning
        case .icmp, .icmpv6: return Color.pink
        case .arp: return Color.purple
        case .other: return Color.gray
        }
    }

    // MARK: - Lower Left: Protocol Tree Inspector
    private func dissectionTreeInspector(packet: PacketRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "flowchart")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
                Text("PROTOCOL DISSECTION TREE")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Packet #\(packet.number)")
                    .font(Theme.monoText(10))
                    .foregroundStyle(Theme.cyanPulse)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground)
            Divider().overlay(Theme.borderLight)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(packet.layers) { layer in
                        DisclosureGroup(isExpanded: .constant(true)) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(layer.fields) { field in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(field.name + ":")
                                            .font(Theme.monoText(11))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 170, alignment: .leading)
                                        Text(field.value)
                                            .font(Theme.monoText(11, weight: .medium))
                                            .foregroundStyle(Color.white)
                                        Spacer()
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.top, 4)
                        } label: {
                            HStack(spacing: 8) {
                                Text(layer.name)
                                    .font(Theme.monoText(11, weight: .bold))
                                    .foregroundStyle(Theme.cyanPulse)
                                Text("(\(layer.summary))")
                                    .font(Theme.monoText(10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Theme.cardBackground.opacity(0.15))
    }

    // MARK: - Lower Right: Hex Dump Inspector
    private func hexDumpInspector(packet: PacketRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.electricAzure)
                Text("RAW HEX & ASCII DUMP")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(packet.rawBytes.count) bytes")
                    .font(Theme.monoText(10))
                    .foregroundStyle(Theme.electricAzure)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardBackground)
            Divider().overlay(Theme.borderLight)

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<(packet.rawBytes.count + 15) / 16, id: \.self) { row in
                        let offset = row * 16
                        let chunk = packet.rawBytes.subdata(in: offset..<min(packet.rawBytes.count, offset + 16))
                        hexDumpLine(offset: offset, chunk: chunk)
                    }
                }
                .padding(12)
            }
            .font(Theme.monoText(11))
        }
        .background(Theme.cardBackground.opacity(0.15))
    }

    private func hexDumpLine(offset: Int, chunk: Data) -> some View {
        HStack(spacing: 12) {
            // Offset: 0000
            Text(String(format: "%04x", offset))
                .foregroundStyle(.secondary)

            // Hex Bytes (split in two 8-byte halves)
            HStack(spacing: 8) {
                Text(hexString(chunk.prefix(8)))
                    .frame(width: 175, alignment: .leading)
                    .foregroundStyle(Theme.cyanPulse)
                Text(hexString(chunk.dropFirst(8)))
                    .frame(width: 175, alignment: .leading)
                    .foregroundStyle(Theme.cyanPulse)
            }

            // ASCII representation
            Text(asciiString(chunk))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 140, alignment: .leading)
        }
    }

    private func hexString(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func asciiString(_ data: Data) -> String {
        return data.map { b in
            if b >= 32 && b <= 126 {
                return String(UnicodeScalar(b))
            } else {
                return "."
            }
        }.joined()
    }

    // MARK: - Tab 2: Top Talkers & Flows View
    private func topTalkersAndFlowsView(summary: PacketCaptureSummary) -> some View {
        HSplitView {
            // Left: Top Talkers
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(Theme.cyanPulse)
                    Text("TOP TALKERS BY BANDWIDTH")
                        .font(Theme.monoText(11, weight: .bold))
                    Spacer()
                    Text("\(summary.topTalkers.count) hosts")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Theme.cardBackground)
                Divider().overlay(Theme.borderLight)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(summary.topTalkers.enumerated()), id: \.element.id) { idx, talker in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("#\(idx + 1)")
                                        .font(Theme.monoText(11, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .leading)
                                    Text(talker.ipAddress)
                                        .font(Theme.monoText(12, weight: .bold))
                                        .foregroundStyle(Theme.cyanPulse)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(talker.totalBytes), countStyle: .binary))
                                        .font(Theme.monoText(12, weight: .bold))
                                        .foregroundStyle(Color.white)
                                }
                                // Progress bar
                                let maxBytes = max(1, summary.topTalkers.first?.totalBytes ?? 1)
                                let progress = Double(talker.totalBytes) / Double(maxBytes)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Theme.cardBackground)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(LinearGradient(colors: [Theme.cyanPulse, Theme.electricAzure], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: geo.size.width * CGFloat(progress))
                                    }
                                }
                                .frame(height: 6)

                                HStack {
                                    Text("Sent: \(ByteCountFormatter.string(fromByteCount: Int64(talker.sentBytes), countStyle: .binary))")
                                    Spacer()
                                    Text("Recv: \(ByteCountFormatter.string(fromByteCount: Int64(talker.receivedBytes), countStyle: .binary))")
                                    Spacer()
                                    Text("\(talker.packetCount) packets")
                                }
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Theme.cardBackground.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                        }
                    }
                    .padding(12)
                }
            }
            .frame(minWidth: 360)

            // Right: 5-tuple Flows
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(Theme.electricAzure)
                    Text("ACTIVE CONVERSATIONAL FLOWS")
                        .font(Theme.monoText(11, weight: .bold))
                    Spacer()
                    Text("\(summary.flows.count) flows")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Theme.cardBackground)
                Divider().overlay(Theme.borderLight)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(summary.flows) { flow in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(flow.protocolType.description)
                                        .font(Theme.monoText(9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(protocolBadgeColor(flow.protocolType).opacity(0.2))
                                        .foregroundStyle(protocolBadgeColor(flow.protocolType))
                                        .clipShape(Capsule())

                                    Text("\(flow.source) ⟷ \(flow.destination)")
                                        .font(Theme.monoText(11, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(flow.totalBytes), countStyle: .binary))
                                        .font(Theme.monoText(11, weight: .bold))
                                        .foregroundStyle(Theme.cyanPulse)
                                }
                                HStack {
                                    Text("Packets: \(flow.totalPackets) (\(flow.packetsAtoB) → / ← \(flow.packetsBtoA))")
                                    Spacer()
                                    Text(String(format: "Duration: %.2fs", flow.duration))
                                    if !flow.anomalies.isEmpty {
                                        Spacer()
                                        HStack(spacing: 3) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                            Text("\(flow.anomalies.count) anomalies")
                                        }
                                        .foregroundStyle(Theme.amberWarning)
                                    }
                                }
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Theme.cardBackground.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                        }
                    }
                    .padding(12)
                }
            }
            .frame(minWidth: 420)
        }
    }

    // MARK: - Tab 3: TCP Anomalies View
    private func anomaliesView(summary: PacketCaptureSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .foregroundStyle(Theme.amberWarning)
                Text("DETECTED TRANSPORT & TCP HEALTH ANOMALIES")
                    .font(Theme.monoText(11, weight: .bold))
                Spacer()
                Text("\(summary.anomalies.count) events identified")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Theme.amberWarning)
            }
            .padding(12)
            .background(Theme.cardBackground)
            Divider().overlay(Theme.borderLight)

            if summary.anomalies.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.signalEmerald)
                    Text("Zero Transport Anomalies Detected")
                        .font(.system(size: 16, weight: .semibold))
                    Text("No packet retransmissions, duplicate ACKs, buffer stalls, or RST drops observed in this capture.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(summary.anomalies) { anomaly in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: anomaly.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(anomaly.severity == .critical ? Theme.crimsonCritical : Theme.amberWarning)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(anomaly.description)
                                            .font(Theme.monoText(12, weight: .bold))
                                            .foregroundStyle(Color.white)
                                        Spacer()
                                        Text(anomaly.severity.rawValue)
                                            .font(Theme.monoText(9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(anomaly.severity == .critical ? Theme.crimsonCritical.opacity(0.2) : Theme.amberWarning.opacity(0.2))
                                            .foregroundStyle(anomaly.severity == .critical ? Theme.crimsonCritical : Theme.amberWarning)
                                            .clipShape(Capsule())
                                    }

                                    HStack(spacing: 16) {
                                        Text("Packet #\(anomaly.packetNumber)")
                                            .font(Theme.monoText(10))
                                            .foregroundStyle(Theme.cyanPulse)
                                        Text(String(format: "Time: +%.3fs", anomaly.relativeTime))
                                            .font(Theme.monoText(10))
                                            .foregroundStyle(.secondary)
                                        Text("Endpoints: \(anomaly.source) → \(anomaly.destination)")
                                            .font(Theme.monoText(10))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Button("Inspect") {
                                    if let p = summary.packets.first(where: { $0.number == anomaly.packetNumber }) {
                                        selectedPacket = p
                                        activeTab = .packets
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.cyanPulse)
                                .font(.system(size: 11, weight: .medium))
                            }
                            .padding(12)
                            .background(Theme.cardBackground.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Empty State View
    private var emptyDropStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(Theme.cyanPulse)
            Text("No Packet Capture Active")
                .font(.system(size: 18, weight: .bold))
            Text("Load the synthetic sample capture or open a .pcap / .pcapng file to begin streaming protocol analysis.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button("Load Sample Capture") {
                    loadSyntheticCapture()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)

                Button("Open File...") {
                    openCaptureFile()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    // MARK: - Actions
    private func loadSyntheticCapture() {
        let sampleData = SamplePCAPGenerator.generateSampleCapture()
        self.rawCaptureData = sampleData
        self.currentFileName = "synthetic_traffic.pcap"
        do {
            let capSummary = try PCAPReader.parse(data: sampleData, fileName: "synthetic_traffic.pcap")
            self.summary = capSummary
            self.selectedPacket = capSummary.packets.first
        } catch {
            print("Failed to parse synthetic capture: \(error)")
        }
    }

    private func openCaptureFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [] // allow all pcap/pcapng

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                self.rawCaptureData = data
                self.currentFileName = url.lastPathComponent
                let capSummary = try CaptureFileReader.read(data: data, fileName: url.lastPathComponent)
                self.summary = capSummary
                self.selectedPacket = capSummary.packets.first
            } catch {
                print("Failed to open capture file: \(error)")
            }
        }
    }

    private func handleOpenWireshark() {
        let data: Data?
        if liveSession.status == .capturing || liveSession.status == .paused || !liveSession.packets.isEmpty {
            data = liveSession.exportCurrentBufferAsPCAP()
        } else {
            data = rawCaptureData
        }
        guard let validData = data else { return }
        if WiresharkBridge.isWiresharkInstalled {
            _ = try? WiresharkBridge.openDataInWireshark(data: validData, suggestedFileName: currentFileName)
        } else {
            showWiresharkAlert = true
        }
    }

    private func openExportSheet() {
        let cap: PacketCaptureSummary?
        if liveSession.status == .capturing || liveSession.status == .paused || !liveSession.packets.isEmpty {
            cap = liveSession.summary ?? summary
        } else {
            cap = summary
        }
        guard let validCap = cap else { return }
        self.exportedReport = ReportEngine.generatePacketReport(summary: validCap, format: exportFormat)
        self.isExportSheetPresented = true
    }

    // MARK: - Export Sheet View
    private var currentExportReport: ExportedReport? {
        if let rep = exportedReport { return rep }
        if let cap = summary {
            return ReportEngine.generatePacketReport(summary: cap, format: exportFormat)
        }
        return nil
    }

    private var exportSheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
                Text("EXPORT AUDIT EVIDENCE REPORT")
                    .font(Theme.monoText(13, weight: .bold))
                Spacer()
                Button("Close") {
                    isExportSheetPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Divider().overlay(Theme.borderLight)

            HStack {
                Text("Format:")
                    .font(.system(size: 12, weight: .medium))
                Picker("Format", selection: $exportFormat) {
                    ForEach(ReportFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: exportFormat) { _, newFmt in
                    if let cap = summary {
                        self.exportedReport = ReportEngine.generatePacketReport(summary: cap, format: newFmt)
                    }
                }
            }

            if let rep = currentExportReport {
                ScrollView {
                    Text(rep.content)
                        .font(Theme.monoText(11))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 380)

                HStack {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rep.content, forType: .string)
                    }) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(action: {
                        saveReportToFile(report: rep)
                    }) {
                        Label("Save Report File...", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.signalEmerald)
                }
            }
        }
        .padding(20)
        .frame(width: 680, height: 520)
        .background(Theme.cardBackground)
    }

    private func saveReportToFile(report: ExportedReport) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "NexWave_Packet_Audit_\(currentFileName).\(report.format.fileExtension)"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? report.content.write(to: url, atomically: true, encoding: .utf8)
            isExportSheetPresented = false
        }
    }
}
