import SwiftUI

public enum SocketsFilter: String, CaseIterable, Identifiable {
    case all = "All Sockets"
    case exposedOnly = "Exposed (* / 0.0.0.0)"
    case loopbackOnly = "Loopback Safe (127.0.0.1)"
    case tcpOnly = "TCP Only"
    case udpOnly = "UDP Only"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "All Sockets"
        case .exposedOnly: return "Exposed (*)"
        case .loopbackOnly: return "Loopback Safe"
        case .tcpOnly: return "TCP Only"
        case .udpOnly: return "UDP Only"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "antenna.radiowaves.left.and.right"
        case .exposedOnly: return "exclamationmark.shield.fill"
        case .loopbackOnly: return "checkmark.shield.fill"
        case .tcpOnly: return "network"
        case .udpOnly: return "bolt.horizontal.fill"
        }
    }
}

public struct ListeningSocketsView: View {
    @State private var sockets: [ListeningSocketRecord] = []
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""
    @State private var selectedFilter: SocketsFilter = .all
    @State private var lastScanned: Date? = nil
    @State private var autoRefreshSeconds: Int = 0

    public init() {}

    private func filterCount(for filter: SocketsFilter) -> Int {
        switch filter {
        case .all:
            return sockets.count
        case .exposedOnly:
            return sockets.filter { $0.exposure == .exposed }.count
        case .loopbackOnly:
            return sockets.filter { $0.exposure == .loopback }.count
        case .tcpOnly:
            return sockets.filter { $0.proto == "TCP" }.count
        case .udpOnly:
            return sockets.filter { $0.proto == "UDP" }.count
        }
    }

    public var filteredSockets: [ListeningSocketRecord] {
        sockets.filter { socket in
            // Search filter
            if !searchText.isEmpty {
                let lowerSearch = searchText.lowercased()
                let matchesCmd = socket.command.lowercased().contains(lowerSearch) || socket.displayName.lowercased().contains(lowerSearch)
                let matchesPort = String(socket.port).contains(lowerSearch)
                let matchesAddr = socket.localAddress.lowercased().contains(lowerSearch)
                let matchesUser = socket.user.lowercased().contains(lowerSearch)
                guard matchesCmd || matchesPort || matchesAddr || matchesUser else { return false }
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
        .task(id: autoRefreshSeconds) {
            guard autoRefreshSeconds > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(autoRefreshSeconds) * 1_000_000_000)
                if !Task.isCancelled {
                    refreshSockets()
                }
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

            // Filter Selector & Refresh Controls
            HStack(spacing: 12) {
                Text("Filters:")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(SocketsFilter.allCases) { filter in
                        let isSelected = selectedFilter == filter
                        let count = filterCount(for: filter)

                        Button(action: { selectedFilter = filter }) {
                            HStack(spacing: 6) {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(filter.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))

                                if !sockets.isEmpty {
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(isSelected ? Theme.neonCyan.opacity(0.3) : Color.primary.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? Theme.neonCyan.opacity(0.18)
                                    : Color.primary.opacity(0.04)
                            )
                            .foregroundStyle(
                                isSelected
                                    ? Theme.neonCyan
                                    : Color.primary.opacity(0.75)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        isSelected
                                            ? Theme.neonCyan.opacity(0.8)
                                            : Theme.borderLight.opacity(0.6),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Auto:")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $autoRefreshSeconds) {
                            Text("Manual").tag(0)
                            Text("5s").tag(5)
                            Text("15s").tag(15)
                            Text("30s").tag(30)
                        }
                        .pickerStyle(.menu)
                        .font(Theme.monoText(10))
                        .labelsHidden()
                        .frame(width: 78)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight.opacity(0.6), lineWidth: 1))

                    if let time = lastScanned {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.signalEmerald)
                                .frame(width: 5, height: 5)
                            Text("Scanned \(time.formatted(date: .omitted, time: .standard))")
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            tableHeader

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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSockets) { socket in
                        socketRow(socket: socket)
                        if socket.id != filteredSockets.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("PROCESS").frame(width: 170, alignment: .leading)
            Text("PID").frame(width: 65, alignment: .leading)
            Text("USER").frame(width: 80, alignment: .leading)
            Text("PROTO").frame(width: 75, alignment: .leading)
            Text("BOUND PORT").frame(width: 110, alignment: .leading)
            Text("LOCAL ADDRESS").frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            Text("EXPOSURE & ACTIONS").frame(width: 175, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
    }

    private func socketRow(socket: ListeningSocketRecord) -> some View {
        HStack(spacing: 12) {
            // Process
            HStack(spacing: 8) {
                #if canImport(AppKit)
                if let icon = socket.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.azurePro)
                        .frame(width: 16, height: 16)
                }
                #else
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.azurePro)
                    .frame(width: 16, height: 16)
                #endif

                Text(socket.displayName)
                    .font(Theme.monoText(12, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 170, alignment: .leading)

            // PID
            Text(String(socket.pid))
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)

            // USER
            Text(socket.user)
                .font(Theme.monoText(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
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
            .frame(width: 75, alignment: .leading)

            // BOUND PORT
            HStack(spacing: 4) {
                Text(":\(socket.port)")
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(socket.isPrivilegedPort ? Theme.solarAmber : Theme.neonCyan)

                if socket.isPrivilegedPort {
                    Text("SYS")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Theme.solarAmber.opacity(0.18))
                        .foregroundStyle(Theme.solarAmber)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(width: 110, alignment: .leading)

            // LOCAL ADDRESS
            HStack(spacing: 6) {
                Text(socket.localAddress)
                    .font(Theme.monoText(11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if socket.localAddress == "*" || socket.localAddress == "0.0.0.0" || socket.localAddress == "::" {
                    Text("(All Interfaces)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else if socket.localAddress == "127.0.0.1" || socket.localAddress == "::1" {
                    Text("(Loopback)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.signalEmerald)
                }
            }
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            // EXPOSURE BADGE & ACTIONS
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(exposureColor(socket.exposure))
                        .frame(width: 5, height: 5)
                    Text(socket.exposureBadgeText)
                        .font(Theme.monoText(9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(exposureColor(socket.exposure).opacity(0.15))
                .foregroundStyle(exposureColor(socket.exposure))
                .clipShape(Capsule())

                Menu {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("kill -9 \(socket.pid)", forType: .string)
                    } label: {
                        Label("Copy 'kill -9 \(socket.pid)'", systemImage: "bolt.horizontal.fill")
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(socket.port)", forType: .string)
                    } label: {
                        Label("Copy Port (\(socket.port))", systemImage: "number")
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(socket.displayName) (PID \(socket.pid)) on :\(socket.port)", forType: .string)
                    } label: {
                        Label("Copy Process Info", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            .frame(width: 175, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(socket.exposure == .exposed ? Theme.pulseCrimson.opacity(0.02) : Color.clear)
        .contextMenu {
            Button("Copy 'kill -9 \(socket.pid)'") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("kill -9 \(socket.pid)", forType: .string)
            }
            Button("Copy Port \(socket.port)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(socket.port)", forType: .string)
            }
            Button("Copy Process Name: \(socket.displayName)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(socket.displayName, forType: .string)
            }
        }
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
