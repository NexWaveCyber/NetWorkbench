import SwiftUI
import DNSEngine
import NetworkCore

public enum DNSProtocolMode: String, CaseIterable, Identifiable {
    case compareBoth = "All Protocols (Do53 + DoH)"
    case dohOnly = "Encrypted DoH (RFC 8484)"
    case classicOnly = "Classic UDP (Do53)"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compareBoth:
            return "Protocols (Do53 + DoH)"
        case .dohOnly:
            return "Encrypted DoH (RFC 8484)"
        case .classicOnly:
            return "Classic UDP (Do53)"
        }
    }

    public var icon: String {
        switch self {
        case .compareBoth:
            return "arrow.triangle.swap"
        case .dohOnly:
            return "lock.shield.fill"
        case .classicOnly:
            return "antenna.radiowaves.left.and.right"
        }
    }
}

public struct DNSStudioView: View {
    @State private var queryHost = "cloudflare.com"
    @State private var selectedRecordType = "A"
    @State private var protocolMode: DNSProtocolMode = .compareBoth
    @State private var isQuerying = false
    @State private var classicResults: [DNSResolutionResult] = []
    @State private var dohResults: [DoHQueryResult] = []

    private let resolver = DNSResolver()
    private let dohClient = DoHClient()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Query Card
                headerQueryCard

                // DNSSEC Status Banner (if any DoH returned DNSSEC validation)
                if let validDoH = dohResults.first(where: { $0.isDNSSECValidated }) {
                    dnssecBanner(validDoH: validDoH)
                }

                // Latency Race Visualizer
                if !classicResults.isEmpty || !dohResults.isEmpty {
                    latencyRaceCard
                }

                // Detailed Record Cards
                if protocolMode != .classicOnly && !dohResults.isEmpty {
                    dohRecordCardsSection
                }

                if protocolMode != .dohOnly && !classicResults.isEmpty {
                    classicRecordCardsSection
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("DNS Studio")
        .onAppear {
            if classicResults.isEmpty && dohResults.isEmpty {
                runDNSMatrix()
            }
        }
    }

    // MARK: - Header Query Card
    private var headerQueryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title and RFC Telemetry Specs
            HStack {
                Text("DNS STUDIO & RESOLVER MATRIX")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("RFC 1035 (Do53) • RFC 8484 (DoH) • DNSSEC")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Target Input Row
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.neonCyan)

                TextField("Enter domain name to resolve (e.g. cloudflare.com, apple.com)...", text: $queryHost)
                    .textFieldStyle(.plain)
                    .font(Theme.monoText(14))
                    .onSubmit { runDNSMatrix() }

                // Record Type Dropdown Menu
                Menu {
                    ForEach(["A", "AAAA", "MX", "TXT", "CNAME", "NS", "SOA"], id: \.self) { rType in
                        Button(rType) {
                            selectedRecordType = rType
                            runDNSMatrix()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedRecordType)
                            .font(Theme.monoText(12, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.borderLight, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button(action: runDNSMatrix) {
                    HStack(spacing: 6) {
                        if isQuerying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                        }
                        Text("Benchmark DNS")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(queryHost.trimmingCharacters(in: .whitespaces).isEmpty || isQuerying ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Theme.cyanGlowGradient))
                    .foregroundStyle(queryHost.trimmingCharacters(in: .whitespaces).isEmpty || isQuerying ? Color.secondary : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(queryHost.trimmingCharacters(in: .whitespaces).isEmpty || isQuerying)
            }
            .padding(10)
            .background(Theme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.cyanPulse.opacity(0.25), lineWidth: 1)
            )

            // Protocol Selector & Quick Domain Chips Row
            HStack(spacing: 12) {
                // Protocol Filter Pills
                HStack(spacing: 6) {
                    Text("Protocols:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(DNSProtocolMode.allCases) { mode in
                        Button(action: {
                            protocolMode = mode
                            runDNSMatrix()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 10))
                                Text(mode.displayName)
                                    .font(Theme.monoText(11, weight: .semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(protocolMode == mode ? Theme.neonCyan.opacity(0.18) : Color.primary.opacity(0.04))
                            .foregroundStyle(protocolMode == mode ? Theme.neonCyan : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(protocolMode == mode ? Theme.neonCyan.opacity(0.6) : Theme.borderLight, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 16)

                // Domain Presets
                HStack(spacing: 6) {
                    Text("Presets:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(["cloudflare.com", "apple.com", "google.com", "github.com"], id: \.self) { preset in
                        Button(action: {
                            queryHost = preset
                            runDNSMatrix()
                        }) {
                            Text(preset)
                                .font(Theme.monoText(10, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(queryHost == preset ? Theme.azurePro.opacity(0.2) : Color.primary.opacity(0.04))
                                .foregroundStyle(queryHost == preset ? Theme.azurePro : Color.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(queryHost == preset ? Theme.azurePro.opacity(0.5) : Theme.borderLight, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .engineeringCard(padding: 16)
    }

    // MARK: - DNSSEC Banner
    private func dnssecBanner(validDoH: DoHQueryResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.signalEmerald.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.signalEmerald)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DNSSEC CRYPTOGRAPHICALLY VALIDATED")
                        .font(Theme.monoText(11, weight: .bold))
                        .foregroundStyle(Theme.signalEmerald)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("RFC 4033 / 4034 / 4035")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.tertiary)
                }
                Text("Resolver '\(validDoH.endpoint.rawValue)' returned Authenticated Data (AD) flag = true for domain '\(queryHost)'.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HUDStatusBadge(title: "AD=1 SIGNED", color: Theme.signalEmerald, isPulsing: false, icon: "lock.shield.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .engineeringCard(padding: 14)
    }

    // MARK: - Latency Race Visualizer
    private var latencyRaceCard: some View {
        struct BenchItem: Identifiable {
            let id: String
            let name: String
            let latencyMs: Double
            let isDoH: Bool
            let isHealthy: Bool
        }

        var items: [BenchItem] = []
        for c in classicResults {
            items.append(BenchItem(id: "Do53-\(c.resolverName)", name: "\(c.resolverName) (UDP Do53)", latencyMs: c.queryTimeMs, isDoH: false, isHealthy: c.isHealthy))
        }
        for d in dohResults {
            items.append(BenchItem(id: "DoH-\(d.endpoint.rawValue)", name: "\(d.endpoint.rawValue) (DoH HTTPS)", latencyMs: d.queryTimeMs, isDoH: true, isHealthy: d.isSuccess))
        }
        items.sort { $0.latencyMs < $1.latencyMs }

        let fastest = items.first(where: { $0.isHealthy })
        let maxTime = max(items.last?.latencyMs ?? 100.0, 1.0)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RESOLVER LATENCY BENCHMARK RACE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if let win = fastest {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill").font(.system(size: 10))
                        Text("Fastest: \(win.name) (\(String(format: "%.1f ms", win.latencyMs)))")
                            .font(Theme.monoText(10, weight: .bold))
                    }
                    .foregroundStyle(Theme.signalEmerald)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.signalEmerald.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    let fraction = CGFloat(item.latencyMs / maxTime)
                    let isWinner = item.id == fastest?.id

                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.isDoH ? Theme.quantumViolet : Theme.neonCyan)
                                .frame(width: 6, height: 6)
                            Text(item.name)
                                .font(Theme.monoText(11, weight: isWinner ? .bold : .medium))
                                .foregroundStyle(isWinner ? Theme.neonCyan : Color.primary)
                                .lineLimit(1)
                                .frame(width: 220, alignment: .leading)
                        }

                        GeometryReader { geo in
                            let barWidth = max(6, geo.size.width * fraction)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isWinner ? AnyShapeStyle(Theme.cyanGlowGradient) : AnyShapeStyle(item.isDoH ? Theme.quantumViolet.opacity(0.7) : Theme.electricAzure.opacity(0.7)))
                                .frame(width: barWidth, height: 12)
                        }
                        .frame(height: 12)

                        Text(String(format: "%.1f ms", item.latencyMs))
                            .font(Theme.monoText(11, weight: isWinner ? .bold : .regular))
                            .foregroundStyle(isWinner ? Theme.signalEmerald : .secondary)
                            .frame(width: 65, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .engineeringCard(padding: 16)
    }

    // MARK: - DoH Record Cards Section
    private var dohRecordCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ENCRYPTED DNS-OVER-HTTPS (RFC 8484) RESPONSES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.quantumViolet)
                Spacer()
                Text("TLS Encrypted • JSON Wireformat")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: .infinity), spacing: 14)], spacing: 14) {
                ForEach(dohResults, id: \.endpoint.rawValue) { doh in
                    dohResultCard(doh: doh)
                }
            }
        }
    }

    private func dohResultCard(doh: DoHQueryResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.quantumViolet)
                    Text(doh.endpoint.rawValue)
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                if doh.isDNSSECValidated {
                    Text("DNSSEC")
                        .font(Theme.monoText(9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.signalEmerald.opacity(0.2))
                        .foregroundStyle(Theme.signalEmerald)
                        .clipShape(Capsule())
                }
                Text(String(format: "%.1f ms", doh.queryTimeMs))
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
            }

            Divider()

            if doh.isSuccess && !doh.answers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(doh.answers) { ans in
                        HStack {
                            Text(ans.typeName)
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(Theme.azurePro)
                                .frame(width: 40, alignment: .leading)
                            Text(ans.data)
                                .font(Theme.monoText(11))
                                .lineLimit(1)
                            Spacer()
                            Text("TTL \(ans.ttl)s")
                                .font(Theme.monoText(9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                Text(doh.errorMessage ?? "Status: \(doh.statusName)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.pulseCrimson)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .engineeringCard(padding: 14, hasHoverEffect: true)
    }

    // MARK: - Classic UDP Do53 Cards Section
    private var classicRecordCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STANDARD SYSTEM & UNENCRYPTED (Do53) RESPONSES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: .infinity), spacing: 14)], spacing: 14) {
                ForEach(classicResults, id: \.resolverName) { res in
                    classicResultCard(res: res)
                }
            }
        }
    }

    private func classicResultCard(res: DNSResolutionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(res.resolverName)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(String(format: "%.1f ms", res.queryTimeMs))
                    .font(Theme.monoText(11, weight: .bold))
                    .foregroundStyle(res.isHealthy ? Theme.neonCyan : Theme.pulseCrimson)
            }

            Divider()

            if res.isHealthy {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(res.records.prefix(4), id: \.id) { rec in
                        HStack {
                            Text(rec.type.rawValue)
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(Theme.azurePro)
                                .frame(width: 40, alignment: .leading)
                            Text(rec.value)
                                .font(Theme.monoText(11))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            } else {
                Text(res.errorMessage ?? "Resolution failed")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.pulseCrimson)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .engineeringCard(padding: 14, hasHoverEffect: true)
    }

    // MARK: - Execution
    private func runDNSMatrix() {
        let host = queryHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }

        isQuerying = true
        Task {
            // Run Do53 if enabled
            var cResults: [DNSResolutionResult] = []
            if protocolMode != .dohOnly {
                let sysRes = await resolver.resolve(hostname: host, profile: .system)
                let cfRes = await resolver.resolve(hostname: host, profile: .cloudflare)
                let googleRes = await resolver.resolve(hostname: host, profile: .google)
                let quad9Res = await resolver.resolve(hostname: host, profile: .quad9)
                cResults = [sysRes, cfRes, googleRes, quad9Res]
            }

            // Run DoH if enabled
            var dResults: [DoHQueryResult] = []
            if protocolMode != .classicOnly {
                async let cfDoH = dohClient.resolve(name: host, recordType: selectedRecordType, endpoint: .cloudflare)
                async let googleDoH = dohClient.resolve(name: host, recordType: selectedRecordType, endpoint: .google)
                async let quad9DoH = dohClient.resolve(name: host, recordType: selectedRecordType, endpoint: .quad9)
                dResults = await [cfDoH, googleDoH, quad9DoH]
            }

            await MainActor.run {
                self.classicResults = cResults
                self.dohResults = dResults
                self.isQuerying = false
            }
        }
    }
}
