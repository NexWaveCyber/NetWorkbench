import Foundation
import PersistenceKit

public actor BackgroundMonitorService {
    private let repository: TimeSeriesRepository
    private var targetConfigs: [UUID: MonitorTargetConfig] = [:]
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var rollingWindows: [UUID: [LatencySample]] = [:]
    private var lastAlertTime: [String: Date] = [:]

    public init(repository: TimeSeriesRepository) {
        self.repository = repository
    }

    public func updateConfigs(_ configs: [MonitorTargetConfig]) {
        self.targetConfigs = Dictionary(uniqueKeysWithValues: configs.map { ($0.id, $0) })
        syncTasks()
    }

    public func addConfig(_ config: MonitorTargetConfig) {
        self.targetConfigs[config.id] = config
        syncTasks()
    }

    public func removeConfig(id: UUID) {
        targetConfigs.removeValue(forKey: id)
        runningTasks[id]?.cancel()
        runningTasks.removeValue(forKey: id)
        rollingWindows.removeValue(forKey: id)
    }

    public func startAll() {
        syncTasks()
    }

    public func stopAll() {
        for (_, task) in runningTasks {
            task.cancel()
        }
        runningTasks.removeAll()
    }

    private func syncTasks() {
        for (id, config) in targetConfigs {
            if config.isEnabled && runningTasks[id] == nil {
                let task = Task { [weak self] in
                    guard let self = self else { return }
                    await self.runMonitorLoop(for: config)
                }
                runningTasks[id] = task
            } else if !config.isEnabled, let task = runningTasks[id] {
                task.cancel()
                runningTasks.removeValue(forKey: id)
            }
        }
    }

    private func runMonitorLoop(for config: MonitorTargetConfig) async {
        var previousLatency: Double? = nil

        while !Task.isCancelled {
            let sample = await probe(target: config.target, previousLatency: previousLatency)
            previousLatency = sample.latencyMs

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

            // 4. Sleep
            let nanoseconds = UInt64(max(1.0, config.intervalSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    private func probe(target: String, previousLatency: Double?) async -> LatencySample {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "800", target]
        process.standardOutput = pipe
        process.standardError = Pipe()

        var latency: Double? = nil
        var isTimeout = true

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if let parsed = parsePingLatency(output: output) {
                    latency = parsed
                    isTimeout = false
                }
            }
        } catch {
            isTimeout = true
        }

        var jitter: Double? = nil
        if let current = latency, let prev = previousLatency {
            jitter = abs(current - prev)
        }

        return LatencySample(
            target: target,
            timestamp: Date(),
            latencyMs: latency,
            isTimeout: isTimeout,
            jitterMs: jitter
        )
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
            }
        }
        return nil
    }
}
