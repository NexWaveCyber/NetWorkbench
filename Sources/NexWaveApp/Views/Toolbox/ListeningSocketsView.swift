import SwiftUI

public enum SocketsFilter: String, CaseIterable, Identifiable {
    case all = "All Sockets"
    case exposedOnly = "Exposed (* / 0.0.0.0)"
    case loopbackOnly = "Loopback Safe (127.0.0.1)"
    case tcpOnly = "TCP Only"
    case udpOnly = "UDP Only"

    public var id: String { rawValue }
}

public struct ListeningSocketsView: View {
    @State private var sockets: [ListeningSocketRecord] = []
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""
    @State private var selectedFilter: SocketsFilter = .all
    @State private var lastScanned: Date? = nil

    public init() {}

    public var filteredSockets: [ListeningSocketRecord] {
        sockets.filter { socket in
            // Search filter
            if !searchText.isEmpty {
                let lowerSearch = searchText.lowercased()
                let matchesCmd = socket.command.lowercased().contains(lowerSearch)
                let matchesPort = String(socket.port).contains(lowerSearch)
                let matchesAddr = socket.localAddress.lowercased().contains(lowerSearch)
                guard matchesCmd || matchesPort || matchesAddr else { return false }
            }

            // Category filter
            switch selectedFilter {
            case .all:
                return true
            case .exposedOnly:
                return socket.exposure == .exposed
            case .loopbackOnly:
                return socket.exposure == .loopback
            case .tcpOnly:
                return socket.proto == "TCP"
            case .udpOnly:
                return socket.proto == "UDP"
            }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Control Card
                headerControlCard

                if !sockets.isEmpty {
                    // KPI Telemetry Bar
                    kpiBar

                    // Sockets Table
                    socketsTableCard
                } else if !isLoading {
                    emptyStateCard
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Listening Sockets Inspector")
        .onAppear {
            if sockets.isEmpty {
                refreshSockets()
            }
        }
    }

    // MARK: - Header Control Card
    private var headerControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LOCAL LISTENING SOCKETS & PORT EXPOSURE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("macOS Kernel Socket Enumeration • Unprivileged Safe Mode")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.neonCyan)

                TextField("Search by process name, port, or bound IP (e.g. Spotify, 7000, 127.0.0.1)...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.monoText(14))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: refreshSockets) {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text("Rescan Sockets")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(isLoading ? AnyShapeStyle(Color.gray.opacity(0.3)) : AnyShapeStyle(Theme.cyanGlowGradient))
                    .foregroundStyle(isLoading ? Color.secondary : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding(12)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyanPulse.opacity(0.3), lineWidth: 1))

            // Filter Selector
            HStack {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(SocketsFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)

                Spacer()

                if let time = lastScanned {
                    Text("Scanned: \(time.formatted(date: .omitted, time: .standard))")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - KPI Bar
    private var kpiBar: some View {
        let exposedCount = sockets.filter { $0.exposure == .exposed }.count
        let loopbackCount = sockets.filter { $0.exposure == .loopback }.count
        let privilegedCount = sockets.filter { $0.isPrivilegedPort }.count

        return HStack(spacing: 12) {
            kpiCard(title: "Total Listening", count: "\(sockets.count)", icon: "antenna.radiowaves.left.and.right", color: Theme.azurePro)
            kpiCard(title: "Globally Exposed (*)", count: "\(exposedCount)", icon: "exclamationmark.shield.fill", color: Theme.pulseCrimson)
            kpiCard(title: "Loopback Safe", count: "\(loopbackCount)", icon: "checkmark.shield.fill", color: Theme.signalEmerald)
            kpiCard(title: "Privileged (<1024)", count: "\(privilegedCount)", icon: "lock.shield.fill", color: Theme.solarAmber)
        }
    }

    private func kpiCard(title: String, count: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(count).font(Theme.monoText(16, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Sockets Table Card
    private var socketsTableCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table Header
            HStack {
                Text("PROCESS").frame(width: 140, alignment: .leading)
                Text("PID").frame(width: 60, alignment: .leading)
                Text("USER").frame(width: 80, alignment: .leading)
                Text("PROTO").frame(width: 70, alignment: .leading)
                Text("BOUND PORT").frame(width: 100, alignment: .leading)
                Text("LOCAL ADDRESS").frame(minWidth: 140, alignment: .leading)
                Text("EXPOSURE").frame(width: 140, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Rows
            if filteredSockets.isEmpty {
                HStack {
                    Spacer()
                    Text("No listening sockets match the active filter.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredSockets) { socket in
                        socketRow(socket: socket)
                        if socket.id != filteredSockets.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    private func socketRow(socket: ListeningSocketRecord) -> some View {
        HStack {
            // Process
            HStack(spacing: 6) {
                Image(systemName: "app.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.azurePro)
                Text(socket.command)
                    .font(Theme.monoText(12, weight: .bold))
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)

            // PID
            Text("\(socket.pid)")
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            // USER
            Text(socket.user)
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // PROTO
            HStack(spacing: 4) {
                Text(socket.proto)
                    .font(Theme.monoText(10, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(socket.proto == "TCP" ? Theme.azurePro.opacity(0.15) : Theme.quantumViolet.opacity(0.15))
                    .foregroundStyle(socket.proto == "TCP" ? Theme.azurePro : Theme.quantumViolet)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(socket.ipVersion)
                    .font(Theme.monoText(9))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 70, alignment: .leading)

            // PORT
            HStack(spacing: 4) {
                Text(":\(socket.port)")
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(socket.isPrivilegedPort ? Theme.solarAmber : Theme.neonCyan)
            }
            .frame(width: 100, alignment: .leading)

            // LOCAL ADDRESS
            Text(socket.localAddress)
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)

            // EXPOSURE BADGE
            HStack(spacing: 4) {
                Circle()
                    .fill(exposureColor(socket.exposure))
                    .frame(width: 5, height: 5)
                Text(socket.exposure.rawValue.uppercased())
                    .font(Theme.monoText(9, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(exposureColor(socket.exposure).opacity(0.15))
            .foregroundStyle(exposureColor(socket.exposure))
            .clipShape(Capsule())
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(socket.exposure == .exposed ? Theme.pulseCrimson.opacity(0.02) : Color.clear)
    }

    private func exposureColor(_ exp: SocketExposure) -> Color {
        switch exp {
        case .loopback: return Theme.signalEmerald
        case .localNetwork: return Theme.solarAmber
        case .exposed: return Theme.pulseCrimson
        }
    }

    // MARK: - Empty State
    private var emptyStateCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.neonCyan)
            }

            Text("Scanning Local Sockets...")
                .font(.system(size: 16, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .engineeringCard()
    }

    // MARK: - Actions
    private func refreshSockets() {
        isLoading = true
        Task {
            let sc = await SocketInspector.scanListeningSockets()
            await MainActor.run {
                self.sockets = sc
                self.lastScanned = Date()
                self.isLoading = false
            }
        }
    }
}
