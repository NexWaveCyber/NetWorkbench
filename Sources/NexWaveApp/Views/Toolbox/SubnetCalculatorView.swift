import SwiftUI
import NetworkCore

public enum IPStudioTab: String, CaseIterable, Identifiable {
    case subnet = "Subnet & CIDR"
    case vlsm = "VLSM Planner"
    case aggregator = "Route Aggregator"
    case wildcard = "Wildcard Mask"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .subnet: return "number.square.fill"
        case .vlsm: return "chart.bar.doc.horizontal.fill"
        case .aggregator: return "arrow.triangle.merge"
        case .wildcard: return "square.dashed"
        }
    }
}

public struct SubnetCalculatorView: View {
    @State private var selectedTab: IPStudioTab = .subnet

    // Subnet & CIDR state
    @State private var cidrInput = "192.168.10.0/24"
    @State private var calculatedNetwork: IPNetwork? = IPNetwork("192.168.10.0/24")

    // VLSM Planner state
    @State private var vlsmMajorNetworkInput = "10.0.0.0/16"
    @State private var vlsmRequirements: [VLSMRequirement] = [
        VLSMRequirement(name: "Engineering Core", requiredHosts: 120),
        VLSMRequirement(name: "Operations & DevOps", requiredHosts: 60),
        VLSMRequirement(name: "Sales & Marketing", requiredHosts: 28),
        VLSMRequirement(name: "Executive Staff", requiredHosts: 12),
        VLSMRequirement(name: "Datacenter WAN P2P", requiredHosts: 2)
    ]
    @State private var newReqName: String = ""
    @State private var newReqHosts: String = "20"
    @State private var vlsmResult: VLSMResult? = nil

    // Route Aggregator state
    @State private var aggregatorInput = "192.168.0.0/24\n192.168.1.0/24\n192.168.2.0/24\n192.168.3.0/24"
    @State private var aggregatorResult: CIDRAggregatorResult? = nil

    // Wildcard Mask state
    @State private var wildcardInput = "0.0.0.255"
    @State private var wildcardBaseIP = "192.168.1.0"
    @State private var wildcardTestIP = "192.168.1.42"

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Sub-tab Picker
            HStack {
                Picker("Studio Tool", selection: $selectedTab) {
                    ForEach(IPStudioTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Theme.surfaceBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .subnet:
                        subnetCIDRSection
                    case .vlsm:
                        vlsmPlannerSection
                    case .aggregator:
                        routeAggregatorSection
                    case .wildcard:
                        wildcardMaskSection
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("IP Studio & Calculators")
        .onAppear {
            runVLSM()
            runAggregation()
        }
    }

    // MARK: - 1. Subnet & CIDR Section
    private var subnetCIDRSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Input Card
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("IP SUBNET & CIDR CALCULATOR")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                    Spacer()
                    Text("VLSM / RFC 1918 / RFC 3021")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.neonCyan)

                    TextField("Enter subnet CIDR (e.g. 10.20.0.0/22, 172.16.1.0/24)...", text: $cidrInput)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(16))
                        .onChange(of: cidrInput) { _, newValue in
                            calculatedNetwork = IPNetwork(newValue.trimmingCharacters(in: .whitespaces))
                        }

                    if let net = calculatedNetwork {
                        Text(net.address.isPrivate ? "RFC 1918 Private" : (net.address.isCarrierGradeNAT ? "RFC 6598 CGNAT" : "Public IP"))
                            .font(Theme.monoText(10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.azurePro.opacity(0.15))
                            .foregroundStyle(Theme.azurePro)
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

                // Preset Prefix Chips
                HStack(spacing: 6) {
                    Text("Quick Prefixes:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ForEach([8, 16, 24, 26, 28, 30], id: \.self) { prefix in
                        Button("/\(prefix)") {
                            if let base = calculatedNetwork?.networkAddress.description {
                                let sanitizedBase = base.components(separatedBy: "/").first ?? base
                                cidrInput = "\(sanitizedBase)/\(prefix)"
                                calculatedNetwork = IPNetwork(cidrInput)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(calculatedNetwork?.prefixLength == prefix ? Theme.neonCyan.opacity(0.18) : Color.primary.opacity(0.04))
                        .foregroundStyle(calculatedNetwork?.prefixLength == prefix ? Theme.neonCyan : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(calculatedNetwork?.prefixLength == prefix ? Theme.neonCyan : Theme.borderLight, lineWidth: 1))
                    }
                }
            }
            .engineeringCard(padding: 16)

            if let net = calculatedNetwork {
                allocationBar(net: net)
                binaryViewCard(net: net)
                subnetGrid(net: net)
                subnetSplitterCard(net: net)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.solarAmber)
                    Text("Invalid CIDR format. Please enter an IP address followed by prefix (e.g. 192.168.1.0/24).")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .engineeringCard()
            }
        }
    }

    private func allocationBar(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ADDRESS SPACE ALLOCATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Prefix: /\(net.prefixLength) (\(net.usableHostCount.formatted()) usable hosts)")
                    .font(Theme.monoText(10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let netFraction = CGFloat(net.prefixLength) / 32.0

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.cyanGlowGradient)
                        .frame(width: max(4, w * netFraction))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: max(4, w * (1.0 - netFraction)))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
        }
        .engineeringCard(padding: 14)
    }

    private func binaryViewCard(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("32-BIT BINARY BITMASK BREAKDOWN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.neonCyan).frame(width: 6, height: 6)
                        Text("Network (\(net.prefixLength) bits)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.primary.opacity(0.25)).frame(width: 6, height: 6)
                        Text("Host (\(32 - net.prefixLength) bits)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }

            if case .v4(let v4) = net.networkAddress {
                let bits = String(v4.rawValue, radix: 2)
                let padded = String(repeating: "0", count: max(0, 32 - bits.count)) + bits

                HStack(spacing: 8) {
                    ForEach(0..<4) { byteIndex in
                        let start = padded.index(padded.startIndex, offsetBy: byteIndex * 8)
                        let end = padded.index(start, offsetBy: 8)
                        let octetBits = String(padded[start..<end])

                        HStack(spacing: 3) {
                            ForEach(0..<8) { bitIndex in
                                let globalIndex = byteIndex * 8 + bitIndex
                                let isNetworkBit = globalIndex < net.prefixLength
                                Text(String(octetBits[octetBits.index(octetBits.startIndex, offsetBy: bitIndex)]))
                                    .font(Theme.monoText(12, weight: .bold))
                                    .foregroundStyle(isNetworkBit ? Theme.neonCyan : Color.primary.opacity(0.28))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderLight, lineWidth: 1))

                        if byteIndex < 3 {
                            Text(".")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                }
            }
        }
        .engineeringCard(padding: 14)
    }

    private func subnetGrid(net: IPNetwork) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            paramCard(label: "Network Address", val: net.networkAddress.description, icon: "network")
            paramCard(label: "Broadcast Address", val: net.broadcastAddress?.description ?? "N/A (IPv6)", icon: "antenna.radiowaves.left.and.right")
            paramCard(label: "Subnet Mask", val: net.ipv4Netmask?.description ?? "N/A", icon: "shield")
            paramCard(label: "Wildcard Mask", val: net.ipv4WildcardMask?.description ?? "N/A", icon: "square.dashed")
            paramCard(label: "Usable Host Range", val: "\(net.firstUsableAddress?.description ?? "-") → \(net.lastUsableAddress?.description ?? "-")", icon: "arrow.left.and.right")
            paramCard(label: "Total Usable Hosts", val: "\(net.usableHostCount.formatted())", icon: "server.rack", highlightColor: Theme.signalEmerald)
        }
    }

    private func subnetSplitterCard(net: IPNetwork) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUBNET SPLIT (/N+1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Split into 2 equal equal-sized child subnets")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if net.prefixLength < 32, case .v4(let v4) = net.networkAddress {
                let newPrefix = net.prefixLength + 1
                let halfHosts = UInt32(1) << (32 - newPrefix)
                let net1 = IPNetwork(address: .v4(v4), prefixLength: newPrefix)!
                let net2 = IPNetwork(address: .v4(IPAddress.IPv4(rawValue: v4.rawValue + halfHosts)), prefixLength: newPrefix)!

                HStack(spacing: 14) {
                    splitPill(net: net1)
                    splitPill(net: net2)
                }
            }
        }
        .engineeringCard(padding: 14)
    }

    private func splitPill(net: IPNetwork) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(net.description)
                    .font(Theme.monoText(13, weight: .bold))
                Text("\(net.usableHostCount) Usable Hosts (\(net.firstUsableAddress?.description ?? "") – \(net.lastUsableAddress?.description ?? ""))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(net.description, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - 2. VLSM Planner Section
    private var vlsmPlannerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Parent Network Configuration
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PARENT NETWORK BLOCK")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                    Spacer()
                    Text("VLSM Hierarchical Subnet Partitioning")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .foregroundStyle(Theme.neonCyan)
                    TextField("Enter Parent Major Network (e.g. 10.0.0.0/16, 172.16.0.0/20)...", text: $vlsmMajorNetworkInput)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(15))
                        .onChange(of: vlsmMajorNetworkInput) { _, _ in runVLSM() }

                    Button("Recalculate Plan") {
                        runVLSM()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.cyanGlowGradient)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))
            }
            .engineeringCard(padding: 16)

            // Subnet Requirements Editor
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SUBNET CAPACITY REQUIREMENTS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(vlsmRequirements.count) subnets defined")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Add new requirement row
                HStack(spacing: 10) {
                    TextField("Subnet Name (e.g. Voice VLAN)...", text: $newReqName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    TextField("Hosts", text: $newReqHosts)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(13))
                        .frame(width: 80)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button(action: addRequirement) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.neonCyan.opacity(0.15))
                        .foregroundStyle(Theme.neonCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(newReqName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Table of requirements
                VStack(spacing: 6) {
                    ForEach(vlsmRequirements) { req in
                        HStack {
                            Text(req.name)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(req.requiredHosts) hosts required")
                                .font(Theme.monoText(11, weight: .semibold))
                                .foregroundStyle(Theme.neonCyan)
                            Button(action: {
                                vlsmRequirements.removeAll { $0.id == req.id }
                                runVLSM()
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.pulseCrimson.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .engineeringCard(padding: 16)

            // Result Breakdown
            if let res = vlsmResult, res.isSuccess {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("CALCULATED VLSM ALLOCATIONS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.signalEmerald)
                        Spacer()
                        Text("Utilization: \(String(format: "%.1f", res.utilizationPercent))%")
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                    }

                    VStack(spacing: 8) {
                        ForEach(res.allocations) { alloc in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(alloc.requirement.name)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(alloc.allocatedNetwork.description)
                                            .font(Theme.monoText(12, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Theme.neonCyan.opacity(0.12))
                                            .foregroundStyle(Theme.neonCyan)
                                            .clipShape(Capsule())
                                    }
                                    Text("Usable: \(alloc.allocatedNetwork.firstUsableAddress?.description ?? "") → \(alloc.allocatedNetwork.lastUsableAddress?.description ?? "")")
                                        .font(Theme.monoText(10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(alloc.allocatedHosts) usable hosts")
                                        .font(Theme.monoText(12, weight: .semibold))
                                        .foregroundStyle(Theme.signalEmerald)
                                    Text("Requested: \(alloc.requirement.requiredHosts) (\(alloc.wastedHosts) free)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(12)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
                        }
                    }
                }
                .engineeringCard(padding: 16)
            } else if let err = vlsmResult?.errorMessage {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.pulseCrimson)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.pulseCrimson)
                }
                .engineeringCard(padding: 14)
            }
        }
    }

    private func addRequirement() {
        guard let hosts = Int(newReqHosts), hosts > 0, !newReqName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vlsmRequirements.append(VLSMRequirement(name: newReqName.trimmingCharacters(in: .whitespaces), requiredHosts: hosts))
        newReqName = ""
        newReqHosts = "20"
        runVLSM()
    }

    private func runVLSM() {
        guard let major = IPNetwork(vlsmMajorNetworkInput.trimmingCharacters(in: .whitespaces)) else {
            vlsmResult = nil
            return
        }
        vlsmResult = VLSMPlanner.plan(majorNetwork: major, requirements: vlsmRequirements)
    }

    // MARK: - 3. Route Aggregator Section
    private var routeAggregatorSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ROUTE SUMMARIZATION & CIDR AGGREGATION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                    Spacer()
                    Text("Optimal Supernet Calculation")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text("Enter a list of IPv4 subnets (one per line) to compute the minimal set of aggregated CIDR route announcements:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextEditor(text: $aggregatorInput)
                    .font(Theme.monoText(13))
                    .frame(height: 110)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
                    .onChange(of: aggregatorInput) { _, _ in runAggregation() }

                Button(action: runAggregation) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Summarize Routes")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.cyanGlowGradient)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .engineeringCard(padding: 16)

            if let res = aggregatorResult {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("AGGREGATED ROUTE ANNOUNCEMENTS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.signalEmerald)
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(res.originalCount) In → \(res.summaryCount) Out")
                                .font(Theme.monoText(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.0f", res.reductionPercent))% Reduction")
                                .font(Theme.monoText(10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.signalEmerald.opacity(0.18))
                                .foregroundStyle(Theme.signalEmerald)
                                .clipShape(Capsule())
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(res.aggregatedNetworks, id: \.description) { net in
                            HStack {
                                Text(net.description)
                                    .font(Theme.monoText(14, weight: .bold))
                                    .foregroundStyle(Theme.neonCyan)
                                Spacer()
                                Text("\(net.usableHostCount.formatted()) Usable Hosts (\(net.firstUsableAddress?.description ?? "") – \(net.lastUsableAddress?.description ?? ""))")
                                    .font(Theme.monoText(11))
                                    .foregroundStyle(.secondary)
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(net.description, forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 8)
                            }
                            .padding(12)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
                        }
                    }
                }
                .engineeringCard(padding: 16)
            }
        }
    }

    private func runAggregation() {
        let lines = aggregatorInput.components(separatedBy: .newlines)
        var nets: [IPNetwork] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let net = IPNetwork(trimmed) {
                nets.append(net)
            }
        }
        aggregatorResult = CIDRAggregator.aggregate(nets)
    }

    // MARK: - 4. Wildcard Mask Section
    private var wildcardMaskSection: some View {
        let wm = WildcardMask(wildcardInput.trimmingCharacters(in: .whitespaces))

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("CISCO INVERTED WILDCARD MASK CALCULATOR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)
                    Spacer()
                    Text("ACL Pattern Matching & Bit Inversion")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.neonCyan)
                    TextField("Enter Wildcard Mask (e.g. 0.0.0.255, 0.0.3.255, 0.0.0.15)...", text: $wildcardInput)
                        .textFieldStyle(.plain)
                        .font(Theme.monoText(15))
                }
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

                // Presets
                HStack(spacing: 8) {
                    Text("Common Masks:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(["0.0.0.3", "0.0.0.7", "0.0.0.15", "0.0.0.255", "0.0.3.255", "0.0.255.255"], id: \.self) { preset in
                        Button(preset) {
                            wildcardInput = preset
                        }
                        .buttonStyle(.plain)
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(wildcardInput == preset ? Theme.neonCyan.opacity(0.18) : Color.primary.opacity(0.04))
                        .foregroundStyle(wildcardInput == preset ? Theme.neonCyan : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .engineeringCard(padding: 16)

            if let mask = wm {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MASK PROPERTIES & BIT PATTERN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        paramCard(label: "Inverted Subnet Mask", val: mask.invertedSubnetMask, icon: "shield")
                        paramCard(label: "Equivalent CIDR", val: mask.prefixLength.map { "/\($0)" } ?? "Discontiguous", icon: "number.square")
                        paramCard(label: "Contiguous Check", val: mask.isContiguous ? "Contiguous" : "Non-Contiguous", icon: "checkmark.circle", highlightColor: mask.isContiguous ? Theme.signalEmerald : Theme.solarAmber)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("BINARY PATTERN (0 = Must Match, 1 = Wildcard / Don't Care):")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text(mask.binaryRepresentation)
                            .font(Theme.monoText(14, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .engineeringCard(padding: 16)

                // Interactive Matching Tester
                VStack(alignment: .leading, spacing: 12) {
                    Text("CISCO ACL MATCH VERIFIER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.neonCyan)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base IP").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("Base IP", text: $wildcardBaseIP)
                                .textFieldStyle(.plain)
                                .font(Theme.monoText(13))
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Candidate IP").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("Candidate IP", text: $wildcardTestIP)
                                .textFieldStyle(.plain)
                                .font(Theme.monoText(13))
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        let isMatch: Bool = {
                            guard let base = IPAddress.IPv4(wildcardBaseIP),
                                  let cand = IPAddress.IPv4(wildcardTestIP) else { return false }
                            return mask.matches(base: base, candidate: cand)
                        }()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ACL Result").font(.system(size: 11)).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: isMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                Text(isMatch ? "PERMIT (MATCH)" : "DENY (NO MATCH)")
                                    .fontWeight(.bold)
                            }
                            .font(Theme.monoText(12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isMatch ? Theme.signalEmerald.opacity(0.18) : Theme.pulseCrimson.opacity(0.18))
                            .foregroundStyle(isMatch ? Theme.signalEmerald : Theme.pulseCrimson)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .engineeringCard(padding: 16)
            }
        }
    }

    private func paramCard(label: String, val: String, icon: String, highlightColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.azurePro)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(val)
                .font(Theme.monoText(13, weight: .bold))
                .foregroundStyle(highlightColor ?? Color.primary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
    }
}
