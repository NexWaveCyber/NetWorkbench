import SwiftUI

public struct AppSidebar: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: $state.selectedWorkspace) {
                Section {
                    ForEach([WorkspaceItem.home, .diagnose, .toolbox], id: \.self) { item in
                        NavigationLink(value: item) {
                            sidebarRow(item: item, tint: Theme.cyanPulse)
                        }
                    }
                } header: {
                    Text("WORKSPACES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                }

                Section {
                    ForEach([WorkspaceItem.devices, .snmp, .config, .packet], id: \.self) { item in
                        NavigationLink(value: item) {
                            sidebarRow(item: item, tint: Theme.electricAzure)
                        }
                    }
                } header: {
                    Text("INFRASTRUCTURE & PROTOCOLS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                }

                Section {
                    NavigationLink(value: WorkspaceItem.investigations) {
                        HStack(spacing: 9) {
                            iconBadge(name: WorkspaceItem.investigations.iconName, tint: Theme.signalEmerald)
                            Text(WorkspaceItem.investigations.rawValue)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if !state.investigations.isEmpty {
                                Text("\(state.investigations.count)")
                                    .font(Theme.monoText(10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.signalEmerald.opacity(0.18))
                                    .foregroundStyle(Theme.signalEmerald)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    ForEach([WorkspaceItem.environments, .commandLibrary, .history, .settings], id: \.self) { item in
                        NavigationLink(value: item) {
                            sidebarRow(item: item, tint: Theme.quantumViolet)
                        }
                    }
                } header: {
                    Text("OPERATIONS & EVIDENCE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            }
            .listStyle(.sidebar)

            Divider()

            // MARK: - Workstation Status Footer
            sidebarFooter
        }
        .navigationTitle("NexWave")
    }

    private func sidebarRow(item: WorkspaceItem, tint: Color) -> some View {
        HStack(spacing: 9) {
            iconBadge(name: item.iconName, tint: tint)
            Text(item.rawValue)
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func iconBadge(name: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tint.opacity(0.12))
                .frame(width: 22, height: 22)

            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.signalEmerald)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(Theme.signalEmerald.opacity(0.4), lineWidth: 2)
                        .scaleEffect(1.4)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("ENGINE ACTIVE • UNPRIVILEGED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("SQLite WAL • Safe Mode")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("v1.0")
                .font(Theme.monoText(10, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
