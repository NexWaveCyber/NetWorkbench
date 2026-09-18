import Foundation
import Network
import PersistenceKit

private final class MonitorProbeCompletion: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()
    private let connection: NWConnection
    private let continuation: CheckedContinuation<(Double?, Bool), Never>

    init(connection: NWConnection, continuation: CheckedContinuation<(Double?, Bool), Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func complete(latencyMs: Double?, isTimeout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !hasResumed {
            hasResumed = true
            connection.cancel()
            continuation.resume(returning: (latencyMs, isTimeout))
        }
    }
}

private final class ICMPProbeCompletion: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()
    private let continuation: CheckedContinuation<(String?, Bool), Never>

    init(continuation: CheckedContinuation<(String?, Bool), Never>) {
        self.continuation = continuation
    }

    func complete(output: String?, isTimeout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !hasResumed {
            hasResumed = true
            continuation.resume(returning: (output, isTimeout))
        }
    }
}

public actor BackgroundMonitorService {
    private let repository: TimeSeriesRepository
    private var targetConfigs: [UUID: MonitorTargetConfig] = [:]
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var rollingWindows: [UUID: [LatencySample]] = [:]
    private var lastAlertTime: [String: Date] = [:]
    private var onAlertTriggered: (@Sendable (SLAMonitorAlert) -> Void)?
    private var isMonitoringActive: Bool = false

    public init(repository: TimeSeriesRepository) {
        self.repository = repository
    }

    public func setOnAlertTriggered(_ handler: @escaping @Sendable (SLAMonitorAlert) -> Void) {
        self.onAlertTriggered = handler
    }

    public func updateConfigs(_ configs: [MonitorTargetConfig]) {
        self.targetConfigs = Dictionary(uniqueKeysWithValues: configs.map { ($0.id, $0) })
        if isMonitoringActive {
            syncTasks()
        }
    }

    public func addConfig(_ config: MonitorTargetConfig) {
        self.targetConfigs[config.id] = config
        if isMonitoringActive {
            syncTasks()
        }
    }

    public func removeConfig(id: UUID) {
        targetConfigs.removeValue(forKey: id)
        runningTasks[id]?.cancel()
        runningTasks.removeValue(forKey: id)
        rollingWindows.removeValue(forKey: id)
    }

    public func startAll() {
        self.isMonitoringActive = true
        syncTasks()
    }

    public func stopAll() {
        self.isMonitoringActive = false
        for (_, task) in runningTasks {
            task.cancel()
        }
        runningTasks.removeAll()
    }

    public var isActive: Bool {
        isMonitoringActive
    }

    private func syncTasks() {
        guard isMonitoringActive else { return }

        // Cancel removed tasks
        for (id, task) in runningTasks {
            if targetConfigs[id] == nil || targetConfigs[id]?.isEnabled == false {
                task.cancel()
                runningTasks.removeValue(forKey: id)
            }
        }

        // Start new or updated enabled tasks
        for (id, config) in targetConfigs {
            if config.isEnabled && runningTasks[id] == nil {
                let task = Task { [weak self] in
                    guard let self = self else { return }
                    await self.runMonitorLoop(for: config)
                }
                runningTasks[id] = task
            }
        }
    }

    private func runMonitorLoop(for config: MonitorTargetConfig) async {
        var previousLatency: Double? = nil
        var consecutiveTimeouts: Int = 0

        while !Task.isCancelled {
            let sample = await probe(config: config, previousLatency: previousLatency)
            previousLatency = sample.latencyMs

            if sample.isTimeout || sample.latencyMs == nil {
                consecutiveTimeouts += 1
            } else {
                consecutiveTimeouts = 0
            }

            // 1. Store in repository
            try? repository.insert(sample: sample)

            // 2. Update rolling buffer
            var window = rollingWindows[config.id] ?? []
            window.append(sample)
            if window.count > 10 {
                window.removeFirst(window.count - 10)
            }
            rollingWindows[config.id] = window

            // 3. Evaluate SLA thresholds
            await evaluateSLA(config: config, window: window, latestSample: sample)

            // 4. Adaptive sleep: if target has 3+ consecutive timeouts (e.g. offline workstation), back off to 8s
            let baseInterval = max(1.0, config.intervalSeconds)
            let effectiveInterval = consecutiveTimeouts >= 3 ? max(baseInterval, 8.0) : baseInterval
            let nanoseconds = UInt64(effectiveInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    private func probe(config: MonitorTargetConfig, previousLatency: Double?) async -> LatencySample {
        if config.probeProtocol == .tcp {
            return await probeTCP(host: config.target, port: config.port ?? 443, previousLatency: previousLatency)
        } else {
            return await probeICMP(target: config.target, previousLatency: previousLatency)
        }
    }

    private func probeICMP(target: String, previousLatency: Double?) async -> LatencySample {
        let clean = target.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")

        let isIPv6 = isIPv6Address(clean)

        let (output, isTimeout): (String?, Bool) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let pipe = Pipe()
                let process = Process()
                if isIPv6 {
                    process.executableURL = URL(fileURLWithPath: "/sbin/ping6")
                    process.arguments = ["-c", "1", clean]
                } else {
                    process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                    process.arguments = ["-c", "1", "-W", "800", clean]
                }
                process.standardOutput = pipe
                process.standardError = Pipe()

                let completion = ICMPProbeCompletion(continuation: continuation)

                // 1.2s safety watchdog to terminate process if ARP drops packets completely
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) {
                    if process.isRunning {
                        process.terminate()
                    }
                    completion.complete(output: nil, isTimeout: true)
                }

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        let outStr = String(data: data, encoding: .utf8)
                        completion.complete(output: outStr, isTimeout: false)
                    } else {
                        completion.complete(output: nil, isTimeout: true)
                    }
                } catch {
                    completion.complete(output: nil, isTimeout: true)
                }
            }
        }

        var latency: Double? = nil
        if let out = output, let parsed = parsePingLatency(output: out) {
            latency = parsed
        }

        var jitter: Double? = nil
        if let current = latency, let prev = previousLatency {
            jitter = abs(current - prev)
        }

        return LatencySample(
            target: target,
            timestamp: Date(),
            latencyMs: latency,
            isTimeout: isTimeout || latency == nil,
            jitterMs: jitter
        )
    }

    private func probeTCP(host: String, port: Int, previousLatency: Double?) async -> LatencySample {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return LatencySample(target: host, timestamp: Date(), latencyMs: nil, isTimeout: true)
        }
        let clean = host.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(clean), port: nwPort)
        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false

        let connection = NWConnection(to: endpoint, using: parameters)
        let startTime = DispatchTime.now()

        let (latency, isTimeout): (Double?, Bool) = await withCheckedContinuation { continuation in
            let completion = MonitorProbeCompletion(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                    completion.complete(latencyMs: elapsed, isTimeout: false)
                case .failed:
                    completion.complete(latencyMs: nil, isTimeout: true)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                completion.complete(latencyMs: nil, isTimeout: true)
            }
        }

        var jitter: Double? = nil
        if let current = latency, let prev = previousLatency {
            jitter = abs(current - prev)
        }

        return LatencySample(
            target: host,
            timestamp: Date(),
            latencyMs: latency,
            isTimeout: isTimeout,
            jitterMs: jitter
        )
    }

    private func isIPv6Address(_ host: String) -> Bool {
        if host.contains(":") { return true }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, nil, &hints, &res) == 0, let first = res {
            defer { freeaddrinfo(res) }
            return first.pointee.ai_family == AF_INET6
        }
        return false
    }

    private func evaluateSLA(config: MonitorTargetConfig, window: [LatencySample], latestSample: LatencySample) async {
        guard window.count >= 5 else { return }

        let now = Date()
        let cooldownSeconds: TimeInterval = 60.0

        // A. Packet Loss Breach Check
        let timeouts = window.filter { $0.isTimeout || $0.latencyMs == nil }.count
        let lossPct = (Double(timeouts) / Double(window.count)) * 100.0

        if lossPct >= config.packetLossThresholdPct {
            let key = "\(config.id.uuidString)_loss"
            if let last = lastAlertTime[key], now.timeIntervalSince(last) < cooldownSeconds {
                // Cooldown active
            } else {
                lastAlertTime[key] = now
                let alert = SLAMonitorAlert(
                    target: config.target,
                    targetName: config.name,
                    timestamp: now,
                    alertType: lossPct >= 80 ? .targetDown : .packetLoss,
                    measuredValue: lossPct,
                    thresholdValue: config.packetLossThresholdPct,
                    message: "Packet loss reached \(String(format: "%.1f", lossPct))% (Threshold: \(String(format: "%.1f", config.packetLossThresholdPct))%) across last \(window.count) probes."
                )
                try? repository.recordAlert(alert: alert)
                onAlertTriggered?(alert)
            }
        }

        // B. Latency Spike Check
        if let lat = latestSample.latencyMs, lat >= config.latencyThresholdMs {
            let key = "\(config.id.uuidString)_latency"
            if let last = lastAlertTime[key], now.timeIntervalSince(last) < cooldownSeconds {
                // Cooldown active
            } else {
                lastAlertTime[key] = now
                let alert = SLAMonitorAlert(
                    target: config.target,
                    targetName: config.name,
                    timestamp: now,
                    alertType: .latencySpike,
                    measuredValue: lat,
                    thresholdValue: config.latencyThresholdMs,
                    message: "Latency spiked to \(String(format: "%.1f", lat)) ms (Threshold: \(String(format: "%.1f", config.latencyThresholdMs)) ms)."
                )
                try? repository.recordAlert(alert: alert)
                onAlertTriggered?(alert)
            }
        }
    }

    private func parsePingLatency(output: String) -> Double? {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("time=") {
                let parts = line.components(separatedBy: "time=")
                if parts.count > 1 {
                    let timePart = parts[1].components(separatedBy: " ")[0]
                    return Double(timePart)
                }
            } else if line.contains("min/avg/max") {
                // e.g. round-trip min/avg/max/std-dev = 19.844/19.844/19.844/0.000 ms
                if let slashParts = line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces).components(separatedBy: "/") {
                    if slashParts.count >= 2, let avg = Double(slashParts[1]) {
                        return avg
                    }
                }
            }
        }
        return nil
    }
}
