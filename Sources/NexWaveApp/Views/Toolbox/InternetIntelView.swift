import SwiftUI
import InternetIntel
import NetworkCore

public struct InternetIntelView: View {
    @State private var targetInput: String = "1.1.1.1"
    @State private var isQuerying: Bool = false
    @State private var report: InternetIntelligenceReport? = nil

    private let intelEngine = InternetIntelEngine()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Search Card
                headerSearchCard

                if let rep = report {
                    if rep.isSuccess {
                        // Success View
                        VStack(alignment: .leading, spacing: 16) {
                            // Telemetry Pill
                            telemetryPill(rep: rep)

                            // RPKI Validation Shield Card
                            if let rpki = rep.rpkiResult {
                                rpkiCard(rpki: rpki)
                            }

                            // Autonomous System Profile Card
                            if let asRec = rep.asRecord {
                                asProfileCard(asRec: asRec, rep: rep)
                            }

                            // BGP Routing Card
                            if let bgp = rep.bgpAnnouncement {
                                bgpAnnouncementCard(bgp: bgp)
                            }
                        }
                    } else {
                        // Error Card
                        errorCard(msg: rep.errorMessage ?? "No BGP or AS data found.")
                    }
                } else if !isQuerying {
                    emptyStateCard
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Internet Intelligence & ASN")
        .onAppear {
            if report == nil {
                runLookup()
            }
        }
    }

    // MARK: - Header Search Card
    private var headerSearchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("INTERNET INTELLIGENCE & ASN ROUTING")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("BGP Origin ASN • Team Cymru DNS • RPKI ROA Validation")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.neonCyan)

                TextField("Enter IP address, hostname, or ASN (e.g. 1.1.1.1, 8.8.8.8, AS13335, apple.com)...", text: $targetInput)
                    .textFieldStyle(.plain)
                    .font(Theme.monoText(15))
                    .onSubmit { runLookup() }

                Button(action: runLookup) {
                    HStack(spacing: 6) {
                        if isQuerying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text("Lookup Intelligence")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(targetInput.trimmingCharacters(in: .whitespaces).isEmpty || isQuerying ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Theme.cyanGlowGradient))
                    .foregroundStyle(targetInput.trimmingCharacters(in: .whitespaces).isEmpty || isQuerying ? Color.secondary : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(targetInput.trimmingCharacters(in: .whitespaces).isEmpty || isQuerying)
            }
            .padding(12)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

            // Quick Presets
            HStack(spacing: 8) {
                Text("Quick Targets:").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach([
                    ("Cloudflare", "1.1.1.1"),
                    ("Google", "8.8.8.8"),
                    ("Quad9", "9.9.9.9"),
                    ("Apple", "17.0.0.1"),
                    ("Fastly", "151.101.1.69")
                ], id: \.1) { name, target in
                    Button(action: {
                        targetInput = target
                        runLookup()
                    }) {
                        HStack(spacing: 4) {
                            Text(name).fontWeight(.medium)
                            Text("(\(target))").foregroundStyle(.secondary)
                        }
                        .font(Theme.monoText(10))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Telemetry Pill
    private func telemetryPill(rep: InternetIntelligenceReport) -> some View {
        HStack(spacing: 12) {
            HUDStatusBadge(
                title: "LOOKUP RESOLVED (\(String(format: "%.1f ms", rep.lookupTimeMs)))",
                color: Theme.signalEmerald,
                isPulsing: false,
                icon: "bolt.horizontal.fill"
            )

            HStack(spacing: 6) {
                Text("Resolved IP:").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(rep.ipAddress).font(Theme.monoText(11, weight: .bold)).foregroundStyle(Theme.neonCyan)
            }

            Spacer()

            Text("Team Cymru DNS Origin Engine")
                .font(Theme.monoText(10))
                .foregroundStyle(.tertiary)
        }
        .engineeringCard(padding: 12)
    }

    // MARK: - RPKI Card
    private func rpkiCard(rpki: RPKIValidationResult) -> some View {
        let isSafe = rpki.status == .valid
        let isInvalid = rpki.status == .invalid
        let badgeColor = isSafe ? Theme.signalEmerald : (isInvalid ? Theme.pulseCrimson : Theme.solarAmber)

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: isSafe ? "lock.shield.fill" : (isInvalid ? "xmark.shield.fill" : "questionmark.shield.fill"))
                    .font(.system(size: 22))
                    .foregroundStyle(badgeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(rpki.status.displayLabel.uppercased())
                        .font(Theme.monoText(12, weight: .bold))
                        .foregroundStyle(badgeColor)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Validator: \(rpki.validator)")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.tertiary)
                }

                Text(rpki.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HUDStatusBadge(
                title: rpki.status.rawValue,
                color: badgeColor,
                isPulsing: false,
                icon: isSafe ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - AS Profile Card
    private func asProfileCard(asRec: ASRecord, rep: InternetIntelligenceReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AUTONOMOUS SYSTEM (AS) PROFILE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("BGP Routing Entity")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.azurePro.opacity(0.15))
                        .frame(width: 70, height: 70)
                    VStack(spacing: 2) {
                        Text("AS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("\(asRec.asn)")
                            .font(Theme.monoText(16, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(asRec.asName)
                        .font(.system(size: 16, weight: .bold))
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("Country:").foregroundStyle(.secondary)
                            Text(asRec.countryCode).fontWeight(.bold)
                        }
                        HStack(spacing: 4) {
                            Text("RIR:").foregroundStyle(.secondary)
                            Text(asRec.registry).fontWeight(.bold).foregroundStyle(Theme.azurePro)
                        }
                        HStack(spacing: 4) {
                            Text("Allocated:").foregroundStyle(.secondary)
                            Text(asRec.allocatedDate)
                        }
                    }
                    .font(Theme.monoText(11))
                }

                Spacer()
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                intelParam(label: "ASN", val: asRec.formattedASN, icon: "number")
                intelParam(label: "Organization Name", val: asRec.asName, icon: "building.2.fill")
                intelParam(label: "Regional Registry", val: asRec.registry, icon: "map.fill")
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - BGP Routing Card
    private func bgpAnnouncementCard(bgp: BGPAnnouncement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BGP PREFIX & GLOBAL ROUTE ANNOUNCEMENT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.signalEmerald)
                Spacer()
                Text("Global Internet Routing Table")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                intelParam(label: "Announced BGP Prefix", val: bgp.prefix, icon: "network", highlightColor: Theme.neonCyan)
                intelParam(label: "Origin AS Number", val: "AS\(bgp.originASN)", icon: "antenna.radiowaves.left.and.right")
                intelParam(label: "Prefix Allocation Date", val: bgp.allocationDate, icon: "calendar")
            }
        }
        .engineeringCard(padding: 16)
    }

    private func intelParam(label: String, val: String, icon: String, highlightColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Theme.azurePro)
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(val)
                .font(Theme.monoText(12, weight: .bold))
                .foregroundStyle(highlightColor ?? Color.primary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Error & Empty State
    private func errorCard(msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.pulseCrimson)
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(Theme.pulseCrimson)
            Spacer()
        }
        .engineeringCard(padding: 16)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.neonCyan)
            }

            Text("Enter an IP, Domain, or ASN to Begin")
                .font(.system(size: 16, weight: .bold))

            Text("Inspect autonomous systems, announced BGP CIDR routes, registry allocations, and cryptographic RPKI ROA security.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .engineeringCard()
    }

    // MARK: - Actions
    private func runLookup() {
        let clean = targetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        isQuerying = true
        Task {
            let res = await intelEngine.inspect(target: clean)
            await MainActor.run {
                self.report = res
                self.isQuerying = false
            }
        }
    }
}
