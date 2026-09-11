import SwiftUI
import SecurityKit

public struct SecondaryWorkspaceView: View {
    let title: String
    let icon: String
    let subtitle: String
    let capabilities: [String]

    public init(title: String, icon: String, subtitle: String, capabilities: [String]) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.capabilities = capabilities
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Capabilities List
                VStack(alignment: .leading, spacing: 12) {
                    Text("WORKBENCH CAPABILITIES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(capabilities, id: \.self) { cap in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text(cap)
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationTitle(title)
    }
}
