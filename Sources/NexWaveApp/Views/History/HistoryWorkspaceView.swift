import SwiftUI
import PersistenceKit

public struct HistoryWorkspaceView: View {
    @Bindable var state: AppState
    @State private var filterQuery = ""

    public init(state: AppState) {
        self.state = state
    }

    public var filteredHistory: [DiagnosticHistoryRecord] {
        let q = filterQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return state.recentHistory }
        return state.recentHistory.filter {
            $0.target.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q) ||
            $0.targetType.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter diagnostic runs by target, summary, or type...", text: $filterQuery)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Refresh") {
                    state.refreshHistory()
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // History Table
            if filteredHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No diagnostic history found.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredHistory) {
                    TableColumn("Status") { item in
                        Circle()
                            .fill(item.tcpHealthy ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                    }
                    .width(40)

                    TableColumn("Target") { item in
                        Text(item.target)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .width(180)

                    TableColumn("Type") { item in
                        Text(item.targetType)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .width(120)

                    TableColumn("Latency") { item in
                        if let lat = item.pingLatency {
                            Text(String(format: "%.1f ms", lat))
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            Text("-").foregroundStyle(.secondary)
                        }
                    }
                    .width(90)

                    TableColumn("Summary") { item in
                        Text(item.summary)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }

                    TableColumn("Timestamp") { item in
                        Text(Date(timeIntervalSince1970: item.timestamp).formatted(date: .abbreviated, time: .standard))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .width(160)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationTitle("Diagnostic History")
    }
}
