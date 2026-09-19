import SwiftUI
import AppKit
import Combine
import TerminalKit
import SecurityKit
import PersistenceKit
import DNSEngine
import SNMPEngine
import NetworkCore
import UniformTypeIdentifiers

/// Navigation categories for the Enterprise Preferences workspace
public enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General & UI"
    case diagnostics = "Diagnostics & Probing"
    case dns = "DNS & Resolution"
    case monitoring = "SLA & Menu Bar"
    case packetCapture = "Packet Capture & BPF"
    case terminal = "Terminal & Console"
    case snmp = "SNMP Studio"
    case storage = "Storage & Database"
    case about = "System & About"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .diagnostics: return "stethoscope"
        case .dns: return "network"
        case .monitoring: return "waveform.path.ecg"
        case .packetCapture: return "tray.full.fill"
        case .terminal: return "terminal.fill"
        case .snmp: return "server.rack"
        case .storage: return "cylinder.split.1x2.fill"
        case .about: return "info.circle.fill"
        }
    }
}

/// 10/10 Enterprise Grade Preferences & System Tuning Workspace for NexWave Network Workbench
public struct SettingsWorkspaceView: View {
    @Bindable var state: AppState

    // Navigation Category
    @State private var selectedCategory: SettingsCategory = .general

    // General & UI Tuning
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage("accentColorHex") private var accentColorHex: String = "#00E5FF"
    @AppStorage("enableSoundEffects") private var enableSoundEffects: Bool = true
    @AppStorage("toastDurationSec") private var toastDurationSec: Double = 3.0
    @AppStorage("reduceMotion") private var reduceMotion: Bool = false

    // Diagnostics & Probing
    @AppStorage("defaultPingCount") private var defaultPingCount: Int = 5
    @AppStorage("pingPayloadBytes") private var pingPayloadBytes: Int = 64
    @AppStorage("setDontFragmentBit") private var setDontFragmentBit: Bool = false
    @AppStorage("defaultTimeoutMs") private var defaultTimeoutMs: Int = 2000
    @AppStorage("defaultTcpPort") private var defaultTcpPort: Int = 80
    @AppStorage("customUserAgent") private var customUserAgent: String = "NexWave-Workbench/1.0 (Macintosh; Apple Silicon)"

    // DNS & Resolution
    @AppStorage("preferredDNSResolver") private var preferredDNSResolver: String = "1.1.1.1"
    @AppStorage("secondaryDNSResolver") private var secondaryDNSResolver: String = "1.0.0.1"
    @AppStorage("customDNSResolverIP") private var customDNSResolverIP: String = ""
    @AppStorage("enableDoH") private var enableDoH: Bool = true
    @AppStorage("dohEndpoint") private var dohEndpoint: String = "https://cloudflare-dns.com/dns-query"
    @AppStorage("validateDNSSEC") private var validateDNSSEC: Bool = true

    // SLA & Background Monitoring
    @AppStorage("menuBarIntervalSec") private var menuBarIntervalSec: Double = 2.5
    @AppStorage("menuBarIconStyle") private var menuBarIconStyle: String = "nextGenWave"
    @AppStorage("slaLatencyThresholdMs") private var slaLatencyThresholdMs: Double = 50.0
    @AppStorage("slaLossThresholdPct") private var slaLossThresholdPct: Double = 5.0

    // Packet Capture & BPF
    @AppStorage("maxPacketBufferSize") private var maxPacketBufferSize: Int = 2000
    @AppStorage("captureSnaplen") private var captureSnaplen: Int = 1514
    @AppStorage("enablePromiscuousMode") private var enablePromiscuousMode: Bool = true

    // Terminal & Serial Console
    @AppStorage("terminal_font_family") private var terminalFontFamily: String = "SF Mono (System)"
    @AppStorage("terminal_font_size") private var terminalFontSize: Double = 12.0
    @AppStorage("terminal_line_spacing") private var terminalLineSpacing: Double = 2.0
    @AppStorage("terminal_theme") private var terminalTheme: String = TerminalTheme.obsidian.rawValue
    @AppStorage("terminal_cursor_style") private var terminalCursorStyle: String = TerminalCursorStyle.block.rawValue
    @AppStorage("terminal_cursor_blink") private var terminalCursorBlink: Bool = true
    @AppStorage("defaultSSHUser") private var defaultSSHUser: String = "admin"
    @AppStorage("defaultSSHPort") private var defaultSSHPort: Int = 22
    @AppStorage("defaultSerialBaud") private var defaultSerialBaud: Int = 9600

    // SNMP Studio Preferences
    @AppStorage("snmpDefaultCommunity") private var snmpDefaultCommunity: String = "public"
    @AppStorage("snmpDefaultPort") private var snmpDefaultPort: Int = 161
    @AppStorage("snmpDefaultTimeoutMs") private var snmpDefaultTimeoutMs: Int = 2000
    @AppStorage("snmpDefaultRetries") private var snmpDefaultRetries: Int = 2
    @AppStorage("snmpDefaultVersion") private var snmpDefaultVersion: Int = 1 // 0=v1, 1=v2c, 3=v3
    @AppStorage("snmpDefaultOidGroup") private var snmpDefaultOidGroup: String = "system"

    // Storage & Maintenance State
    @State private var dbSizeBytes: Int64 = 0
    @State private var dbRowCounts: [String: Int] = [:]
    @State private var isVacuuming: Bool = false
    @State private var lastVacuumTimestamp: Date? = nil
    @State private var lastFlushDnsTimestamp: Date? = nil
    @State private var showingClearHistoryAlert: Bool = false
    @State private var showingResetDefaultsAlert: Bool = false

    // Cursor Blink Animation Timer is encapsulated inside TerminalPreviewBoxView for maximum UI responsiveness

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Global Header
            headerBar
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider().overlay(Theme.borderLight)

            // Category Navigation + Content Workspace
            HStack(spacing: 0) {
                // Left Navigation Rail
                sidebarNavigation
                    .frame(width: 230)
                    .background(Theme.surfaceBackground)

                Divider().overlay(Theme.borderLight)

                // Right Category Detail
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedCategory {
                        case .general:
                            generalSection
                        case .diagnostics:
                            diagnosticsSection
                        case .dns:
                            dnsSection
                        case .monitoring:
                            monitoringSection
                        case .packetCapture:
                            packetCaptureSection
                        case .terminal:
                            terminalSection
                        case .snmp:
                            snmpSection
                        case .storage:
                            storageSection
                        case .about:
                            aboutSection
                        }
                    }
                    .padding(24)
                }
                .background(Theme.secondaryBackground)
            }
        }
        .navigationTitle("Preferences & Tuning")
        .onAppear {
            refreshDatabaseMetrics()
        }

        .alert("Clear Diagnostic History?", isPresented: $showingClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All History", role: .destructive) {
                state.clearAllHistory()
                refreshDatabaseMetrics()
            }
        } message: {
            Text("This will permanently delete all diagnostic logs and test runs from the local SQLite database. Investigations and credentials remain intact.")
        }
        .alert("Reset All Preferences to Defaults?", isPresented: $showingResetDefaultsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset to Defaults", role: .destructive) {
                resetAllPreferencesToDefaults()
            }
        } message: {
            Text("This will restore default timeouts, resolvers, font settings, and monitoring thresholds to factory standards.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("WORKBENCH PREFERENCES & TUNING")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("LOCAL-FIRST ZERO-TELEMETRY")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.signalEmerald)
                }

                Text("System Configuration & Telemetry Controls")
                    .font(.system(size: 20, weight: .bold))

                Text("Fine-tune low-level Darwin socket options, DNS engines, terminal appearance, and SQLite WAL retention.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    showingResetDefaultsAlert = true
                } label: {
                    Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                HUDStatusBadge(title: "v1.0.0 (Build 2026.1)", color: Theme.azurePro, icon: "checkmark.seal.fill")
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Sidebar Navigation

    private var sidebarNavigation: some View {
        VStack(spacing: 6) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedCategory == category ? Theme.neonCyan : .secondary)
                            .frame(width: 20)

                        Text(category.rawValue)
                            .font(.system(size: 12, weight: selectedCategory == category ? .bold : .regular))
                            .foregroundStyle(selectedCategory == category ? Color.white : .primary)

                        Spacer()

                        if selectedCategory == category {
                            Circle()
                                .fill(Theme.neonCyan)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedCategory == category ? Theme.neonCyan.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Database Live Status Widget in Sidebar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "cylinder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.signalEmerald)
                    Text("SQLITE WAL MODE")
                        .font(Theme.monoText(9, weight: .bold))
                        .foregroundStyle(Theme.signalEmerald)
                    Spacer()
                    Text(formattedFileSize(dbSizeBytes))
                        .font(Theme.monoText(9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("Zero external database connections. Local macOS sandbox storage.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.innerChipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .padding(.top, 16)
    }

    // MARK: - Category 1: General & UI

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "GENERAL & UI APPEARANCE", icon: "slider.horizontal.3", subtitle: "Configure theme accents, HUD notifications, sound chimes, and micro-animations")

            VStack(spacing: 16) {
                // Theme Appearance Cards
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WORKBENCH APPEARANCE & THEME")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(Theme.primaryAccent)
                            Text("Select your primary engineering workspace theme")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Active: \(themeManager.currentTheme.displayName)")
                            .font(Theme.monoText(10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(AppTheme.allCases) { theme in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    themeManager.currentTheme = theme
                                    state.toastMessage = "Switched to \(theme.displayName)"
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(theme.previewBackground)
                                            .frame(width: 38, height: 38)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(theme.previewAccent.opacity(0.4), lineWidth: 1.5)
                                            )

                                        Image(systemName: theme.iconName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(theme.previewAccent)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(theme.displayName)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.primary)

                                            if themeManager.currentTheme == theme {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(Theme.primaryAccent)
                                            }
                                        }

                                        Text(theme.subtitle)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .background(themeManager.currentTheme == theme ? Theme.primaryAccent.opacity(0.08) : Theme.innerChipBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            themeManager.currentTheme == theme ? Theme.primaryAccent : Theme.borderLight,
                                            lineWidth: themeManager.currentTheme == theme ? 1.5 : 1.0
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Accent Glow Tint
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accent Glow Color")
                            .font(.system(size: 12, weight: .medium))
                        Text("Visual telemetry highlight color across graphs and badges")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        accentColorButton(hex: "#00E5FF", title: "Neon Cyan")
                        accentColorButton(hex: "#33FF66", title: "Signal Emerald")
                        accentColorButton(hex: "#0A84FF", title: "Azure Pro")
                        accentColorButton(hex: "#BF5AF2", title: "Electric Violet")
                        accentColorButton(hex: "#FFB300", title: "Solar Amber")
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Telemetry Sound Chimes
                Toggle(isOn: $enableSoundEffects) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostic Audio Feedback")
                            .font(.system(size: 12, weight: .medium))
                        Text("Play subtle system audio chimes upon probe completion and threshold alerts")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Toast Duration Slider
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toast Alert Duration")
                            .font(.system(size: 12, weight: .medium))
                        Text("Length of time transient engineering toasts persist")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f sec", toastDurationSec))
                        .font(Theme.monoText(11, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                    Slider(value: $toastDurationSec, in: 1.5...6.0, step: 0.5)
                        .frame(width: 140)
                }

                Divider().overlay(Theme.borderLight)

                // Reduce Motion
                Toggle(isOn: $reduceMotion) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Low Overhead UI (Reduce Micro-Animations)")
                            .font(.system(size: 12, weight: .medium))
                        Text("Disables animated waveforms and particle pulses for maximum GPU/CPU efficiency")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .engineeringCard(padding: 16)
        }
    }

    private func accentColorButton(hex: String, title: String) -> some View {
        Button {
            accentColorHex = hex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 22, height: 22)
                if accentColorHex.caseInsensitiveCompare(hex) == .orderedSame {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: - Category 2: Diagnostics & Probing

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "DIAGNOSTICS & PROBE ENGINE", icon: "stethoscope", subtitle: "Low-level ICMP ping options, socket timeouts, MTU sweeps, and HTTP headers")

            VStack(spacing: 14) {
                // ICMP Packet Count
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default ICMP Ping Packets")
                            .font(.system(size: 12, weight: .medium))
                        Text("Number of sequential echo requests sent per diagnostic run")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $defaultPingCount) {
                        Text("3 packets").tag(3)
                        Text("5 packets (Balanced)").tag(5)
                        Text("10 packets (Standard)").tag(10)
                        Text("20 packets (High Confidence)").tag(20)
                        Text("50 packets (Stress Test)").tag(50)
                    }
                    .frame(width: 210)
                }

                Divider().overlay(Theme.borderLight)

                // ICMP Payload Size & MTU Sweep
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ICMP Payload Size (Bytes)")
                            .font(.system(size: 12, weight: .medium))
                        Text("Payload buffer size for detecting MTU restrictions & bufferbloat")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $pingPayloadBytes) {
                        Text("32 Bytes (Minimal)").tag(32)
                        Text("64 Bytes (BSD Ping Default)").tag(64)
                        Text("512 Bytes (Medium Frame)").tag(512)
                        Text("1472 Bytes (1500 MTU Test)").tag(1472)
                        Text("8972 Bytes (Jumbo 9000 MTU)").tag(8972)
                    }
                    .frame(width: 210)
                }

                Divider().overlay(Theme.borderLight)

                // Don't Fragment (DF) Bit
                Toggle(isOn: $setDontFragmentBit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set Don't Fragment (DF) Bit on IP Header")
                            .font(.system(size: 12, weight: .medium))
                        Text("Path MTU Discovery (PMTUD): Prohibits router packet slicing on transit links")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Probe Socket Timeout
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Probe Socket Timeout")
                            .font(.system(size: 12, weight: .medium))
                        Text("Maximum wait time before declaring unreachable/packet loss")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $defaultTimeoutMs) {
                        Text("500 ms (Aggressive)").tag(500)
                        Text("1,000 ms (Fast)").tag(1000)
                        Text("2,000 ms (Default)").tag(2000)
                        Text("3,000 ms (Generous)").tag(3000)
                        Text("5,000 ms (WAN/Satellite)").tag(5000)
                    }
                    .frame(width: 210)
                }

                Divider().overlay(Theme.borderLight)

                // Default TCP Probe Port
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default TCP Probe Port")
                            .font(.system(size: 12, weight: .medium))
                        Text("Default port tested for three-way handshake validation")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $defaultTcpPort) {
                        Text("Port 80 (HTTP)").tag(80)
                        Text("Port 443 (HTTPS / TLS)").tag(443)
                        Text("Port 22 (SSH Management)").tag(22)
                        Text("Port 53 (DNS Service)").tag(53)
                        Text("Port 8080 (HTTP Alt)").tag(8080)
                    }
                    .frame(width: 210)
                }

                Divider().overlay(Theme.borderLight)

                // HTTP User-Agent String
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom HTTP User-Agent")
                            .font(.system(size: 12, weight: .medium))
                        Text("Identifier sent with layer-7 HTTP/TLS diagnostic probes")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("User Agent", text: $customUserAgent)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.monoText(11))
                        .frame(width: 280)
                }

                Divider().overlay(Theme.borderLight)

                // Darwin Non-Root Socket Telemetry
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kernel Socket Implementation")
                            .font(.system(size: 12, weight: .medium))
                        Text("Privilege-free ICMP socket mode via macOS Darwin kernel")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(Theme.signalEmerald).frame(width: 8, height: 8)
                        Text("IPPROTO_ICMP (Non-Root Dgram)")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                }
            }
            .engineeringCard(padding: 16)
        }
    }

    // MARK: - Category 3: DNS & Encrypted Resolution

    private var dnsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "DNS & ENCRYPTED RESOLUTION", icon: "network", subtitle: "Configure primary & secondary resolvers, DNS-over-HTTPS (DoH), and flush macOS cache")

            VStack(spacing: 14) {
                // Primary Resolver
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Primary DNS Resolver")
                            .font(.system(size: 12, weight: .medium))
                        Text("First-choice upstream recursive resolver")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $preferredDNSResolver) {
                        Text("Cloudflare (1.1.1.1)").tag("1.1.1.1")
                        Text("Google (8.8.8.8)").tag("8.8.8.8")
                        Text("Quad9 (9.9.9.9 - Malware Filtered)").tag("9.9.9.9")
                        Text("AdGuard (94.140.14.14)").tag("94.140.14.14")
                        Text("OpenDNS (208.67.222.222)").tag("208.67.222.222")
                        Text("System DHCP Default").tag("System")
                        Text("Custom Resolver IP").tag("Custom")
                    }
                    .frame(width: 240)
                }

                if preferredDNSResolver == "Custom" {
                    HStack {
                        Text("Custom Primary IP")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("e.g. 192.168.1.1", text: $customDNSResolverIP)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.monoText(11))
                            .frame(width: 180)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Secondary Resolver
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Secondary DNS Resolver")
                            .font(.system(size: 12, weight: .medium))
                        Text("Fallback resolver used if primary does not respond")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $secondaryDNSResolver) {
                        Text("Cloudflare Secondary (1.0.0.1)").tag("1.0.0.1")
                        Text("Google Secondary (8.8.4.4)").tag("8.8.4.4")
                        Text("Quad9 Secondary (9.9.9.10)").tag("9.9.9.10")
                        Text("AdGuard Secondary (94.140.14.15)").tag("94.140.14.15")
                        Text("OpenDNS Secondary (208.67.220.220)").tag("208.67.220.220")
                    }
                    .frame(width: 240)
                }

                Divider().overlay(Theme.borderLight)

                // DoH Toggle & Endpoint
                VStack(spacing: 10) {
                    Toggle(isOn: $enableDoH) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable DNS-over-HTTPS (DoH RFC 8484)")
                                .font(.system(size: 12, weight: .medium))
                            Text("Encrypts DNS queries using HTTPS POST/GET with wire-format binary payloads")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if enableDoH {
                        HStack {
                            Text("DoH Upstream Endpoint")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $dohEndpoint) {
                                Text("Cloudflare (cloudflare-dns.com)").tag("https://cloudflare-dns.com/dns-query")
                                Text("Google (dns.google)").tag("https://dns.google/dns-query")
                                Text("Quad9 Secure (dns.quad9.net)").tag("https://dns.quad9.net/dns-query")
                                Text("AdGuard (dns.adguard-dns.com)").tag("https://dns.adguard-dns.com/dns-query")
                            }
                            .frame(width: 260)
                        }
                    }
                }

                Divider().overlay(Theme.borderLight)

                // DNSSEC Validation
                Toggle(isOn: $validateDNSSEC) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Validate DNSSEC Signatures")
                            .font(.system(size: 12, weight: .medium))
                        Text("Verifies cryptographic RRSIG and DS records to prevent DNS poisoning and spoofing")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Flush macOS Resolver Cache
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Flush macOS Resolver Cache")
                            .font(.system(size: 12, weight: .medium))
                        if let lastFlush = lastFlushDnsTimestamp {
                            Text("Last flushed at \(lastFlush.formatted(date: .omitted, time: .standard))")
                                .font(Theme.monoText(10))
                                .foregroundStyle(Theme.signalEmerald)
                        } else {
                            Text("Purges dscacheutil and sends HUP signal to mDNSResponder")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        flushSystemDNSCache()
                    } label: {
                        Label("Flush Cache Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .engineeringCard(padding: 16)
        }
    }

    private func flushSystemDNSCache() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]
        try? process.run()
        process.waitUntilExit()

        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProcess.arguments = ["-HUP", "mDNSResponder"]
        try? killProcess.run()
        killProcess.waitUntilExit()

        lastFlushDnsTimestamp = Date()
        state.toastMessage = "macOS DNS Resolver Cache Flushed Successfully"
    }

    // MARK: - Category 4: SLA & Background Monitoring

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "SLA & BACKGROUND MONITORING", icon: "waveform.path.ecg", subtitle: "Background polling frequency, SLA threshold alarms, and menu bar wave visualizer")

            VStack(spacing: 14) {
                // Polling Interval
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu Bar Probing Frequency")
                            .font(.system(size: 12, weight: .medium))
                        Text("Rate at which active gateways and WAN links are polled in background")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $menuBarIntervalSec) {
                        Text("Aggressive (1.0s)").tag(1.0)
                        Text("Balanced (2.5s - Default)").tag(2.5)
                        Text("Battery Saver (5.0s)").tag(5.0)
                        Text("Low Overhead (10.0s)").tag(10.0)
                    }
                    .frame(width: 200)
                }

                Divider().overlay(Theme.borderLight)

                // SLA Latency Warning Slider
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SLA Latency Warning Trigger")
                            .font(.system(size: 12, weight: .medium))
                        Text("RTT latency threshold above which link is flagged as degraded")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(slaLatencyThresholdMs)) ms")
                        .font(Theme.monoText(12, weight: .bold))
                        .foregroundStyle(slaLatencyThresholdMs > 80 ? Theme.amberWarning : Theme.signalEmerald)
                        .frame(width: 55, alignment: .trailing)
                    Slider(value: $slaLatencyThresholdMs, in: 10...200, step: 5)
                        .frame(width: 140)
                }

                Divider().overlay(Theme.borderLight)

                // SLA Packet Loss Slider
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SLA Packet Loss Alert Trigger")
                            .font(.system(size: 12, weight: .medium))
                        Text("Percentage of dropped packets triggering critical HUD alert")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(slaLossThresholdPct))%")
                        .font(Theme.monoText(12, weight: .bold))
                        .foregroundStyle(slaLossThresholdPct > 10 ? Theme.crimsonCritical : Theme.signalEmerald)
                        .frame(width: 55, alignment: .trailing)
                    Slider(value: $slaLossThresholdPct, in: 1...25, step: 1)
                        .frame(width: 140)
                }

                Divider().overlay(Theme.borderLight)

                // Menu Bar Icon Wave Style
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu Bar Status Wave Style")
                            .font(.system(size: 12, weight: .medium))
                        Text("Choose signature wave glyph for wired and wireless menu bar telemetry")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $menuBarIconStyle) {
                        Label("Next-Gen Wave (Signature)", systemImage: "waveform.path.ecg").tag("nextGenWave")
                        Label("Forward Waves (>>>)", systemImage: "wave.3.forward").tag("forwardWave")
                        Label("Carrier Wave (Sine)", systemImage: "waveform.path").tag("sineWave")
                        Label("Spectrum Bars", systemImage: "waveform").tag("spectrumWave")
                        Label("Unified Network (Globe)", systemImage: "network").tag("network")
                    }
                    .frame(width: 240)
                }

                // Interactive Live Menu Bar Visualizer
                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE MENU BAR ICON PREVIEW")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)

                    HStack(spacing: 12) {
                        // Simulated macOS Menu Bar Status Item
                        HStack(spacing: 6) {
                            menuBarIconPreview(style: menuBarIconStyle)
                                .foregroundStyle(Theme.neonCyan)
                            Text("14ms · 0% loss")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.neonCyan.opacity(0.35), lineWidth: 1)
                        )

                        Text("Preview shows live appearance on macOS system menu bar with active SLA telemetry.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Theme.innerChipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .engineeringCard(padding: 16)
        }
    }

    @ViewBuilder
    private func menuBarIconPreview(style: String) -> some View {
        switch style {
        case "forwardWave":
            Image(systemName: "wave.3.forward")
                .font(.system(size: 12, weight: .bold))
        case "sineWave":
            Image(systemName: "waveform.path")
                .font(.system(size: 12, weight: .bold))
        case "spectrumWave":
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
        case "network":
            Image(systemName: "network")
                .font(.system(size: 12, weight: .bold))
        default:
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12, weight: .bold))
        }
    }

    // MARK: - Category 5: Packet Capture & BPF

    private var packetCaptureSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "PACKET CAPTURE & BPF DRIVER", icon: "tray.full.fill", subtitle: "Berkeley Packet Filter ring buffer depth, promiscuous mode, and Wireshark bridge")

            VStack(spacing: 14) {
                // In-Memory Buffer Depth
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In-Memory Ring Buffer Depth")
                            .font(.system(size: 12, weight: .medium))
                        Text("Maximum frame capacity before FIFO rotation of capture buffer")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $maxPacketBufferSize) {
                        Text("1,000 packets (Low Memory)").tag(1000)
                        Text("2,000 packets (Standard)").tag(2000)
                        Text("5,000 packets (Extended)").tag(5000)
                        Text("10,000 packets (High Memory)").tag(10000)
                    }
                    .frame(width: 230)
                }

                Divider().overlay(Theme.borderLight)

                // Capture Snaplen
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capture Snaplen (Slice Size)")
                            .font(.system(size: 12, weight: .medium))
                        Text("Bytes captured per packet before truncating for memory savings")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $captureSnaplen) {
                        Text("64 Bytes (Headers Only)").tag(64)
                        Text("128 Bytes (Header + Transport)").tag(128)
                        Text("1,514 Bytes (Full Ethernet Frame)").tag(1514)
                        Text("9,000 Bytes (Jumbo Frame)").tag(9000)
                    }
                    .frame(width: 230)
                }

                Divider().overlay(Theme.borderLight)

                // Promiscuous Mode
                Toggle(isOn: $enablePromiscuousMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Promiscuous Mode Capture")
                            .font(.system(size: 12, weight: .medium))
                        Text("Allows network interface to inspect all packets on the broadcast domain")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Wireshark Detection
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wireshark Native App Integration")
                            .font(.system(size: 12, weight: .medium))
                        Text("Detects local Wireshark installation for 1-click PCAP bridge")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let wiresharkURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.wireshark.Wireshark") {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Installed (/Applications)")
                            }
                            .font(Theme.monoText(10, weight: .semibold))
                            .foregroundStyle(Theme.signalEmerald)

                            Button("Launch") {
                                NSWorkspace.shared.open(wiresharkURL)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                            Text("Not Detected (Optional)")
                        }
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Darwin BPF Driver Info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Darwin BPF Driver Interface")
                            .font(.system(size: 12, weight: .medium))
                        Text("Zero-copy packet tap via macOS `/dev/bpf*` character devices")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("/dev/bpf0...255 (Darwin Packet Filter)")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.neonCyan)
                }
            }
            .engineeringCard(padding: 16)
        }
    }

    // MARK: - Category 6: Terminal & Serial Console

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "TERMINAL & SERIAL CONSOLE BRIDGE", icon: "terminal.fill", subtitle: "Monospace typography, color themes, cursor blinking, and interactive preview")

            VStack(spacing: 14) {
                // Font Family
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monospace Font Family")
                            .font(.system(size: 12, weight: .medium))
                        Text("Developer monospace font used for SSH, Telnet, and Serial sessions")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $terminalFontFamily) {
                        ForEach(TerminalFontFamily.allCases) { f in
                            Text(f.rawValue).tag(f.rawValue)
                        }
                    }
                    .frame(width: 200)
                }

                Divider().overlay(Theme.borderLight)

                // Font Size & Line Spacing
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Font Size & Line Spacing")
                            .font(.system(size: 12, weight: .medium))
                        Text("Text size and vertical padding between terminal output rows")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 14) {
                        HStack(spacing: 6) {
                            Text("\(Int(terminalFontSize)) pt")
                                .font(Theme.monoText(11, weight: .bold))
                                .foregroundStyle(Theme.neonCyan)
                            Stepper("", value: $terminalFontSize, in: 9...24, step: 1)
                                .labelsHidden()
                        }

                        HStack(spacing: 6) {
                            Text(String(format: "%.1fx", terminalLineSpacing))
                                .font(Theme.monoText(11, weight: .bold))
                                .foregroundStyle(.secondary)
                            Stepper("", value: $terminalLineSpacing, in: 1.0...4.0, step: 0.5)
                                .labelsHidden()
                        }
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Color Theme
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Terminal Color Theme")
                            .font(.system(size: 12, weight: .medium))
                        Text("High-contrast palettes designed for prolonged CLI operations")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $terminalTheme) {
                        ForEach(TerminalTheme.allCases) { t in
                            Text(t.rawValue).tag(t.rawValue)
                        }
                    }
                    .frame(width: 200)
                }

                Divider().overlay(Theme.borderLight)

                // Cursor Style & Blink
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor Style & Blinking")
                            .font(.system(size: 12, weight: .medium))
                        Text("Choose cursor shape and toggle real-time blinking animation")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Picker("", selection: $terminalCursorStyle) {
                            ForEach(TerminalCursorStyle.allCases) { c in
                                Text(c.rawValue).tag(c.rawValue)
                            }
                        }
                        .frame(width: 130)

                        Toggle("Blink", isOn: $terminalCursorBlink)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Default SSH User & Baud Rate
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default SSH User & Serial Baud")
                            .font(.system(size: 12, weight: .medium))
                        Text("Pre-filled credentials and standard console port speed")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        TextField("admin", text: $defaultSSHUser)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.monoText(11))
                            .frame(width: 100)

                        Picker("", selection: $defaultSerialBaud) {
                            Text("9600 bps (Cisco)").tag(9600)
                            Text("19200 bps").tag(19200)
                            Text("38400 bps").tag(38400)
                            Text("57600 bps").tag(57600)
                            Text("115200 bps (Arista)").tag(115200)
                        }
                        .frame(width: 150)
                    }
                }

                // Interactive Live Monospace Terminal Box Preview (Isolated lifecycle)
                TerminalPreviewBoxView(
                    currentTerminalTheme: currentTerminalTheme,
                    activeCursorGlyph: activeCursorGlyph,
                    terminalCursorBlink: terminalCursorBlink,
                    terminalLineSpacing: terminalLineSpacing,
                    customTerminalFont: customTerminalFont,
                    terminalFontFamily: terminalFontFamily,
                    terminalFontSize: terminalFontSize,
                    terminalTheme: terminalTheme
                )
            }
            .engineeringCard(padding: 16)
        }
    }

    private var currentTerminalTheme: TerminalTheme {
        TerminalTheme(rawValue: terminalTheme) ?? .obsidian
    }

    private var activeCursorGlyph: String {
        switch terminalCursorStyle {
        case TerminalCursorStyle.beam.rawValue:
            return "❘"
        case TerminalCursorStyle.underline.rawValue:
            return "_"
        default:
            return "▋"
        }
    }

    private var customTerminalFont: Font {
        if let family = TerminalFontFamily(rawValue: terminalFontFamily) {
            return .custom(family.fontName, size: CGFloat(terminalFontSize))
        }
        return Theme.monoText(CGFloat(terminalFontSize))
    }

    // MARK: - Category 7: SNMP Studio Preferences

    private var snmpSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "SNMP STUDIO DEFAULTS", icon: "server.rack", subtitle: "Default community strings, port, retries, timeout, and MIB-II polling groups")

            VStack(spacing: 14) {
                // Community String & Port
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Community String & Port")
                            .font(.system(size: 12, weight: .medium))
                        Text("Authentication secret used for SNMPv1/v2c queries")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        SecureField("Community", text: $snmpDefaultCommunity)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.monoText(11))
                            .frame(width: 120)

                        Text("Port:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Picker("", selection: $snmpDefaultPort) {
                            Text("161 (Standard)").tag(161)
                            Text("10161 (Alt)").tag(10161)
                            Text("162 (Trap)").tag(162)
                        }
                        .frame(width: 130)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Timeout & Retries
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Request Timeout & Retries")
                            .font(.system(size: 12, weight: .medium))
                        Text("UDP timeout interval and retry count before flagging agent timeout")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Picker("Timeout", selection: $snmpDefaultTimeoutMs) {
                            Text("1,000 ms").tag(1000)
                            Text("2,000 ms (Default)").tag(2000)
                            Text("3,000 ms").tag(3000)
                            Text("5,000 ms").tag(5000)
                        }
                        .frame(width: 140)

                        Picker("Retries", selection: $snmpDefaultRetries) {
                            Text("1 retry").tag(1)
                            Text("2 retries").tag(2)
                            Text("3 retries").tag(3)
                            Text("5 retries").tag(5)
                        }
                        .frame(width: 110)
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Default Protocol Version
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Protocol Version")
                            .font(.system(size: 12, weight: .medium))
                        Text("SNMP protocol version used for automated device interrogation")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $snmpDefaultVersion) {
                        Text("SNMPv1 (Legacy RFC 1157)").tag(0)
                        Text("SNMPv2c (Community RFC 1901)").tag(1)
                        Text("SNMPv3 (Encrypted USM RFC 3414)").tag(3)
                    }
                    .frame(width: 250)
                }

                Divider().overlay(Theme.borderLight)

                // Default OID Polling Presets
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default MIB Polling Group")
                            .font(.system(size: 12, weight: .medium))
                        Text("Standard OID subtree queried during rapid device discovery")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $snmpDefaultOidGroup) {
                        Text("RFC 1213 System (1.3.6.1.2.1.1)").tag("system")
                        Text("IF-MIB Interfaces (1.3.6.1.2.1.2)").tag("interfaces")
                        Text("HOST-RESOURCES-MIB (1.3.6.1.2.1.25)").tag("hostResources")
                        Text("IP-MIB Routing (1.3.6.1.2.1.4)").tag("routing")
                    }
                    .frame(width: 250)
                }
            }
            .engineeringCard(padding: 16)
        }
    }

    // MARK: - Category 8: Storage, Database & Backup

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "DATA RETENTION & DATABASE MAINTENANCE", icon: "cylinder.split.1x2.fill", subtitle: "SQLite WAL statistics, table row counts, optimization vacuum, and full backups")

            // Database Statistics Card
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SQLite Database File Size")
                            .font(.system(size: 12, weight: .medium))
                        Text(state.database.path)
                            .font(Theme.monoText(9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(formattedFileSize(dbSizeBytes))
                        .font(Theme.monoText(13, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                }

                Divider().overlay(Theme.borderLight)

                // Live Table Row Counts Grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE ROW COUNTS BY REPOSITORY")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.signalEmerald)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        metricChip(title: "Diagnostic Runs", count: dbRowCounts["diagnostic_history"] ?? state.recentHistory.count, icon: "stethoscope")
                        metricChip(title: "Investigations", count: dbRowCounts["investigations"] ?? state.investigations.count, icon: "shield.lefthalf.filled")
                        metricChip(title: "Timeline Events", count: dbRowCounts["timeline_events"] ?? 0, icon: "clock.arrow.circlepath")
                        metricChip(title: "Forensic Artifacts", count: dbRowCounts["forensic_artifacts"] ?? 0, icon: "doc.zipper")
                        metricChip(title: "Managed Devices", count: dbRowCounts["managed_devices"] ?? state.managedDevices.count, icon: "server.rack")
                        metricChip(title: "Custom Scripts", count: dbRowCounts["custom_scripts"] ?? 0, icon: "scroll.fill")
                    }
                }

                Divider().overlay(Theme.borderLight)

                // Actions: Vacuum, Backup, Clear
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Optimize & Vacuum Database")
                                .font(.system(size: 12, weight: .medium))
                            if let lastVac = lastVacuumTimestamp {
                                Text("Reclaimed pages & updated query statistics at \(lastVac.formatted(date: .omitted, time: .standard))")
                                    .font(Theme.monoText(10))
                                    .foregroundStyle(Theme.signalEmerald)
                            } else {
                                Text("Executes SQLite VACUUM and ANALYZE to reclaim disk space and rebuild query plans")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            runVacuumOptimization()
                        } label: {
                            if isVacuuming {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Vacuum & Optimize", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isVacuuming)
                    }

                    Divider().overlay(Theme.borderLight)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export Full SQLite Backup (.sqlite)")
                                .font(.system(size: 12, weight: .medium))
                            Text("Create an atomic, transaction-safe snapshot of all tables, devices, and history")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            exportDatabaseBackup()
                        } label: {
                            Label("Export Backup...", systemImage: "arrow.down.doc.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.azurePro)
                        .controlSize(.small)
                    }

                    Divider().overlay(Theme.borderLight)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Diagnostic History")
                                .font(.system(size: 12, weight: .medium))
                            Text("Delete all historic test runs. Managed devices and investigations are preserved")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showingClearHistoryAlert = true
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .engineeringCard(padding: 16)
        }
    }

    private func metricChip(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.neonCyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Theme.innerChipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func refreshDatabaseMetrics() {
        let stats = state.getDatabaseStats()
        self.dbSizeBytes = stats.fileSizeBytes
        self.dbRowCounts = stats.rowCounts
    }

    private func runVacuumOptimization() {
        isVacuuming = true
        Task { @MainActor in
            state.vacuumDatabase()
            self.isVacuuming = false
            self.lastVacuumTimestamp = Date()
            self.refreshDatabaseMetrics()
        }
    }

    private func exportDatabaseBackup() {
        let panel = NSSavePanel()
        panel.title = "Export SQLite Database Backup"
        panel.nameFieldStringValue = "NexWave_Backup_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).sqlite"
        panel.allowedContentTypes = [.data]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try state.backupDatabase(to: url)
                refreshDatabaseMetrics()
            } catch {
                state.toastMessage = "Backup failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Category 9: System Telemetry & About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: "SYSTEM TELEMETRY & ABOUT", icon: "info.circle.fill", subtitle: "Kernel version, CPU architecture, network interfaces, and zero-telemetry policy")

            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.neonCyan.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NexWave Network Workbench")
                            .font(.system(size: 16, weight: .bold))
                        Text("Version 1.0.0 (Build 2026.1 Enterprise Release)")
                            .font(Theme.monoText(11))
                            .foregroundStyle(.secondary)
                        Text("Apple Swift 6 · Darwin Native · Zero GPL Dependencies")
                            .font(Theme.monoText(10, weight: .semibold))
                            .foregroundStyle(Theme.signalEmerald)
                    }
                    Spacer()
                }

                Divider().overlay(Theme.borderLight)

                // Host Telemetry Grid
                VStack(spacing: 10) {
                    systemRow(label: "Operating System", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    systemRow(label: "Host Architecture", value: hostArchitectureString)
                    systemRow(label: "Logical CPU Cores", value: "\(ProcessInfo.processInfo.activeProcessorCount) Cores Available")
                    systemRow(label: "Physical RAM Memory", value: String(format: "%.1f GB Unified Memory", Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)))
                    systemRow(label: "Local Hostname", value: ProcessInfo.processInfo.hostName)
                    systemRow(label: "Apple Sandbox & Hardening", value: "App Sandbox Active · Hardened Runtime Active")
                }

                Divider().overlay(Theme.borderLight)

                // Zero-Telemetry Compliance Statement
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.signalEmerald)
                        Text("ENTERPRISE LOCAL-FIRST ZERO-TELEMETRY GUARANTEE")
                            .font(Theme.monoText(10, weight: .bold))
                            .foregroundStyle(Theme.signalEmerald)
                    }

                    Text("NexWave Network Workbench operates strictly on your local Mac. Diagnostic runs, packet captures, credentials, and topology graphs never leave this device. No remote analytics, telemetry beacons, or third-party cloud connections are ever initiated.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Theme.innerChipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .engineeringCard(padding: 16)
        }
    }

    private var hostArchitectureString: String {
        #if arch(arm64)
        return "Apple Silicon (ARM64 Native)"
        #else
        return "Intel (x86_64 Native)"
        #endif
    }

    private func systemRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoText(11, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Helper Views & Methods

    private func cardHeader(title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.monoText(12, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    private func resetAllPreferencesToDefaults() {
        themeManager.currentTheme = .cyberDark
        accentColorHex = "#00E5FF"
        enableSoundEffects = true
        toastDurationSec = 3.0
        reduceMotion = false

        defaultPingCount = 5
        pingPayloadBytes = 64
        setDontFragmentBit = false
        defaultTimeoutMs = 2000
        defaultTcpPort = 80
        customUserAgent = "NexWave-Workbench/1.0 (Macintosh; Apple Silicon)"

        preferredDNSResolver = "1.1.1.1"
        secondaryDNSResolver = "1.0.0.1"
        customDNSResolverIP = ""
        enableDoH = true
        dohEndpoint = "https://cloudflare-dns.com/dns-query"
        validateDNSSEC = true

        menuBarIntervalSec = 2.5
        menuBarIconStyle = "nextGenWave"
        slaLatencyThresholdMs = 50.0
        slaLossThresholdPct = 5.0

        maxPacketBufferSize = 2000
        captureSnaplen = 1514
        enablePromiscuousMode = true

        terminalFontFamily = "SF Mono (System)"
        terminalFontSize = 12.0
        terminalLineSpacing = 2.0
        terminalTheme = TerminalTheme.obsidian.rawValue
        terminalCursorStyle = TerminalCursorStyle.block.rawValue
        terminalCursorBlink = true
        defaultSSHUser = "admin"
        defaultSSHPort = 22
        defaultSerialBaud = 9600

        snmpDefaultCommunity = "public"
        snmpDefaultPort = 161
        snmpDefaultTimeoutMs = 2000
        snmpDefaultRetries = 2
        snmpDefaultVersion = 1
        snmpDefaultOidGroup = "system"

        state.toastMessage = "All preferences reset to factory defaults."
    }
}

// MARK: - Dedicated Terminal Live Preview with Isolated Cursor Timer
private struct TerminalPreviewBoxView: View {
    let currentTerminalTheme: TerminalTheme
    let activeCursorGlyph: String
    let terminalCursorBlink: Bool
    let terminalLineSpacing: Double
    let customTerminalFont: Font
    let terminalFontFamily: String
    let terminalFontSize: Double
    let terminalTheme: String

    @State private var cursorVisible: Bool = true
    private let cursorTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVE TERMINAL PREVIEW")
                    .font(Theme.monoText(10, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Text("\(terminalFontFamily) · \(Int(terminalFontSize))pt · \(terminalTheme)")
                    .font(Theme.monoText(9))
                    .foregroundStyle(.secondary)
            }

            // Terminal Window Canvas
            VStack(alignment: .leading, spacing: 0) {
                // Titlebar
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "#FF5F56")).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: "#FFBD2E")).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: "#27C93F")).frame(width: 9, height: 9)
                    Spacer()
                    Text("admin@nexwave-core# (pty3)")
                        .font(Theme.monoText(9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.4))

                // Terminal Body
                VStack(alignment: .leading, spacing: CGFloat(terminalLineSpacing)) {
                    HStack(spacing: 0) {
                        Text("nexwave-core# ")
                            .foregroundStyle(Color(hex: currentTerminalTheme.promptColorHex))
                        Text("show ip bgp summary")
                            .foregroundStyle(Color(hex: currentTerminalTheme.foregroundColorHex))
                        if cursorVisible {
                            Text(activeCursorGlyph)
                                .foregroundStyle(Color(hex: currentTerminalTheme.promptColorHex))
                        }
                    }

                    Text("BGP router identifier 10.0.0.1, local AS number 65001")
                        .foregroundStyle(Color(hex: currentTerminalTheme.foregroundColorHex).opacity(0.85))

                    Text("Neighbor        V    AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd")
                        .foregroundStyle(Color(hex: currentTerminalTheme.foregroundColorHex).opacity(0.7))

                    Text("192.168.1.2     4 65002    1420    1419       12    0    0 02:45:11            4")
                        .foregroundStyle(Theme.signalEmerald)

                    Text("192.168.2.2     4 65003     890     892       12    0    0 01:12:30            6")
                        .foregroundStyle(Theme.signalEmerald)
                }
                .font(customTerminalFont)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: currentTerminalTheme.backgroundColorHex))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.cardBorderHighContrast, lineWidth: 1)
            )
        }
        .padding(12)
        .background(Theme.innerChipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onReceive(cursorTimer) { _ in
            if terminalCursorBlink {
                cursorVisible.toggle()
            } else if !cursorVisible {
                cursorVisible = true
            }
        }
    }
}
