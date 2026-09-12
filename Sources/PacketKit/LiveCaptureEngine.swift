import Foundation
import Darwin

public enum BPFAccessStatus: Sendable, Equatable {
    case accessible
    case requiresElevation(reason: String)
    case unsupported
}

public struct CaptureInterface: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let ipAddress: String?
    public let isUp: Bool
    public let isRunning: Bool
    public let isWireless: Bool
    public let isLoopback: Bool

    public init(
        name: String,
        displayName: String,
        ipAddress: String?,
        isUp: Bool = true,
        isRunning: Bool = true,
        isWireless: Bool = false,
        isLoopback: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.ipAddress = ipAddress
        self.isUp = isUp
        self.isRunning = isRunning
        self.isWireless = isWireless
        self.isLoopback = isLoopback
    }
}

public enum LiveCaptureEngine {

    /// Enumerates active Darwin network interfaces with their bound IP addresses.
    public static func discoverInterfaces() -> [CaptureInterface] {
        var interfaces: [String: (ip: String?, isUp: Bool, isRunning: Bool, isLoopback: Bool)] = [:]

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return fallbackInterfaces()
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            let name = String(cString: cur.pointee.ifa_name)
            let flags = Int32(cur.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            var ipStr: String? = nil
            if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    ipStr = String(cString: &hostname)
                }
            }

            if let existing = interfaces[name] {
                interfaces[name] = (existing.ip ?? ipStr, existing.isUp || isUp, existing.isRunning || isRunning, existing.isLoopback || isLoopback)
            } else {
                interfaces[name] = (ipStr, isUp, isRunning, isLoopback)
            }

            ptr = cur.pointee.ifa_next
        }

        var result: [CaptureInterface] = []
        for (name, meta) in interfaces {
            let isWireless = name.hasPrefix("en") && (name == "en0" || name == "awdl0" || name == "ap1")
            let label: String
            if meta.isLoopback {
                label = "\(name) (Loopback)"
            } else if let ip = meta.ip {
                label = "\(name) (\(isWireless ? "Wi-Fi" : "Interface") • \(ip))"
            } else {
                label = "\(name) (\(isWireless ? "Wi-Fi" : "Interface"))"
            }

            result.append(CaptureInterface(
                name: name,
                displayName: label,
                ipAddress: meta.ip,
                isUp: meta.isUp,
                isRunning: meta.isRunning,
                isWireless: isWireless,
                isLoopback: meta.isLoopback
            ))
        }

        // Sort prioritizing en0, loopback, then active IPs
        result.sort { a, b in
            if a.name == "en0" { return true }
            if b.name == "en0" { return false }
            if a.ipAddress != nil && b.ipAddress == nil { return true }
            if a.ipAddress == nil && b.ipAddress != nil { return false }
            return a.name < b.name
        }

        return result.isEmpty ? fallbackInterfaces() : result
    }

    private static func fallbackInterfaces() -> [CaptureInterface] {
        [
            CaptureInterface(name: "en0", displayName: "en0 (Wi-Fi)", ipAddress: "192.168.1.100", isUp: true, isRunning: true, isWireless: true),
            CaptureInterface(name: "lo0", displayName: "lo0 (Loopback)", ipAddress: "127.0.0.1", isUp: true, isRunning: true, isLoopback: true)
        ]
    }

    /// Tests if /dev/bpf0 is readable without root or if elevation is needed.
    public static func checkBPFAccess() -> BPFAccessStatus {
        let fd = open("/dev/bpf0", O_RDONLY)
        if fd >= 0 {
            close(fd)
            return .accessible
        }
        let err = errno
        if err == EACCES || err == EPERM {
            return .requiresElevation(reason: "macOS requires root or BPF group access (/dev/bpf* permissions).")
        }
        return .unsupported
    }
}

// MARK: - Live Capture Session

@Observable
public final class LiveCaptureSession: @unchecked Sendable {

    public enum CaptureStatus: Equatable, Sendable {
        case idle
        case starting
        case capturing
        case paused
        case stopped
        case error(String)
    }

    public var status: CaptureStatus = .idle
    public var selectedInterface: String = "en0"
    public var bpfFilter: String = ""
    public var maxBufferSize: Int = 2000

    public var packets: [PacketRecord] = []
    public var summary: PacketCaptureSummary? = nil

    // Telemetry
    public var packetRate: Double = 0.0
    public var bitrateMbps: Double = 0.0
    public var totalPacketsCaptured: Int = 0
    public var totalBytesCaptured: Int = 0
    public var anomalyCount: Int = 0

    // Internal State
    private var process: Process? = nil
    private var simulationTask: Task<Void, Never>? = nil
    private var telemetryTimer: Task<Void, Never>? = nil

    private var rawPCAPBuffer = Data()
    private var incomingChunkBuffer = Data()
    private var headerParsed = false
    private var isSwapped = false
    private var isNano = false

    private let lock = NSLock()
    private let anomalyDetector = TCPAnomalyDetector()
    private let flowTracker = FlowTracker()

    private var rateWindowPackets: Int = 0
    private var rateWindowBytes: Int = 0
    private var firstPacketTimestamp: Date? = nil
    private var lastPacketTimestamp: Date? = nil

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Live Capture Execution

    public func startLiveCapture(interface: String, filter: String = "") {
        stop()

        lock.lock()
        self.status = .starting
        self.selectedInterface = interface
        self.bpfFilter = filter
        self.packets.removeAll()
        self.rawPCAPBuffer = Data()
        self.incomingChunkBuffer = Data()
        self.headerParsed = false
        self.totalPacketsCaptured = 0
        self.totalBytesCaptured = 0
        self.anomalyCount = 0
        self.rateWindowPackets = 0
        self.rateWindowBytes = 0
        self.firstPacketTimestamp = nil
        self.lastPacketTimestamp = nil
        lock.unlock()

        startTelemetryTimer()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")

        var arguments = ["-s", "65535", "-U", "-w", "-", "-i", interface]
        let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFilter.isEmpty {
            arguments.append(trimmedFilter)
        }
        p.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.consumeChunk(chunk)
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .capturing = self.status {
                    if proc.terminationStatus != 0 {
                        let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                        let errStr = String(data: errData, encoding: .utf8) ?? "tcpdump exited with code \(proc.terminationStatus)"
                        self.status = .error(errStr.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        self.status = .stopped
                    }
                }
            }
        }

        do {
            try p.run()
            self.process = p
            DispatchQueue.main.async {
                self.status = .capturing
            }
        } catch {
            DispatchQueue.main.async {
                self.status = .error("Failed to start tcpdump: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Simulated Stream (Zero-Privilege Live Mode)

    public func startSimulation(packetsPerSecond: Double = 12.0) {
        stop()

        lock.lock()
        self.status = .starting
        self.selectedInterface = "en0 (Simulated)"
        self.bpfFilter = ""
        self.packets.removeAll()
        self.rawPCAPBuffer = Data()
        self.incomingChunkBuffer = Data()
        self.headerParsed = false
        self.totalPacketsCaptured = 0
        self.totalBytesCaptured = 0
        self.anomalyCount = 0
        self.rateWindowPackets = 0
        self.rateWindowBytes = 0
        self.firstPacketTimestamp = nil
        self.lastPacketTimestamp = nil
        lock.unlock()

        startTelemetryTimer()

        // Write synthetic PCAP header to chunk buffer
        var header = Data()
        var magic: UInt32 = 0xa1b2c3d4
        var verMaj: UInt16 = 2
        var verMin: UInt16 = 4
        var thiszone: UInt32 = 0
        var sigfigs: UInt32 = 0
        var snaplen: UInt32 = 65535
        var linktype: UInt32 = 1 // Ethernet
        withUnsafeBytes(of: &magic) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &verMaj) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &verMin) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &thiszone) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &sigfigs) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &snaplen) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &linktype) { header.append(contentsOf: $0) }
        consumeChunk(header)

        DispatchQueue.main.async {
            self.status = .capturing
        }

        let delayNanos = UInt64(1_000_000_000.0 / max(1.0, packetsPerSecond))
        self.simulationTask = Task.detached { [weak self] in
            var simStep = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: delayNanos)
                guard let self = self else { break }
                let frame = self.generateSimulatedFrame(step: simStep)
                let packetBytes = self.encodePCAPPacket(frame: frame)
                self.consumeChunk(packetBytes)
                simStep += 1
            }
        }
    }

    // MARK: - Chunk Consumer & Streaming Slicer

    public func consumeChunk(_ chunk: Data) {
        lock.lock()
        incomingChunkBuffer.append(chunk)

        // 1. Process 24-byte PCAP Global Header if not parsed
        if !headerParsed {
            guard incomingChunkBuffer.count >= 24 else {
                lock.unlock()
                return
            }

            let rawMagic = incomingChunkBuffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
            switch rawMagic {
            case 0xa1b2c3d4:
                isSwapped = false
                isNano = false
            case 0xd4c3b2a1:
                isSwapped = true
                isNano = false
            case 0xa1b23c4d:
                isSwapped = false
                isNano = true
            case 0x4d3cb2a1:
                isSwapped = true
                isNano = true
            default:
                isSwapped = false
                isNano = false
            }

            rawPCAPBuffer.append(incomingChunkBuffer.prefix(24))
            incomingChunkBuffer.removeSubrange(0..<24)
            headerParsed = true
        }

        // 2. Slice complete packet headers (16 bytes) and payloads
        var newlyParsedPackets: [PacketRecord] = []

        while incomingChunkBuffer.count >= 16 {
            let u32: (Int) -> UInt32 = { offset in
                let val = self.incomingChunkBuffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
                return self.isSwapped ? val.byteSwapped : val
            }

            let tsSec = u32(0)
            let tsUsec = u32(4)
            let inclLen = Int(u32(8))
            let origLen = Int(u32(12))

            guard inclLen >= 0 && inclLen <= 65536 else {
                // Skip corrupted byte
                incomingChunkBuffer.removeFirst()
                continue
            }

            guard incomingChunkBuffer.count >= 16 + inclLen else {
                // Awaiting remaining payload bytes in next chunk
                break
            }

            let packetData = incomingChunkBuffer.subdata(in: 16..<(16 + inclLen))
            rawPCAPBuffer.append(incomingChunkBuffer.prefix(16 + inclLen))
            incomingChunkBuffer.removeSubrange(0..<(16 + inclLen))

            let timeDivisor = isNano ? 1_000_000_000.0 : 1_000_000.0
            let timestamp = Date(timeIntervalSince1970: TimeInterval(tsSec) + (Double(tsUsec) / timeDivisor))

            if firstPacketTimestamp == nil {
                firstPacketTimestamp = timestamp
            }
            lastPacketTimestamp = timestamp
            let relativeTime = max(0, timestamp.timeIntervalSince(firstPacketTimestamp ?? timestamp))

            totalPacketsCaptured += 1
            totalBytesCaptured += inclLen
            rateWindowPackets += 1
            rateWindowBytes += inclLen

            let packetNum = totalPacketsCaptured
            let dissected = ProtocolDissector.dissect(
                packetData: packetData,
                packetNumber: packetNum,
                wireLength: origLen > 0 ? origLen : inclLen
            )

            var anomalies: [TCPAnomaly] = []
            if let flags = dissected.tcpFlags,
               let seq = dissected.tcpSeq,
               let ack = dissected.tcpAck,
               let win = dissected.tcpWindow,
               let sp = dissected.sourcePort,
               let dp = dissected.destinationPort {
                anomalies = anomalyDetector.analyze(
                    packetNumber: packetNum,
                    timestamp: timestamp,
                    sourceIP: dissected.sourceAddress,
                    destIP: dissected.destinationAddress,
                    sourcePort: sp,
                    destPort: dp,
                    tcpFlags: flags,
                    seq: seq,
                    ack: ack,
                    window: win,
                    payloadLength: dissected.payloadLength
                )
            }

            if !anomalies.isEmpty {
                anomalyCount += anomalies.count
            }

            let record = PacketRecord(
                id: UUID(),
                number: packetNum,
                timestamp: timestamp,
                relativeTime: relativeTime,
                sourceAddress: dissected.sourceAddress,
                destinationAddress: dissected.destinationAddress,
                sourcePort: dissected.sourcePort,
                destinationPort: dissected.destinationPort,
                protocolType: dissected.protocolType,
                wireLength: origLen > 0 ? origLen : inclLen,
                capturedLength: inclLen,
                summary: dissected.summary,
                tcpFlags: dissected.tcpFlags,
                tcpSeq: dissected.tcpSeq,
                tcpAck: dissected.tcpAck,
                tcpWindow: dissected.tcpWindow,
                anomalies: anomalies,
                layers: dissected.layers,
                rawBytes: packetData
            )

            flowTracker.record(packet: record)
            newlyParsedPackets.append(record)
        }

        // Apply ring-buffer eviction if necessary
        var updatedPackets = self.packets
        updatedPackets.append(contentsOf: newlyParsedPackets)
        if updatedPackets.count > maxBufferSize {
            let overflow = updatedPackets.count - maxBufferSize
            updatedPackets.removeFirst(overflow)
        }
        self.packets = updatedPackets

        lock.unlock()
    }

    // MARK: - State Control

    public func pause() {
        if case .capturing = status {
            status = .paused
        }
    }

    public func resume() {
        if case .paused = status {
            status = .capturing
        }
    }

    public func stop() {
        process?.terminate()
        process = nil
        simulationTask?.cancel()
        simulationTask = nil
        telemetryTimer?.cancel()
        telemetryTimer = nil
        if case .capturing = status {
            status = .stopped
        }
        recomputeSummary()
    }

    public func clear() {
        lock.lock()
        packets.removeAll()
        rawPCAPBuffer = Data()
        incomingChunkBuffer = Data()
        headerParsed = false
        totalPacketsCaptured = 0
        totalBytesCaptured = 0
        anomalyCount = 0
        rateWindowPackets = 0
        rateWindowBytes = 0
        packetRate = 0.0
        bitrateMbps = 0.0
        firstPacketTimestamp = nil
        lastPacketTimestamp = nil
        summary = nil
        lock.unlock()
    }

    // MARK: - Export PCAP Buffer

    public func exportCurrentBufferAsPCAP() -> Data {
        lock.lock()
        defer { lock.unlock() }

        if rawPCAPBuffer.count >= 24 {
            return rawPCAPBuffer
        }

        // Reconstruct valid PCAP from current packets if buffer was reconstructed
        var data = Data()
        var magic: UInt32 = 0xa1b2c3d4
        var verMaj: UInt16 = 2
        var verMin: UInt16 = 4
        var thiszone: UInt32 = 0
        var sigfigs: UInt32 = 0
        var snaplen: UInt32 = 65535
        var linktype: UInt32 = 1 // Ethernet
        withUnsafeBytes(of: &magic) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &verMaj) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &verMin) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &thiszone) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &sigfigs) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &snaplen) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &linktype) { data.append(contentsOf: $0) }

        for p in packets {
            let sec = UInt32(p.timestamp.timeIntervalSince1970)
            let usec = UInt32((p.timestamp.timeIntervalSince1970 - Double(sec)) * 1_000_000)
            var s = sec
            var u = usec
            var capLen = UInt32(p.rawBytes.count)
            var origLen = UInt32(p.wireLength)
            withUnsafeBytes(of: &s) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &u) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &capLen) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &origLen) { data.append(contentsOf: $0) }
            data.append(p.rawBytes)
        }

        return data
    }

    // MARK: - Telemetry & Summary Updates

    private func startTelemetryTimer() {
        telemetryTimer?.cancel()
        telemetryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 2 Hz updates
                guard let self = self else { break }
                self.updateTelemetry()
            }
        }
    }

    private func updateTelemetry() {
        lock.lock()
        let pkts = rateWindowPackets
        let bytes = rateWindowBytes
        rateWindowPackets = 0
        rateWindowBytes = 0
        lock.unlock()

        let rate = Double(pkts) * 2.0 // 500ms window -> * 2
        let mbps = (Double(bytes * 8) / 1_000_000.0) * 2.0

        DispatchQueue.main.async {
            self.packetRate = rate
            self.bitrateMbps = mbps
            self.recomputeSummary()
        }
    }

    private func recomputeSummary() {
        lock.lock()
        let totalP = self.totalPacketsCaptured
        let totalB = self.totalBytesCaptured
        let currentPkts = self.packets
        let firstT = self.firstPacketTimestamp
        let lastT = self.lastPacketTimestamp ?? Date()
        let duration = max(0.1, (lastT.timeIntervalSince(firstT ?? lastT)))
        let bitrate = (Double(totalB * 8) / 1_000_000.0) / duration
        let protoDist = self.flowTracker.buildProtocolDistribution()
        let talkers = self.flowTracker.buildTopTalkers()
        let flows = self.flowTracker.buildFlows()
        lock.unlock()

        var anomalyEvents: [AnomalyEvent] = []
        for p in currentPkts {
            for a in p.anomalies {
                anomalyEvents.append(AnomalyEvent(
                    id: UUID(),
                    packetNumber: p.number,
                    relativeTime: p.relativeTime,
                    source: "\(p.sourceAddress)\(p.sourcePort != nil ? ":\(p.sourcePort!)" : "")",
                    destination: "\(p.destinationAddress)\(p.destinationPort != nil ? ":\(p.destinationPort!)" : "")",
                    anomaly: a,
                    severity: .warning,
                    description: a.title
                ))
            }
        }

        self.summary = PacketCaptureSummary(
            fileName: "live_capture_\(selectedInterface).pcap",
            formatName: "Live Capture (Streaming PCAP)",
            totalPackets: totalP,
            totalBytes: totalB,
            duration: duration,
            startTime: firstT,
            endTime: lastT,
            averageBitrateMbps: bitrate,
            protocolDistribution: protoDist,
            topTalkers: talkers,
            flows: flows,
            anomalies: anomalyEvents,
            packets: currentPkts
        )
    }

    // MARK: - Simulation Frame Encoding

    private func encodePCAPPacket(frame: Data) -> Data {
        var data = Data()
        let now = Date()
        var sec = UInt32(now.timeIntervalSince1970)
        var usec = UInt32((now.timeIntervalSince1970 - Double(sec)) * 1_000_000)
        var capLen = UInt32(frame.count)
        var origLen = UInt32(frame.count)
        withUnsafeBytes(of: &sec) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &usec) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &capLen) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &origLen) { data.append(contentsOf: $0) }
        data.append(frame)
        return data
    }

    private func generateSimulatedFrame(step: Int) -> Data {
        var p = Data()
        let macHost: [UInt8] = [0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E]
        let macGw: [UInt8] = [0x00, 0x50, 0x56, 0xC0, 0x00, 0x01]

        let mod = step % 8
        switch mod {
        case 0:
            // DNS Query (A api.nexwave.net)
            p.append(contentsOf: macGw)
            p.append(contentsOf: macHost)
            appendUInt16BE(&p, 0x0800)
            appendIPv4Header(&p, src: [192, 168, 1, 100], dst: [1, 1, 1, 1], proto: 17, payloadLen: 34)
            appendUDPHeader(&p, srcPort: 53142, dstPort: 53, len: 34)
            // DNS Header + Q
            appendUInt16BE(&p, 0x1234)
            appendUInt16BE(&p, 0x0100) // Standard query
            appendUInt16BE(&p, 1) // QDCOUNT
            appendUInt16BE(&p, 0)
            appendUInt16BE(&p, 0)
            appendUInt16BE(&p, 0)
            p.append(contentsOf: [3, 97, 112, 105, 7, 110, 101, 120, 119, 97, 118, 101, 3, 110, 101, 116, 0])
            appendUInt16BE(&p, 1) // Type A
            appendUInt16BE(&p, 1) // Class IN

        case 1:
            // DNS Response
            p.append(contentsOf: macHost)
            p.append(contentsOf: macGw)
            appendUInt16BE(&p, 0x0800)
            appendIPv4Header(&p, src: [1, 1, 1, 1], dst: [192, 168, 1, 100], proto: 17, payloadLen: 50)
            appendUDPHeader(&p, srcPort: 53, dstPort: 53142, len: 50)
            appendUInt16BE(&p, 0x1234)
            appendUInt16BE(&p, 0x8180) // Response
            appendUInt16BE(&p, 1)
            appendUInt16BE(&p, 1) // ANCOUNT
            appendUInt16BE(&p, 0)
            appendUInt16BE(&p, 0)
            p.append(contentsOf: [3, 97, 112, 105, 7, 110, 101, 120, 119, 97, 118, 101, 3, 110, 101, 116, 0])
            appendUInt16BE(&p, 1)
            appendUInt16BE(&p, 1)
            // Answer: IP 104.21.48.12
            appendUInt16BE(&p, 0xC00C) // Pointer
            appendUInt16BE(&p, 1)
            appendUInt16BE(&p, 1)
            appendUInt32BE(&p, 300) // TTL
            appendUInt16BE(&p, 4)   // Len
            p.append(contentsOf: [104, 21, 48, 12])

        case 2:
            // TCP SYN
            p.append(contentsOf: macGw)
            p.append(contentsOf: macHost)
            appendUInt16BE(&p, 0x0800)
            appendIPv4Header(&p, src: [192, 168, 1, 100], dst: [104, 21, 48, 12], proto: 6, payloadLen: 20)
            appendTCPHeader(&p, srcPort: 49152, dstPort: 443, seq: 1000, ack: 0, flags: 0x02, win: 65535)

        case 3:
            // TCP SYN-ACK
            p.append(contentsOf: macHost)
            p.append(contentsOf: macGw)
            appendUInt16BE(&p, 0x0800)
            appendIPv4Header(&p, src: [104, 21, 48, 12], dst: [192, 168, 1, 100], proto: 6, payloadLen: 20)
            appendTCPHeader(&p, srcPort: 443, dstPort: 49152, seq: 5000, ack: 1001, flags: 0x12, win: 65535)

        case 4:
            // TLS Client Hello
            p.append(contentsOf: macGw)
            p.append(contentsOf: macHost)
            appendUInt16BE(&p, 0x0800)
            let tlsPayload = Data([0x16, 0x03, 0x03, 0x00, 0x20] + [UInt8](repeating: 0xAA, count: 32))
            appendIPv4Header(&p, src: [192, 168, 1, 100], dst: [104, 21, 48, 12], proto: 6, payloadLen: 20 + tlsPayload.count)
            appendTCPHeader(&p, srcPort: 49152, dstPort: 443, seq: 1001, ack: 5001, flags: 0x18, win: 65535)
            p.append(tlsPayload)

        case 5:
            // Simulated Anomaly: TCP Zero Window buffer stall
            p.append(contentsOf: macHost)
            p.append(contentsOf: macGw)
            appendUInt16BE(&p, 0x0800)
            appendIPv4Header(&p, src: [104, 21, 48, 12], dst: [192, 168, 1, 100], proto: 6, payloadLen: 20)
            appendTCPHeader(&p, srcPort: 443, dstPort: 49152, seq: 5001, ack: 1038, flags: 0x10, win: 0) // Win = 0!

        case 6:
            // Simulated Anomaly: TCP Retransmission
            p.append(contentsOf: macGw)
            p.append(contentsOf: macHost)
            appendUInt16BE(&p, 0x0800)
            let retryPayload = Data([0x16, 0x03, 0x03, 0x00, 0x20] + [UInt8](repeating: 0xAA, count: 32))
            appendIPv4Header(&p, src: [192, 168, 1, 100], dst: [104, 21, 48, 12], proto: 6, payloadLen: 20 + retryPayload.count)
            appendTCPHeader(&p, srcPort: 49152, dstPort: 443, seq: 1001, ack: 5001, flags: 0x18, win: 65535)
            p.append(retryPayload)

        default:
            // ICMP Ping Echo Reply
            p.append(contentsOf: macHost)
            p.append(contentsOf: macGw)
            appendUInt16BE(&p, 0x0800)
            appendIPv4Header(&p, src: [1, 1, 1, 1], dst: [192, 168, 1, 100], proto: 1, payloadLen: 32)
            p.append(contentsOf: [0, 0, 0x5B, 0x76, 0x12, 0x34, 0x00, 0x01] + [UInt8](repeating: 0x41, count: 24))
        }

        return p
    }

    private func appendUInt16BE(_ d: inout Data, _ val: UInt16) {
        var v = val.bigEndian
        withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
    }

    private func appendUInt32BE(_ d: inout Data, _ val: UInt32) {
        var v = val.bigEndian
        withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
    }

    private func appendIPv4Header(_ d: inout Data, src: [UInt8], dst: [UInt8], proto: UInt8, payloadLen: Int) {
        d.append(0x45) // Version 4, IHL 5
        d.append(0x00) // DSCP/ECN
        appendUInt16BE(&d, UInt16(20 + payloadLen))
        appendUInt16BE(&d, 0x4A21)
        appendUInt16BE(&d, 0x4000) // Don't fragment
        d.append(64)   // TTL
        d.append(proto)
        appendUInt16BE(&d, 0x0000) // Checksum
        d.append(contentsOf: src)
        d.append(contentsOf: dst)
    }

    private func appendUDPHeader(_ d: inout Data, srcPort: UInt16, dstPort: UInt16, len: UInt16) {
        appendUInt16BE(&d, srcPort)
        appendUInt16BE(&d, dstPort)
        appendUInt16BE(&d, 8 + len)
        appendUInt16BE(&d, 0x0000)
    }

    private func appendTCPHeader(_ d: inout Data, srcPort: UInt16, dstPort: UInt16, seq: UInt32, ack: UInt32, flags: UInt8, win: UInt16) {
        appendUInt16BE(&d, srcPort)
        appendUInt16BE(&d, dstPort)
        appendUInt32BE(&d, seq)
        appendUInt32BE(&d, ack)
        d.append(0x50) // Data offset 5
        d.append(flags)
        appendUInt16BE(&d, win)
        appendUInt16BE(&d, 0x0000) // Checksum
        appendUInt16BE(&d, 0x0000) // Urgent pointer
    }
}
