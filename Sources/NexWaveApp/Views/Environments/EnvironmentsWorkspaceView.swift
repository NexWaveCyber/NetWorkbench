import SwiftUI
import NetworkCore

/// Scope and site profile management for network engineers
public struct EnvironmentsWorkspaceView: View {
    @Bindable var state: AppState

    @State private var environments: [NetworkEnvironmentProfile] = [
        NetworkEnvironmentProfile(
            id: UUID(),
            name: "SFO Production Data Center",
            type: .dataCenter,
            gatewayIP: "10.200.1.1",
            subnetCIDR: "10.200.0.0/16",
            primaryDNS: "10.200.1.10",
            vlanRange: "10 - 250",
            deviceCount: 48,
            runbookNotes: "Dual Arista 7050X spine switches with BGP peering to AWS DirectConnect. VLAN 100 is primary SAN traffic.",
            isActive: true
        ),
        NetworkEnvironmentProfile(
            id: UUID(),
            name: "Corporate Headquarters Campus",
            type: .campus,
            gatewayIP: "172.16.1.1",
            subnetCIDR: "172.16.0.0/16",
            primaryDNS: "1.1.1.1",
            vlanRange: "10 - 50",
            deviceCount: 32,
            runbookNotes: "Cisco Catalyst 9300 access layer with dual FortiGate 100F firewalls. Wi-Fi 6 APs deployed across floors 2-4.",
            isActive: false
        ),
        NetworkEnvironmentProfile(
            id: UUID(),
            name: "Remote Staging & Engineering Lab",
            type: .lab,
            gatewayIP: "192.168.100.1",
            subnetCIDR: "192.168.100.0/24",
            primaryDNS: "8.8.8.8",
            vlanRange: "100 - 110",
            deviceCount: 14,
            runbookNotes: "Isolated hardware test bench for firmware certification and pre-deployment ACL testing.",
            isActive: false
        ),
        NetworkEnvironmentProfile(
            id: UUID(),
            name: "Cloud Transit Gateway (VPC)",
            type: .cloud,
            gatewayIP: "10.50.0.1",
            subnetCIDR: "10.50.0.0/16",
            primaryDNS: "10.50.0.2",
            vlanRange: "N/A (Overlay)",
            deviceCount: 8,
            runbookNotes: "IPsec VPN tunnel terminating at AWS Transit Gateway. BGP ASN 64512.",
            isActive: false
        )
    ]

    @State private var isShowingAddSheet: Bool = false
    @State private var newName: String = ""
    @State private var newGateway: String = ""
    @State private var newSubnet: String = ""
    @State private var newDNS: String = "1.1.1.1"
    @State private var newNotes: String = ""
    @State private var newType: NetworkEnvironmentProfile.EnvironmentType = .campus

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Bar
                headerBar

                // Active Environment Banner
                if let active = environments.first(where: { $0.isActive }) {
                    activeEnvironmentBanner(active)
                }

                // Environments Grid
                Text("REGISTERED SITE ENVIRONMENTS (\(environments.count))")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(environments) { env in
                        environmentCard(env)
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Environments & Sites")
        .sheet(isPresented: $isShowingAddSheet) {
            addEnvironmentModal
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.quantumViolet.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.quantumViolet)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("INFRASTRUCTURE SCOPES")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.quantumViolet)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("MULTI-SITE PROFILES")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                Text("Environments & Runbooks")
                    .font(.system(size: 20, weight: .bold))

                Text("Segment testing, device inventories, and diagnostic baselines across client sites and data centers.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { isShowingAddSheet = true }) {
                Label("Add Environment", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.quantumViolet)
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Active Environment Banner

    private func activeEnvironmentBanner(_ env: NetworkEnvironmentProfile) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.signalEmerald)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Theme.signalEmerald.opacity(0.4), lineWidth: 3).scaleEffect(1.6))

            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT ACTIVE SCOPE")
                    .font(Theme.monoText(9, weight: .bold))
                    .foregroundStyle(Theme.signalEmerald)
                Text(env.name)
                    .font(.system(size: 14, weight: .bold))
            }

            Spacer()

            HStack(spacing: 16) {
                metricPill(label: "GATEWAY", val: env.gatewayIP)
                metricPill(label: "SUBNET", val: env.subnetCIDR)
                metricPill(label: "DEVICES", val: "\(env.deviceCount)")
            }
        }
        .padding(14)
        .background(Theme.signalEmerald.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.signalEmerald.opacity(0.3), lineWidth: 1))
    }

    private func metricPill(label: String, val: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Theme.monoText(8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(val)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(Color.white)
        }
    }

    // MARK: - Environment Card

    private func environmentCard(_ env: NetworkEnvironmentProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: env.type.iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(env.type.color)
                    Text(env.name)
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                if env.isActive {
                    HUDStatusBadge(title: "ACTIVE", color: Theme.signalEmerald)
                } else {
                    Button("Activate") {
                        activateEnvironment(env)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider().overlay(Theme.borderLight)

            // Properties Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                propertyRow(label: "Gateway IP", value: env.gatewayIP)
                propertyRow(label: "Subnet CIDR", value: env.subnetCIDR)
                propertyRow(label: "Primary DNS", value: env.primaryDNS)
                propertyRow(label: "VLAN Scope", value: env.vlanRange)
            }

            // Runbook Notes
            if !env.runbookNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ENGINEERING RUNBOOK")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(env.runbookNotes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Quick Actions
            HStack(spacing: 8) {
                Button(action: {
                    state.targetInput = env.gatewayIP
                    state.selectedWorkspace = .diagnose
                }) {
                    Label("Diagnose Gateway", systemImage: "stethoscope")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Button(action: {
                    state.terminalManager.openSSHSession(host: env.gatewayIP)
                    state.selectedWorkspace = .terminal
                }) {
                    Label("Console", systemImage: "terminal.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(env.deviceCount) Devices")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)
            }
        }
        .engineeringCard(padding: 16)
    }

    private func propertyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoText(11, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    // MARK: - Actions

    private func activateEnvironment(_ target: NetworkEnvironmentProfile) {
        for index in environments.indices {
            environments[index].isActive = (environments[index].id == target.id)
        }
        state.targetInput = target.gatewayIP
        state.toastMessage = "Switched active scope to \(target.name)"
    }

    // MARK: - Add Environment Modal

    private var addEnvironmentModal: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Add Site Environment", systemImage: "network")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Close") { isShowingAddSheet = false }
                    .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ENVIRONMENT NAME")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Austin Regional Branch", text: $newName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GATEWAY IP")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("192.168.1.1", text: $newGateway)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUBNET CIDR")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("192.168.1.0/24", text: $newSubnet)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("RUNBOOK & SITE NOTES")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Router model, ISP circuit IDs, technician contacts...", text: $newNotes)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: {
                guard !newName.isEmpty else { return }
                let newEnv = NetworkEnvironmentProfile(
                    id: UUID(),
                    name: newName,
                    type: newType,
                    gatewayIP: newGateway.isEmpty ? "192.168.1.1" : newGateway,
                    subnetCIDR: newSubnet.isEmpty ? "192.168.1.0/24" : newSubnet,
                    primaryDNS: newDNS,
                    vlanRange: "10 - 100",
                    deviceCount: 0,
                    runbookNotes: newNotes,
                    isActive: false
                )
                environments.append(newEnv)
                isShowingAddSheet = false
                newName = ""
                newGateway = ""
                newSubnet = ""
                newNotes = ""
            }) {
                Text("Create Environment Profile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.quantumViolet)
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Model representing an engineering site or logical network scope
public struct NetworkEnvironmentProfile: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: EnvironmentType
    public var gatewayIP: String
    public var subnetCIDR: String
    public var primaryDNS: String
    public var vlanRange: String
    public var deviceCount: Int
    public var runbookNotes: String
    public var isActive: Bool

    public enum EnvironmentType: Sendable {
        case dataCenter
        case campus
        case lab
        case cloud

        public var iconName: String {
            switch self {
            case .dataCenter: return "server.rack"
            case .campus: return "building.2.fill"
            case .lab: return "flask.fill"
            case .cloud: return "cloud.fill"
            }
        }

        public var color: Color {
            switch self {
            case .dataCenter: return Theme.cyanPulse
            case .campus: return Theme.signalEmerald
            case .lab: return Theme.solarAmber
            case .cloud: return Theme.azurePro
            }
        }
    }
}
