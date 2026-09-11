import SwiftUI

public enum ToolboxTool: String, CaseIterable, Identifiable {
    case subnet = "Subnet & VLSM"
    case dns = "DNS Studio"
    case ports = "Port Diagnostics"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .subnet: return "number.square.fill"
        case .dns: return "arrow.triangle.branch"
        case .ports: return "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

/// Unified container for interactive toolbox utilities.
public struct ToolboxWorkspaceContainerView: View {
    @State private var selectedTool: ToolboxTool = .subnet

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Sub-navigation bar
            HStack {
                Picker("Toolbox Utility", selection: $selectedTool) {
                    ForEach(ToolboxTool.allCases) { tool in
                        Label(tool.rawValue, systemImage: tool.icon).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.surfaceBackground)

            Divider()

            // Active Tool View
            switch selectedTool {
            case .subnet:
                SubnetCalculatorView()
            case .dns:
                DNSStudioView()
            case .ports:
                PortDiagnosticsView()
            }
        }
    }
}
