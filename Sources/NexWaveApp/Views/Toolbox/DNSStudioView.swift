import SwiftUI
import DNSEngine
import NetworkCore

public struct DNSStudioView: View {
    @State private var queryHost = "apple.com"
    @State private var isQuerying = false
    @State private var results: [DNSResolutionResult] = []

    private let resolver = DNSResolver()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Query Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("DNS STUDIO & RESOLVER MATRIX")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.neonCyan)
                        Spacer()
                        Text("RFC 1035 / Do53 / Anycast Benchmarking")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.neonCyan)

                        TextField("Enter domain name to resolve (e.g. apple.com, cloudflare.com)...", text: $queryHost)
                            .textFieldStyle(.plain)
                            .font(Theme.monoText(15))
                            .onSubmit {
                                runDNSMatrix()
                            }

                        Button(action: runDNSMatrix) {
                            HStack(spacing: 6) {
                                if isQuerying {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 11))
                                }
                                Text("Compare Resolvers")
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
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))
                }
                .engineeringCard(padding: 16)

                // Resolver Comparison Grid
                if !results.isEmpty {
                    // Latency Race Visualizer
                    latencyRaceCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("DETAILED RESOLVER RECORD RESPONSES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(results, id: \.resolverName) { res in
                                resolverResultCard(res: res)
                            }
                        }
                    }
                } else if !isQuerying {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.neonCyan.opacity(0.08))
                                .frame(width: 64, height: 64)

                            Image(systemName: "network")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.neonCyan)
                        }

                        Text("Resolver Latency & Record Matrix")
                            .font(.system(size: 16, weight: .bold))

                        Text("Benchmark resolution timing across Cloudflare (1.1.1.1), Google (8.8.8.8), Quad9 (9.9.9.9), and macOS System DNS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .engineeringCard()
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("DNS Studio")
        .onAppear {
            if results.isEmpty {
                runDNSMatrix()
            }
        }
    }

    private var latencyRaceCard: some View {
        let sorted = results.sorted(by: { $0.queryTimeMs < $1.queryTimeMs })
        let fastestTime = sorted.first?.queryTimeMs ?? 1.0
        let maxTime = max(sorted.last?.queryTimeMs ?? 100.0, 1.0)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RESOLVER LATENCY BENCHMARK RACE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if let fastest = sorted.first, fastest.isHealthy {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                        Text("Fastest: \(fastest.resolverName) (\(String(format: "%.1f ms", fastest.queryTimeMs)))")
                            .font(Theme.monoText(10, weight: .bold))
                    }
                    .foregroundStyle(Theme.signalEmerald)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.signalEmerald.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            VStack(spacing: 8) {
                ForEach(sorted, id: \.resolverName) { res in
                    HStack(spacing: 12) {
                        Text(res.resolverName)
                            .font(Theme.monoText(12, weight: .bold))
                            .frame(width: 130, alignment: .leading)

                        GeometryReader { geo in
                            let fraction = CGFloat(min(res.queryTimeMs / maxTime, 1.0))
                            let isWinner = res.resolverName == sorted.first?.resolverName

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: geo.size.width)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isWinner ? Theme.emeraldGlowGradient : (res.isHealthy ? Theme.cyanGlowGradient : Theme.crimsonGlowGradient))
                                    .frame(width: max(8, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 12)

                        Text(res.isHealthy ? String(format: "%.1f ms", res.queryTimeMs) : "Failed")
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(res.isHealthy ? (res.queryTimeMs == fastestTime ? Theme.signalEmerald : Color.primary) : Theme.pulseCrimson)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
        .engineeringCard(padding: 14)
    }

    private func runDNSMatrix() {
        let host = queryHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        isQuerying = true

        Task {
            let p1 = ResolverProfile.system
            let p2 = ResolverProfile.cloudflare
            let p3 = ResolverProfile.google
            let p4 = ResolverProfile.quad9

            async let r1 = resolver.resolve(hostname: host, profile: p1)
            async let r2 = resolver.resolve(hostname: host, profile: p2)
            async let r3 = resolver.resolve(hostname: host, profile: p3)
            async let r4 = resolver.resolve(hostname: host, profile: p4)

            let collected = await [r1, r2, r3, r4]
            await MainActor.run {
                self.results = collected
                self.isQuerying = false
            }
        }
    }

    private func resolverResultCard(res: DNSResolutionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(res.isHealthy ? Theme.signalEmerald : Theme.pulseCrimson)
                    .frame(width: 8, height: 8)

                Text(res.resolverName)
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Text(String(format: "%.1f ms", res.queryTimeMs))
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(res.queryTimeMs < 30 ? Theme.signalEmerald : (res.queryTimeMs < 80 ? Theme.neonCyan : Theme.solarAmber))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Divider()

            if res.isHealthy {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(res.records.prefix(4)) { rec in
                        HStack {
                            Text(rec.type.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.azurePro.opacity(0.12))
                                .foregroundStyle(Theme.azurePro)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(rec.value)
                                .font(Theme.monoText(12))
                                .lineLimit(1)

                            Spacer()

                            Text("\(rec.ttl)s")
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text(res.errorMessage ?? "Resolution failed")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.pulseCrimson)
            }
        }
        .engineeringCard(padding: 14)
    }
}
