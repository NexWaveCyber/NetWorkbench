import SwiftUI

public struct AppSidebar: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        List(selection: $state.selectedWorkspace) {
            Section("Workspaces") {
                ForEach([WorkspaceItem.home, .diagnose, .toolbox], id: \.self) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.iconName)
                    }
                }
            }

            Section("Devices & Infrastructure") {
                ForEach([WorkspaceItem.devices, .snmp, .config, .packet], id: \.self) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.iconName)
                    }
                }
            }

            Section("Operations & Evidence") {
                NavigationLink(value: WorkspaceItem.investigations) {
                    HStack {
                        Label(WorkspaceItem.investigations.rawValue, systemImage: WorkspaceItem.investigations.iconName)
                        Spacer()
                        if !state.investigations.isEmpty {
                            Text("\(state.investigations.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }

                ForEach([WorkspaceItem.environments, .commandLibrary, .history, .settings], id: \.self) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.iconName)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NexWave")
    }
}
