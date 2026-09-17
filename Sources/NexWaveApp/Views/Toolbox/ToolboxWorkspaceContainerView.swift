import SwiftUI

public enum ToolboxTool: String, CaseIterable, Identifiable {
    case wifi = "Wi-Fi Studio"
    case timeline = "Timeline Monitor"
    case subnet = "IP Studio & VLSM"
    case dns = "DNS & DoH Studio"
    case ports = "Port Diagnostics"
    case mtr = "Continuous MTR"
    case internetIntel = "Internet Intel & ASN"
    case sockets = "Listening Sockets"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .timeline: return "chart.xyaxis.line"
        case .subnet: return "number.square.fill"
        case .dns: return "arrow.triangle.branch"
        case .ports: return "point.3.filled.connected.trianglepath.dotted"
        case .mtr: return "waveform.path.ecg"
        case .internetIntel: return "globe.americas.fill"
        case .sockets: return "antenna.radiowaves.left.and.right"
        }
    }
}

/// Unified container for interactive toolbox utilities.
public struct ToolboxWorkspaceContainerView: View {
    var state: AppState? = nil
    @State private var localSelectedTool: ToolboxTool = .wifi

    private var activeToolBinding: Binding<ToolboxTool> {
        Binding(
            get: { state?.selectedToolboxTool ?? localSelectedTool },
            set: {
                if let s = state {
                    s.selectedToolboxTool = $0
                } else {
                    localSelectedTool = $0
                }
            }
        )
    }

    public init(state: AppState? = nil) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sub-navigation bar
            HStack {
                Picker("Toolbox Utility", selection: activeToolBinding) {
                    ForEach(ToolboxTool.allCases) { tool in
                        Label(tool.rawValue, systemImage: tool.icon).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 1040)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.surfaceBackground)

            Divider()

            // Active Tool View
            switch (state?.selectedToolboxTool ?? localSelectedTool) {
            case .wifi:
                WiFiStudioView()
            case .timeline:
                TimeSeriesStudioView()
            case .subnet:
                SubnetCalculatorView()
            case .dns:
                DNSStudioView()
            case .ports:
                PortDiagnosticsView(initialHost: (state?.portDiagnosticsTarget.isEmpty == false) ? state!.portDiagnosticsTarget : "1.1.1.1")
            case .mtr:
                MTRStudioView()
            case .internetIntel:
                InternetIntelView()
            case .sockets:
                ListeningSocketsView()
            }
        }
    }
}
