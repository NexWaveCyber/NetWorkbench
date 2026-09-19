import SwiftUI
import AppKit
import CommandLibrary
import PersistenceKit

public struct CommandLibraryView: View {
    public enum LibraryTab: String, CaseIterable, Identifiable {
        case catalog = "Command Catalog"
        case rosettaStone = "Rosetta Stone Matrix"
        case custom = "Custom Library"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .catalog: return "books.vertical.fill"
            case .rosettaStone: return "arrow.left.and.right.square.fill"
            case .custom: return "wrench.and.screwdriver.fill"
            }
        }
    }

    @State private var selectedTab: LibraryTab = .catalog
    @State private var searchQuery = ""
    @State private var selectedVendor: VendorOS? = nil
    @State private var selectedCategory: CommandCategory? = nil
    @State private var favoritesOnly: Bool = false
    @State private var copiedCommandId: String? = nil

    // Rosetta Stone
    @State private var selectedRosettaIntent: String = "Show Transceiver Diagnostics"
    @State private var rosettaFilterText: String = ""

    // Parameter Builder Modal
    @State private var parameterizingCommand: VendorCommand? = nil
    @State private var parameterValues: [String: String] = [:]

    // Custom Command Modal
    @State private var isShowingAddCustomSheet: Bool = false
    @State private var newIntent: String = ""
    @State private var newCategory: CommandCategory = .troubleshooting
    @State private var newVendor: VendorOS = .ciscoIOSXE
    @State private var newSyntax: String = ""
    @State private var newDescription: String = ""
    @State private var newParamKeys: String = ""

    // Cheatsheet Export Modal
    @State private var isShowingExportModal: Bool = false
    @State private var exportFormat: String = "Markdown"
    @State private var exportContent: String = ""

    private let db = CommandDatabase.shared
    var state: AppState? = nil

    public init(state: AppState? = nil) {
        self.state = state
    }

    // Merged list of database commands + SQLite custom commands
    public var allCombinedCommands: [VendorCommand] {
        var list = db.commands

        if let s = state {
            // Merge custom commands from database
            let customRecords = s.customCommandsList
            let customMapped: [VendorCommand] = customRecords.compactMap { rec in
                guard let v = VendorOS(rawValue: rec.vendor),
                      let c = CommandCategory(rawValue: rec.category) else { return nil }
                return VendorCommand(
                    id: rec.id,
                    intent: rec.intent,
                    category: c,
                    vendor: v,
                    syntax: rec.syntax,
                    description: rec.description,
                    parameters: [],
                    isCustom: true,
                    isFavorite: rec.isFavorite
                )
            }
            list.append(contentsOf: customMapped)

            // Mark favorites from database
            let favoriteIds = Set(customRecords.filter { $0.isFavorite }.map { $0.id })
            for i in 0..<list.count {
                if favoriteIds.contains(list[i].id) {
                    list[i].isFavorite = true
                }
            }
        }
        return list
    }

    public var filteredCatalogCommands: [VendorCommand] {
        var list = allCombinedCommands

        if favoritesOnly {
            list = list.filter { $0.isFavorite }
        }
        if let v = selectedVendor {
            list = list.filter { $0.vendor == v }
        }
        if let c = selectedCategory {
            list = list.filter { $0.category == c }
        }

        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                $0.intent.lowercased().contains(q) ||
                $0.syntax.lowercased().contains(q) ||
                $0.vendor.rawValue.lowercased().contains(q) ||
                $0.category.rawValue.lowercased().contains(q) ||
                $0.description.lowercased().contains(q)
            }
        }
        return list
    }

    public var customOnlyCommands: [VendorCommand] {
        allCombinedCommands.filter { $0.isCustom }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar Header
            headerToolbar

            Divider().overlay(Theme.borderLight)

            // Sub-view Tab Content
            switch selectedTab {
            case .catalog:
                catalogView
            case .rosettaStone:
                rosettaStoneView
            case .custom:
                customCommandsView
            }
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Command Library")
        .sheet(item: $parameterizingCommand) { cmd in
            parameterBuilderSheet(cmd)
        }
        .sheet(isPresented: $isShowingAddCustomSheet) {
            addCustomCommandSheet
        }
        .sheet(isPresented: $isShowingExportModal) {
            cheatsheetExportSheet
        }
    }

    // MARK: - Header Toolbar

    private var headerToolbar: some View {
        HStack(spacing: 16) {
            // Icon & Title
            ZStack {
                Circle()
                    .fill(Theme.cyanPulse.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.cyanPulse)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("MULTI-VENDOR OS DIRECTORY")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("8 VENDORS • 12 CATEGORIES")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text("Enterprise Network Command Library")
                    .font(.system(size: 18, weight: .bold))
            }

            Spacer()

            // View Tab Picker
            Picker("Mode", selection: $selectedTab) {
                ForEach(LibraryTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 440)

            // Export Button
            Menu {
                Button("Export as Markdown Cheatsheet (.md)") {
                    prepareExport(format: "Markdown")
                }
                Button("Export as CSV (.csv)") {
                    prepareExport(format: "CSV")
                }
                Button("Export as JSON (.json)") {
                    prepareExport(format: "JSON")
                }
            } label: {
                Label("Export Cheatsheet", systemImage: "arrow.up.doc.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderedButton)

            // Add Custom Command Button
            Button(action: { isShowingAddCustomSheet = true }) {
                Label("New Command", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.quantumViolet)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surfaceBackground)
    }

    // MARK: - Catalog View

    private var catalogView: some View {
        VStack(spacing: 0) {
            // Filters Bar
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by intent, command syntax, vendor, or category...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Vendor Filter
                Picker("Vendor", selection: $selectedVendor) {
                    Text("All 8 Vendors").tag(nil as VendorOS?)
                    ForEach(VendorOS.allCases) { v in
                        Text(v.rawValue).tag(v as VendorOS?)
                    }
                }
                .frame(width: 170)

                // Category Filter
                Picker("Category", selection: $selectedCategory) {
                    Text("All 12 Categories").tag(nil as CommandCategory?)
                    ForEach(CommandCategory.allCases) { c in
                        Text(c.rawValue).tag(c as CommandCategory?)
                    }
                }
                .frame(width: 190)

                // Favorites Only Toggle
                Toggle(isOn: $favoritesOnly) {
                    Label("Favorites", systemImage: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(favoritesOnly ? Theme.solarAmber : .secondary)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.surfaceBackground.opacity(0.6))

            Divider().overlay(Theme.borderLight)

            // Results Counter & Active Filter Indicators
            HStack {
                Text("\(filteredCatalogCommands.count) COMMANDS FOUND")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if selectedVendor != nil || selectedCategory != nil || favoritesOnly || !searchQuery.isEmpty {
                    Button("Reset Filters") {
                        selectedVendor = nil
                        selectedCategory = nil
                        favoritesOnly = false
                        searchQuery = ""
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Commands List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredCatalogCommands) { cmd in
                        commandRowCard(cmd)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Command Row Card

    private func commandRowCard(_ cmd: VendorCommand) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Intent, Category, Vendor badge, Favorite star
            HStack(alignment: .center, spacing: 8) {
                // Intent
                Text(cmd.intent)
                    .font(.system(size: 14, weight: .bold))

                if cmd.isCustom {
                    Text("CUSTOM")
                        .font(Theme.monoText(9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.quantumViolet.opacity(0.18))
                        .foregroundStyle(Theme.quantumViolet)
                        .clipShape(Capsule())
                }

                Spacer()

                // Category pill
                HStack(spacing: 4) {
                    Image(systemName: cmd.category.iconName)
                        .font(.system(size: 10))
                    Text(cmd.category.rawValue)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Vendor Badge
                Text(cmd.vendor.rawValue)
                    .font(Theme.monoText(11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(vendorColor(cmd.vendor).opacity(0.14))
                    .foregroundStyle(vendorColor(cmd.vendor))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(vendorColor(cmd.vendor).opacity(0.3), lineWidth: 1))

                // Favorite Button
                Button(action: {
                    toggleFavorite(cmd)
                }) {
                    Image(systemName: isFavorite(cmd) ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(isFavorite(cmd) ? Theme.solarAmber : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(isFavorite(cmd) ? "Remove from Favorites" : "Add to Favorites")
            }

            // Syntax Bar with Copy, Parameterize, and Terminal Buttons
            HStack(spacing: 8) {
                Text(cmd.syntax)
                    .font(Theme.monoText(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

                // Parameterize Button (if parameters exist)
                if !cmd.parameters.isEmpty {
                    Button(action: {
                        openParameterBuilder(cmd)
                    }) {
                        Label("Variables (\(cmd.parameters.count))", systemImage: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.azurePro)
                    .help("Configure parameters: \(cmd.parameters.map { $0.key }.joined(separator: ", "))")
                }

                // Copy Button
                Button(action: {
                    copyToClipboard(cmd.syntax, id: cmd.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedCommandId == cmd.id ? "checkmark" : "doc.on.doc")
                        Text(copiedCommandId == cmd.id ? "Copied" : "Copy")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .help("Copy CLI syntax to clipboard")

                // Run in Terminal Button
                if let s = state {
                    Button(action: {
                        s.terminalManager.activeSession?.sendCommand(cmd.syntax)
                        s.selectedWorkspace = .terminal
                        s.toastMessage = "Dispatched to Terminal: \(cmd.syntax)"
                    }) {
                        Label("Terminal", systemImage: "terminal.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyanPulse)
                    .help("Dispatch command directly to active terminal session")
                }
            }

            // Description
            if !cmd.description.isEmpty {
                Text(cmd.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .engineeringCard(padding: 14)
    }

    // MARK: - Multi-Vendor Rosetta Stone View

    private var rosettaStoneView: some View {
        VStack(spacing: 0) {
            // Intent Selector Header
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OPERATIONAL INTENT COMPARATOR")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                    Text("Select an operational task to compare CLI syntax across all 8 vendors in parallel:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Intent Picker
                Picker("Intent", selection: $selectedRosettaIntent) {
                    ForEach(db.allIntents, id: \.self) { intent in
                        Text(intent).tag(intent)
                    }
                }
                .frame(width: 320)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.surfaceBackground.opacity(0.8))

            Divider().overlay(Theme.borderLight)

            // Side-by-Side Vendor Comparative Matrix
            let matrix = db.rosettaStone(forIntent: selectedRosettaIntent)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("MULTI-VENDOR EQUIVALENTS FOR: \"\(selectedRosettaIntent.uppercased())\"")
                            .font(Theme.monoText(11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(matrix.count) of 8 Vendors Defined")
                            .font(Theme.monoText(10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 14)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(VendorOS.allCases) { vendor in
                            rosettaVendorCard(vendor: vendor, command: matrix[vendor])
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func rosettaVendorCard(vendor: VendorOS, command: VendorCommand?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(vendor.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(vendorColor(vendor))

                Spacer()

                Text(vendor.shortBadge)
                    .font(Theme.monoText(9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(vendorColor(vendor).opacity(0.14))
                    .foregroundStyle(vendorColor(vendor))
                    .clipShape(Capsule())
            }

            if let cmd = command {
                Text(cmd.syntax)
                    .font(Theme.monoText(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

                if !cmd.description.isEmpty {
                    Text(cmd.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if !cmd.parameters.isEmpty {
                        Button(action: { openParameterBuilder(cmd) }) {
                            Label("Variables", systemImage: "slider.horizontal.3")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(action: {
                        copyToClipboard(cmd.syntax, id: "\(vendor.rawValue)_\(cmd.id)")
                    }) {
                        Label(copiedCommandId == "\(vendor.rawValue)_\(cmd.id)" ? "Copied" : "Copy", systemImage: copiedCommandId == "\(vendor.rawValue)_\(cmd.id)" ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    if let s = state {
                        Button(action: {
                            s.terminalManager.activeSession?.sendCommand(cmd.syntax)
                            s.selectedWorkspace = .terminal
                        }) {
                            Label("Run", systemImage: "terminal.fill")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(vendorColor(vendor))
                    }
                }
            } else {
                Text("No vendor equivalent defined for this intent.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Theme.cardBackground.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .engineeringCard(padding: 14)
    }

    // MARK: - Custom Commands View

    private var customCommandsView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ENGINEERING RUNBOOK & CUSTOM SCRIPTS")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.quantumViolet)
                    Text("User-defined commands and macros persisted locally in SQLite database.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { isShowingAddCustomSheet = true }) {
                    Label("Add Custom Command", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.quantumViolet)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.surfaceBackground.opacity(0.8))

            Divider().overlay(Theme.borderLight)

            if customOnlyCommands.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.quantumViolet.opacity(0.5))
                    Text("No Custom Commands Yet")
                        .font(.system(size: 15, weight: .bold))
                    Text("Add your organization's custom show commands, debug macros, or site-specific automation snippets.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    Button("Create First Custom Command") {
                        isShowingAddCustomSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.quantumViolet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(customOnlyCommands) { cmd in
                            customCommandRowCard(cmd)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func customCommandRowCard(_ cmd: VendorCommand) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(cmd.intent)
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                Text(cmd.vendor.rawValue)
                    .font(Theme.monoText(11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(vendorColor(cmd.vendor).opacity(0.14))
                    .foregroundStyle(vendorColor(cmd.vendor))
                    .clipShape(Capsule())

                Button(action: {
                    state?.deleteCustomCommand(id: cmd.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete custom command")
            }

            HStack(spacing: 8) {
                Text(cmd.syntax)
                    .font(Theme.monoText(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

                Button(action: { copyToClipboard(cmd.syntax, id: cmd.id) }) {
                    Image(systemName: copiedCommandId == cmd.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)

                if let s = state {
                    Button(action: {
                        s.terminalManager.activeSession?.sendCommand(cmd.syntax)
                        s.selectedWorkspace = .terminal
                    }) {
                        Label("Run in Terminal", systemImage: "terminal.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.cyanPulse)
                }
            }

            if !cmd.description.isEmpty {
                Text(cmd.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .engineeringCard(padding: 14)
    }

    // MARK: - Parameter Builder Sheet

    private func parameterBuilderSheet(_ cmd: VendorCommand) -> some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PARAMETER BUILDER")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                    Text(cmd.intent)
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
                Button("Close") { parameterizingCommand = nil }
                    .buttonStyle(.plain)
            }

            Divider().overlay(Theme.borderLight)

            // Dynamic Form Fields for each Parameter
            VStack(alignment: .leading, spacing: 14) {
                ForEach(cmd.parameters) { param in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(param.label)
                                .font(Theme.monoText(11, weight: .bold))
                            Spacer()
                            Text("{{\(param.key)}}")
                                .font(Theme.monoText(10))
                                .foregroundStyle(Theme.cyanPulse)
                        }

                        TextField(param.placeholder.isEmpty ? param.defaultValue : param.placeholder, text: Binding(
                            get: { parameterValues[param.key] ?? param.defaultValue },
                            set: { parameterValues[param.key] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        if !param.description.isEmpty {
                            Text(param.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Live Interpolated Output Preview
            let interpolated = cmd.interpolate(with: parameterValues)
            VStack(alignment: .leading, spacing: 6) {
                Text("GENERATED CLI COMMAND")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text(interpolated)
                        .font(Theme.monoText(13, weight: .bold))
                        .foregroundStyle(Theme.cyanPulse)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: {
                        copyToClipboard(interpolated, id: "param_builder")
                    }) {
                        Image(systemName: copiedCommandId == "param_builder" ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    copyToClipboard(interpolated, id: "param_builder_main")
                    parameterizingCommand = nil
                }) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let s = state {
                    Button(action: {
                        s.terminalManager.activeSession?.sendCommand(interpolated)
                        s.selectedWorkspace = .terminal
                        parameterizingCommand = nil
                    }) {
                        Label("Run in Terminal", systemImage: "terminal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyanPulse)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.secondaryBackground)
    }

    // MARK: - Add Custom Command Sheet

    private var addCustomCommandSheet: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Create Custom Command", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") { isShowingAddCustomSheet = false }
                    .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OPERATIONAL INTENT / TITLE")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Show Transceiver Power Thresholds", text: $newIntent)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VENDOR")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $newVendor) {
                            ForEach(VendorOS.allCases) { v in
                                Text(v.rawValue).tag(v)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CATEGORY")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $newCategory) {
                            ForEach(CommandCategory.allCases) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("EXACT CLI SYNTAX")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. show interface {{interface}} transceiver detail | inc Rx", text: $newSyntax)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("DESCRIPTION & RUNBOOK NOTES")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Explanation of command output, grep filters, or troubleshooting use-case...", text: $newDescription)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: {
                guard !newIntent.isEmpty, !newSyntax.isEmpty else { return }
                let record = CustomCommandRecord(
                    id: UUID().uuidString,
                    intent: newIntent,
                    category: newCategory.rawValue,
                    vendor: newVendor.rawValue,
                    syntax: newSyntax,
                    description: newDescription,
                    isFavorite: false,
                    isCustom: true
                )
                state?.saveCustomCommand(record)
                isShowingAddCustomSheet = false
                newIntent = ""
                newSyntax = ""
                newDescription = ""
            }) {
                Text("Save to Command Library")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.quantumViolet)
            .disabled(newIntent.isEmpty || newSyntax.isEmpty)
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.secondaryBackground)
    }

    // MARK: - Cheatsheet Export Sheet

    private var cheatsheetExportSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Command Library Cheatsheet Export", systemImage: "arrow.up.doc.fill")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Close") { isShowingExportModal = false }
                    .buttonStyle(.plain)
            }

            Text("Export your multi-vendor network operations library into documentation or spreadsheet formats:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                Text(exportContent)
                    .font(Theme.monoText(11))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(height: 320)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))

            HStack(spacing: 12) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exportContent, forType: .string)
                    state?.toastMessage = "Copied \(exportFormat) Cheatsheet to clipboard!"
                    isShowingExportModal = false
                }) {
                    Label("Copy \(exportFormat) to Clipboard", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyanPulse)

                Button("Save as File...") {
                    saveExportFile()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 600, height: 480)
        .background(Theme.secondaryBackground)
    }

    // MARK: - Helpers

    private func vendorColor(_ v: VendorOS) -> Color {
        switch v {
        case .ciscoIOSXE: return Color.blue
        case .ciscoNXOS: return Color.indigo
        case .aristaEOS: return Color.teal
        case .juniperJunos: return Color.orange
        case .fortinetFortiOS: return Color.red
        case .mikrotikRouterOS: return Color.purple
        case .paloAltoPANOS: return Color.green
        case .linuxNet: return Color.yellow
        }
    }

    private func isFavorite(_ cmd: VendorCommand) -> Bool {
        if cmd.isFavorite { return true }
        if let s = state {
            return s.customCommandsList.first(where: { $0.id == cmd.id })?.isFavorite == true
        }
        return false
    }

    private func toggleFavorite(_ cmd: VendorCommand) {
        if let s = state {
            s.toggleCommandFavorite(id: cmd.id)
        }
    }

    private func openParameterBuilder(_ cmd: VendorCommand) {
        parameterValues.removeAll()
        for p in cmd.parameters {
            parameterValues[p.key] = p.defaultValue
        }
        parameterizingCommand = cmd
    }

    private func copyToClipboard(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedCommandId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedCommandId == id {
                copiedCommandId = nil
            }
        }
    }

    private func prepareExport(format: String) {
        self.exportFormat = format
        switch format {
        case "Markdown":
            self.exportContent = db.exportMarkdown(vendorFilter: selectedVendor, categoryFilter: selectedCategory)
        case "CSV":
            self.exportContent = db.exportCSV(vendorFilter: selectedVendor)
        case "JSON":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(filteredCatalogCommands),
               let str = String(data: data, encoding: .utf8) {
                self.exportContent = str
            } else {
                self.exportContent = "[]"
            }
        default:
            self.exportContent = ""
        }
        self.isShowingExportModal = true
    }

    private func saveExportFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.showsTagField = false
        panel.nameFieldStringValue = "NexWave_Commands_Cheatsheet.\(exportFormat == "Markdown" ? "md" : (exportFormat == "CSV" ? "csv" : "json"))"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? exportContent.write(to: url, atomically: true, encoding: .utf8)
                state?.toastMessage = "Exported cheatsheet to \(url.lastPathComponent)"
                isShowingExportModal = false
            }
        }
    }
}
