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
                VStack(alignment: .leading, spacing: 12) {
                    Text("DNS STUDIO & RESOLVER MATRIX")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)

                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.azurePro)

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
                                    Image(systemName: "magnifyingglass")
                                }
                                Text("Compare Resolvers")
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(queryHost.trimmingCharacters(in: .whitespaces).isEmpty || isQuerying)
                    }
                    .padding(12)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
                }
                .engineeringCard()

                // Resolver Comparison Grid
                if !results.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MULTI-RESOLVER LATENCY & RECORD MATRIX")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(results, id: \.resolverName) { res in
                                resolverResultCard(res: res)
                            }
                        }
                    }
                } else if !isQuerying {
                    VStack(spacing: 10) {
                        Image(systemName: "network")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Click 'Compare Resolvers' to benchmark resolution latency across Cloudflare, Google, Quad9, and macOS System DNS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
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
                    .fill(res.isHealthy ? Theme.emeraldHealthy : Theme.crimsonCritical)
                    .frame(width: 8, height: 8)

                Text(res.resolverName)
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Text(String(format: "%.1f ms", res.queryTimeMs))
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(res.queryTimeMs < 30 ? Theme.emeraldHealthy : (res.queryTimeMs < 80 ? Theme.cyanPulse : Theme.amberWarning))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Divider()

            if res.isHealthy {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(res.records.prefix(4)) { rec in
                        HStack {
                            Text(rec.type.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.azurePro.opacity(0.12))
                                .foregroundStyle(Theme.azurePro)
                                .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(rec.value)
                                .font(Theme.monoText(12))
                                .lineLimit(1)

                            Spacer()

                            Text("\(rec.ttl)s")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text(res.errorMessage ?? "Resolution failed")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.crimsonCritical)
            }
        }
        .engineeringCard()
    }
}
