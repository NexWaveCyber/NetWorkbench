import SwiftUI
import TerminalKit
import SecurityKit
import PersistenceKit
import DNSEngine

/// Comprehensive Settings & Preferences workspace for NexWave Network Workbench
public struct SettingsWorkspaceView: View {
    @Bindable var state: AppState

    @AppStorage("defaultPingCount") private var defaultPingCount: Int = 5
    @AppStorage("defaultTimeoutMs") private var defaultTimeoutMs: Int = 2000
    @AppStorage("preferredDNSResolver") private var preferredDNSResolver: String = "1.1.1.1"
    @AppStorage("enableDoH") private var enableDoH: Bool = true
    @AppStorage("menuBarIntervalSec") private var menuBarIntervalSec: Double = 2.5
    @AppStorage("menuBarIconStyle") private var menuBarIconStyle: String = "nextGenWave"
    @AppStorage("slaLatencyThresholdMs") private var slaLatencyThresholdMs: Double = 50.0
    @AppStorage("slaLossThresholdPct") private var slaLossThresholdPct: Double = 5.0
    @AppStorage("maxPacketBufferSize") private var maxPacketBufferSize: Int = 2000
    @AppStorage("defaultSSHUser") private var defaultSSHUser: String = "admin"
    @AppStorage("defaultSerialBaud") private var defaultSerialBaud: Int = 9600
    @AppStorage("terminal_font_size") private var terminalFontSize: Double = 12.0
    @AppStorage("terminal_font_family") private var terminalFontFamily: String = "SF Mono (System)"
    @AppStorage("terminal_theme") private var terminalTheme: String = TerminalTheme.obsidian.rawValue
    @AppStorage("terminal_cursor_style") private var terminalCursorStyle: String = TerminalCursorStyle.block.rawValue
    @AppStorage("terminal_cursor_blink") private var terminalCursorBlink: Bool = true
    @AppStorage("terminal_line_spacing") private var terminalLineSpacing: Double = 2.0

    @State private var showingClearHistoryAlert: Bool = false
    @State private var showingFlushDNSAlert: Bool = false
    @State private var flushDNSMessage: String = ""

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerBar

                // Settings Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    // Diagnostics & Probing
                    diagnosticsSection

                    // DNS & Resolution
                    dnsSection

                    // Menu Bar & SLA Monitoring
                    monitoringSection

                    // Live Packet Capture
                    packetSection

                    // Terminal & Console Bridge
                    terminalSection

                    // Storage, Security & Privacy
                    storageSection
                }
            }
            .padding(24)
        }
        .background(Theme.secondaryBackground)
        .navigationTitle("Settings & Preferences")
        .alert("Clear Diagnostic History?", isPresented: $showingClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All History", role: .destructive) {
                try? state.database.clearDiagnosticHistory()
                state.recentHistory.removeAll()
            }
        } message: {
            Text("This will permanently delete all saved diagnostic logs and test runs from the local SQLite database. This cannot be undone.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.neonCyan.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.neonCyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("PREFERENCES & SYSTEM TUNING")
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("LOCAL-FIRST ZERO-TELEMETRY")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                Text("Settings & Privacy")
                    .font(.system(size: 20, weight: .bold))

                Text("Configure probe parameters, DNS engines, capture buffers, and local data policies.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HUDStatusBadge(title: "v1.0.0 (Build 1)", color: Theme.azurePro, icon: "checkmark.seal.fill")
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "DIAGNOSTICS & PROBING", icon: "stethoscope")

            VStack(spacing: 10) {
                HStack {
                    Text("Default Ping Packets")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $defaultPingCount) {
                        Text("3 packets").tag(3)
                        Text("5 packets").tag(5)
                        Text("10 packets").tag(10)
                        Text("20 packets").tag(20)
                    }
                    .frame(width: 140)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Probe Timeout")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $defaultTimeoutMs) {
                        Text("1,000 ms").tag(1000)
                        Text("2,000 ms").tag(2000)
                        Text("3,000 ms").tag(3000)
                        Text("5,000 ms").tag(5000)
                    }
                    .frame(width: 140)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Socket Mode")
                        .font(.system(size: 12))
                    Spacer()
                    Text("Darwin IPPROTO_ICMP (Non-Root)")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.signalEmerald)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - DNS Section

    private var dnsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "DNS & ENCRYPTED RESOLUTION", icon: "network")

            VStack(spacing: 10) {
                HStack {
                    Text("Primary Resolver")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $preferredDNSResolver) {
                        Text("Cloudflare (1.1.1.1)").tag("1.1.1.1")
                        Text("Google (8.8.8.8)").tag("8.8.8.8")
                        Text("Quad9 (9.9.9.9)").tag("9.9.9.9")
                        Text("System DHCP Default").tag("System")
                    }
                    .frame(width: 170)
                }

                Divider().overlay(Theme.borderLight)

                Toggle(isOn: $enableDoH) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable DNS-over-HTTPS (DoH)")
                            .font(.system(size: 12))
                        Text("RFC 8484 encrypted wire format queries")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Flush macOS Resolver Cache")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Flush Cache") {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
                        process.arguments = ["-flushcache"]
                        try? process.run()
                        process.waitUntilExit()
                        state.toastMessage = "macOS DNS Cache Flushed Successfully"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Monitoring & Menu Bar Section

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "MONITORING & MENU BAR", icon: "waveform.path.ecg")

            VStack(spacing: 10) {
                HStack {
                    Text("Menu Bar Probing Rate")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $menuBarIntervalSec) {
                        Text("Fast (1.5s)").tag(1.5)
                        Text("Balanced (2.5s)").tag(2.5)
                        Text("Battery Saver (5.0s)").tag(5.0)
                    }
                    .frame(width: 150)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("SLA Latency Warning Trigger")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(slaLatencyThresholdMs)) ms")
                        .font(Theme.monoText(11, weight: .bold))
                    Slider(value: $slaLatencyThresholdMs, in: 20...150, step: 5)
                        .frame(width: 100)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("SLA Packet Loss Alert Trigger")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(slaLossThresholdPct))%")
                        .font(Theme.monoText(11, weight: .bold))
                    Slider(value: $slaLossThresholdPct, in: 1...20, step: 1)
                        .frame(width: 100)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu Bar Status Icon")
                            .font(.system(size: 12))
                        Text("NexWave brand-aligned next-gen wave telemetry for wired & wireless users")
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
                    .frame(width: 230)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Packet Capture Section

    private var packetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "PACKET CAPTURE & BPF", icon: "tray.full.fill")

            VStack(spacing: 10) {
                HStack {
                    Text("In-Memory Buffer Depth")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $maxPacketBufferSize) {
                        Text("1,000 packets").tag(1000)
                        Text("2,000 packets (Default)").tag(2000)
                        Text("5,000 packets").tag(5000)
                    }
                    .frame(width: 170)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Wireshark App Status")
                        .font(.system(size: 12))
                    Spacer()
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.wireshark.Wireshark") != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Installed (/Applications)")
                        }
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.signalEmerald)
                    } else {
                        Text("Not Detected (Optional)")
                            .font(Theme.monoText(10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("BPF Driver Interface")
                        .font(.system(size: 12))
                    Spacer()
                    Text("/dev/bpf* (Darwin Non-Root)")
                        .font(Theme.monoText(10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Terminal Section

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "TERMINAL & SERIAL BRIDGE", icon: "terminal.fill")

            VStack(spacing: 10) {
                HStack {
                    Text("Monospace Font Family")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $terminalFontFamily) {
                        ForEach(TerminalFontFamily.allCases) { f in
                            Text(f.rawValue).tag(f.rawValue)
                        }
                    }
                    .frame(width: 170)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Default Font Size")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(terminalFontSize)) pt")
                        .font(Theme.monoText(11, weight: .bold))
                    Stepper("", value: $terminalFontSize, in: 9...24, step: 1)
                        .labelsHidden()
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Default Color Theme")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $terminalTheme) {
                        ForEach(TerminalTheme.allCases) { t in
                            Text(t.rawValue).tag(t.rawValue)
                        }
                    }
                    .frame(width: 170)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Cursor Style & Blinking")
                        .font(.system(size: 12))
                    Spacer()
                    HStack(spacing: 8) {
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

                HStack {
                    Text("Default SSH Username")
                        .font(.system(size: 12))
                    Spacer()
                    TextField("admin", text: $defaultSSHUser)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Default Console Baud Rate")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $defaultSerialBaud) {
                        Text("9600 bps (Cisco / Juniper)").tag(9600)
                        Text("115200 bps (Arista)").tag(115200)
                    }
                    .frame(width: 170)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Active Serial Ports")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(state.terminalManager.availableSerialPorts.count) Detected")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.neonCyan)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Storage & Privacy Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "DATA RETENTION & PRIVACY", icon: "lock.shield.fill")

            VStack(spacing: 10) {
                HStack {
                    Text("Database Mode")
                        .font(.system(size: 12))
                    Spacer()
                    Text("SQLite WAL Mode (Local-Only)")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.signalEmerald)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Hardware Keychain")
                        .font(.system(size: 12))
                    Spacer()
                    Text("Secure Enclave Protected")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.signalEmerald)
                }

                Divider().overlay(Theme.borderLight)

                HStack {
                    Text("Clear Diagnostic Records")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Clear History", role: .destructive) {
                        showingClearHistoryAlert = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .engineeringCard(padding: 16)
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.neonCyan)
            Text(title)
                .font(Theme.monoText(11, weight: .bold))
                .foregroundStyle(Color.white)
        }
    }
}
