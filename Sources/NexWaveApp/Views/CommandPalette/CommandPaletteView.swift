import SwiftUI
import NetworkCore
import CommandLibrary

public struct CommandPaletteView: View {
    @Bindable var state: AppState
    @State private var query = ""
    @State private var hoveredItem: String? = nil

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.neonCyan)
                    .shadow(color: Theme.neonCyan.opacity(0.4), radius: 5, x: 0, y: 0)

                TextField("Search commands, IP/host target, or switch workspaces...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .onSubmit {
                        handleSelection()
                    }

                HStack(spacing: 4) {
                    Text("ESC")
                        .font(Theme.monoText(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)

            Divider()
                .overlay(Color.white.opacity(0.1))

            // Suggestions List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !query.isEmpty {
                        paletteActionRow(
                            id: "diagnose-target",
                            title: "Diagnose '\(query)'",
                            subtitle: "Execute multi-layer deterministic telemetry pipeline",
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
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 2)

                    ForEach(WorkspaceItem.allCases) { item in
                        if query.isEmpty || item.rawValue.lowercased().contains(query.lowercased()) {
                            paletteActionRow(
                                id: item.rawValue,
                                title: item.rawValue,
                                subtitle: "Switch workspace to \(item.rawValue)",
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
        .frame(width: 620, height: 460)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.neonCyan.opacity(0.5), Theme.electricAzure.opacity(0.2), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.25
                )
        )
        .shadow(color: Theme.neonCyan.opacity(0.2), radius: 24, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 15)
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

    private func paletteActionRow(id: String, title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredItem == id

        return Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tint.opacity(isHovered ? 0.25 : 0.12))
                        .frame(width: 30, height: 30)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isHovered ? .bold : .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isHovered ? Theme.neonCyan : Color.secondary.opacity(0.5))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isHovered ? Theme.neonCyan.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    if hovering {
                        hoveredItem = id
                    } else if hoveredItem == id {
                        hoveredItem = nil
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
