import SwiftUI
import AppKit
import PacketKit

public struct FollowTCPStreamSheet: View {
    public let result: TCPStreamReassemblyResult
    public let onDismiss: () -> Void

    @State private var viewMode: StreamViewMode = .dialogue
    @State private var searchText: String = ""

    public enum StreamViewMode: String, CaseIterable, Identifiable {
        case dialogue = "Dialogue (Chronological)"
        case clientOnly = "Client ➔ Server Only"
        case serverOnly = "Server ➔ Client Only"
        case rawHex = "Hex & ASCII"
        case fullText = "Full Transcript"

        public var id: String { rawValue }
    }

    public init(result: TCPStreamReassemblyResult, onDismiss: @escaping () -> Void) {
        self.result = result
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            Divider().overlay(Theme.borderLight)

            // Stream Statistics & Controls Bar
            controlsBar
            Divider().overlay(Theme.borderLight)

            // Content Body
            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Theme.borderLight)

            // Footer Action Bar
            footerBar
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.surfaceBackground)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.cyanPulse)

            VStack(alignment: .leading, spacing: 2) {
                Text("FOLLOW TCP STREAM")
                    .font(Theme.monoText(13, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(result.streamId)
                    .font(Theme.monoText(11))
                    .foregroundStyle(Theme.cyanPulse)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.cardBackground.opacity(0.8))
    }

    // MARK: - Controls Bar
    private var controlsBar: some View {
        HStack(spacing: 12) {
            // Mode Picker
            Picker("View Mode", selection: $viewMode) {
                ForEach(StreamViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer()

            // In-stream search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search in stream...", text: $searchText)
                    .font(Theme.monoText(11))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
            .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.cardBackground.opacity(0.3))
    }

    // MARK: - Content Body
    private var contentBody: some View {
        Group {
            switch viewMode {
            case .dialogue:
                dialogueView(segments: filteredSegments)
            case .clientOnly:
                dialogueView(segments: filteredSegments.filter { $0.direction == .clientToServer })
            case .serverOnly:
                dialogueView(segments: filteredSegments.filter { $0.direction == .serverToClient })
            case .rawHex:
                rawHexView(segments: filteredSegments)
            case .fullText:
                fullTranscriptView
            }
        }
    }

    private var filteredSegments: [TCPStreamSegment] {
        if searchText.isEmpty {
            return result.segments
        }
        let term = searchText.lowercased()
        return result.segments.filter { $0.asciiText.lowercased().contains(term) }
    }

    // MARK: - Dialogue Mode
    private func dialogueView(segments: [TCPStreamSegment]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if segments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(result.segments.isEmpty ? "No payload bytes in this TCP stream (handshake/acknowledgments only)" : "No content matches '\(searchText)'")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                } else {
                    ForEach(segments) { seg in
                        segmentCard(seg)
                    }
                }
            }
            .padding(16)
        }
    }

    private func segmentCard(_ seg: TCPStreamSegment) -> some View {
        let isClient = (seg.direction == .clientToServer)
        let tintColor = isClient ? Theme.cyanPulse : Theme.amberWarning

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(tintColor).frame(width: 7, height: 7)
                    Text(seg.direction.rawValue)
                        .font(Theme.monoText(10, weight: .bold))
                        .foregroundStyle(tintColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tintColor.opacity(0.15))
                .clipShape(Capsule())

                Text("Packet #\(seg.packetNumber)")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)

                Text("Seq: \(seg.seq)")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(seg.payload.count) bytes")
                    .font(Theme.monoText(10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(seg.asciiText)
                .font(Theme.monoText(11))
                .foregroundStyle(Color.white.opacity(0.95))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(tintColor.opacity(0.3), lineWidth: 1))
        }
        .padding(12)
        .background(Theme.cardBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: - Raw Hex View
    private func rawHexView(segments: [TCPStreamSegment]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { seg in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(seg.direction.rawValue) — Packet #\(seg.packetNumber)")
                                .font(Theme.monoText(10, weight: .bold))
                                .foregroundStyle(seg.direction == .clientToServer ? Theme.cyanPulse : Theme.amberWarning)
                            Spacer()
                            Text("\(seg.payload.count) bytes")
                                .font(Theme.monoText(10))
                                .foregroundStyle(.secondary)
                        }

                        Text(seg.hexDump)
                            .font(Theme.monoText(11))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .textSelection(.enabled)
                            .padding(10)
                            .background(Theme.surfaceBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(12)
                    .background(Theme.cardBackground.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
    }

    // MARK: - Full Transcript View
    private var fullTranscriptView: some View {
        ScrollView {
            Text(result.combinedAscii)
                .font(Theme.monoText(11))
                .foregroundStyle(Color.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack(spacing: 12) {
            // Stats summary
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle().fill(Theme.cyanPulse).frame(width: 6, height: 6)
                    Text("Client: \(result.clientBytes)B")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.cyanPulse)
                }

                HStack(spacing: 5) {
                    Circle().fill(Theme.amberWarning).frame(width: 6, height: 6)
                    Text("Server: \(result.serverBytes)B")
                        .font(Theme.monoText(10, weight: .semibold))
                        .foregroundStyle(Theme.amberWarning)
                }

                Text("• Total: \(result.totalBytes)B in \(result.segments.count) segments")
                    .font(Theme.monoText(10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.combinedAscii, forType: .string)
            }) {
                Label("Copy Transcript", systemImage: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)

            Button(action: saveStreamToFile) {
                Label("Save Stream...", systemImage: "arrow.down.doc.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.cyanPulse)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cardBackground.opacity(0.7))
    }

    private func saveStreamToFile() {
        let savePanel = NSSavePanel()
        let cleanId = result.streamId.replacingOccurrences(of: " ⟷ ", with: "_").replacingOccurrences(of: ":", with: "_")
        savePanel.nameFieldStringValue = "tcp_stream_\(cleanId).txt"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? result.combinedAscii.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
