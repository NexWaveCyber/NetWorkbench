import SwiftUI

public struct AppSidebar: View {
    @Bindable var state: AppState
    @ObservedObject private var themeManager = ThemeManager.shared

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        List(selection: $state.selectedWorkspace) {
            Section {
                ForEach([WorkspaceItem.home, .diagnose, .toolbox], id: \.self) { item in
                    sidebarRow(item: item)
                        .tag(item)
                }
            } header: {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Section {
                ForEach([WorkspaceItem.wifi, .timeline, .devices, .terminal, .snmp, .config, .packet], id: \.self) { item in
                    sidebarRow(item: item)
                        .tag(item)
                }
            } header: {
                Text("INFRASTRUCTURE & PROTOCOLS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Section {
                ForEach([WorkspaceItem.investigations, .environments, .commandLibrary, .history, .settings], id: \.self) { item in
                    sidebarRow(item: item)
                        .tag(item)
                }
            } header: {
                Text("OPERATIONS & EVIDENCE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.surfaceBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                sidebarFooter
            }
        }
    }

    private func sidebarRow(item: WorkspaceItem) -> some View {
        HStack(spacing: 9) {
            iconBadge(name: item.iconName)
            Text(item.rawValue)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            if let count = badgeCount(for: item) {
                countBadge(count)
            }
        }
        .padding(.vertical, 2)
    }

    private func badgeCount(for item: WorkspaceItem) -> Int? {
        switch item {
        case .devices:
            return state.managedDevices.isEmpty ? nil : state.managedDevices.count
        case .terminal:
            return state.terminalManager.sessions.isEmpty ? nil : state.terminalManager.sessions.count
        case .investigations:
            return state.investigations.isEmpty ? nil : state.investigations.count
        default:
            return nil
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(Theme.monoText(10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.primaryAccent.opacity(themeManager.isLight ? 0.12 : 0.18))
            .foregroundStyle(Theme.primaryAccent)
            .clipShape(Capsule())
    }

    private func iconBadge(name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.primaryAccent.opacity(themeManager.isLight ? 0.12 : 0.16))
                .frame(width: 22, height: 22)

            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.primaryAccent)
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 9) {
            PulsingBeacon(color: Theme.signalEmerald, size: 7, isLive: true)

            VStack(alignment: .leading, spacing: 1.5) {
                Text("ENGINE ACTIVE • ZERO-ROOT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                Text("SQLite WAL • Safe Mode")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("v1.0 Pro")
                .font(Theme.monoText(10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

