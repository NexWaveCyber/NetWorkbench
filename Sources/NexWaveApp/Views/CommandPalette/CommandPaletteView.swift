import SwiftUI
import NetworkCore
import CommandLibrary

public struct CommandPaletteView: View {
    @Bindable var state: AppState
    @State private var query = ""

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                TextField("Type a command, target host, or workspace...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onSubmit {
                        handleSelection()
                    }

                Text("ESC to close")
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Suggestions List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !query.isEmpty {
                        paletteActionRow(
                            title: "Diagnose '\(query)'",
                            subtitle: "Run 20-step multi-layer network diagnosis",
                            icon: "stethoscope"
                        ) {
                            state.updateTargetClassification(query)
                            state.selectedWorkspace = .diagnose
                            state.showCommandPalette = false
                            if let target = state.classifiedTarget {
                                Task {
                                    await state.runDiagnosis(target: target)
                                }
                            }
                        }
                    }

                    Text("WORKSPACES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(WorkspaceItem.allCases) { item in
                        if query.isEmpty || item.rawValue.lowercased().contains(query.lowercased()) {
                            paletteActionRow(
                                title: item.rawValue,
                                subtitle: "Navigate to \(item.rawValue)",
                                icon: item.iconName
                            ) {
                                state.selectedWorkspace = item
                                state.showCommandPalette = false
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 540, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func handleSelection() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        state.updateTargetClassification(trimmed)
        state.selectedWorkspace = .diagnose
        state.showCommandPalette = false
        if let target = state.classifiedTarget {
            Task {
                await state.runDiagnosis(target: target)
            }
        }
    }

    private func paletteActionRow(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
