import SwiftUI
import CommandLibrary

public struct CommandLibraryView: View {
    @State private var searchQuery = ""
    @State private var selectedVendor: VendorOS? = nil
    @State private var copiedCommandId: String? = nil

    private let db = CommandDatabase.shared

    public init() {}

    public var filteredCommands: [VendorCommand] {
        var list = db.search(query: searchQuery)
        if let v = selectedVendor {
            list = list.filter { $0.vendor == v }
        }
        return list
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search & Filter Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search commands by intent (e.g. transceiver, errors, bgp)...", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("Vendor", selection: $selectedVendor) {
                    Text("All Vendors").tag(nil as VendorOS?)
                    ForEach(VendorOS.allCases) { v in
                        Text(v.rawValue).tag(v as VendorOS?)
                    }
                }
                .frame(width: 180)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Commands List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredCommands) { cmd in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(cmd.intent)
                                    .font(.system(size: 14, weight: .bold))

                                Spacer()

                                Text(cmd.vendor.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(vendorColor(cmd.vendor).opacity(0.12))
                                    .foregroundStyle(vendorColor(cmd.vendor))
                                    .clipShape(Capsule())

                                Text(cmd.category.rawValue)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text(cmd.syntax)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .underPageBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cmd.syntax, forType: .string)
                                    copiedCommandId = cmd.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copiedCommandId = nil
                                    }
                                }) {
                                    Image(systemName: copiedCommandId == cmd.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                            }

                            if !cmd.description.isEmpty {
                                Text(cmd.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationTitle("Command Library")
    }

    private func vendorColor(_ v: VendorOS) -> Color {
        switch v {
        case .ciscoIOSXE, .ciscoNXOS: return Color.blue
        case .aristaEOS: return Color.teal
        case .juniperJunos: return Color.orange
        }
    }
}
