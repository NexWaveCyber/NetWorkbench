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
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.neonCyan)

                TextField("Type a target (e.g. 1.1.1.1), CLI command, or workspace...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit {
                        handleSelection()
                    }

                HStack(spacing: 4) {
                    Text("ESC")
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Suggestions List
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !query.isEmpty {
                        paletteActionRow(
                            title: "Diagnose '\(query)'",
                            subtitle: "Execute multi-layer deterministic telemetry diagnosis",
                            icon: "bolt.shield.fill",
                            tint: Theme.neonCyan
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

                    Text("WORKSPACES & TOOLS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)

                    ForEach(WorkspaceItem.allCases) { item in
                        if query.isEmpty || item.rawValue.lowercased().contains(query.lowercased()) {
                            paletteActionRow(
                                title: item.rawValue,
                                subtitle: "Switch to \(item.rawValue)",
                                icon: item.iconName,
                                tint: Theme.electricAzure
                            ) {
                                state.selectedWorkspace = item
                                state.showCommandPalette = false
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 580, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.neonCyan.opacity(0.35), lineWidth: 1)
        )
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

    private func paletteActionRow(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Image(systemName: "return")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
