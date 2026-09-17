import Foundation
import NetworkCore
import PingEngine

public struct DeviceBaselineSample: Sendable {
    public let avgLatencyMs: Double
    public let minLatencyMs: Double
    public let maxLatencyMs: Double
    public let jitterMs: Double
    public let packetLossPct: Double
    public let openPorts: [Int]
    public let snmpSysDescr: String?
    public let measuredAt: Date

    public init(
        avgLatencyMs: Double,
        minLatencyMs: Double,
        maxLatencyMs: Double,
        jitterMs: Double,
        packetLossPct: Double,
        openPorts: [Int],
        snmpSysDescr: String? = nil,
        measuredAt: Date = Date()
    ) {
        self.avgLatencyMs = avgLatencyMs
        self.minLatencyMs = minLatencyMs
        self.maxLatencyMs = maxLatencyMs
        self.jitterMs = jitterMs
        self.packetLossPct = packetLossPct
        self.openPorts = openPorts
        self.snmpSysDescr = snmpSysDescr
        self.measuredAt = measuredAt
    }
}

/// Active telemetry sampler and baseline drift auditor for managed fleet devices.
public actor DeviceAuditor {
    public static let standardAuditPorts: [Int] = [
        22,    // SSH
        23,    // Telnet
        53,    // DNS
        80,    // HTTP
        443,   // HTTPS
        161,   // SNMP
        179,   // BGP
        445,   // SMB
        5985,  // WinRM HTTP
        8080,  // HTTP Alt
        8443   // HTTPS Alt
    ]

    public init() {}

    /// Performs an active, honest telemetry probe against a target device IP.
    public func probeLiveBaseline(
        ipAddress: String,
        customPorts: [Int] = standardAuditPorts,
        pingCount: Int = 5,
        snmpConfig: SNMPDeviceConfig? = nil
    ) async -> DeviceBaselineSample {
        let prober = ICMPPingProber()
        var latencies: [Double] = []
        var timeouts: Int = 0

        // 1. Run Ping Train
        for _ in 0..<pingCount {
            let res = await prober.probe(host: ipAddress, timeoutSeconds: 0.8, allowTCPFallback: false)
            switch res {
            case .success(let ms):
                latencies.append(ms)
            case .timeout, .error:
                timeouts += 1
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms interval between pings
        }

        let totalAttempts = max(1, latencies.count + timeouts)
        let lossPct = (Double(timeouts) / Double(totalAttempts)) * 100.0

        let avgLat: Double
        let minLat: Double
        let maxLat: Double
        let jitter: Double

        if !latencies.isEmpty {
            avgLat = latencies.reduce(0, +) / Double(latencies.count)
            minLat = latencies.min() ?? avgLat
            maxLat = latencies.max() ?? avgLat
            var jitterSum = 0.0
            for i in 1..<latencies.count {
                jitterSum += abs(latencies[i] - latencies[i - 1])
            }
            jitter = latencies.count > 1 ? jitterSum / Double(latencies.count - 1) : 0.1
        } else {
            avgLat = 0.0
            minLat = 0.0
            maxLat = 0.0
            jitter = 0.0
        }

        // 2. Concurrently Scan Top Enterprise Ports
        let tcpProber = TCPPingProber()
        var openPorts: [Int] = []

        await withTaskGroup(of: (Int, Bool).self) { group in
            for port in customPorts {
                group.addTask {
                    let portRes = await tcpProber.probe(
                        host: ipAddress,
                        port: NetworkPort(UInt16(clamping: port)),
                        timeoutSeconds: 0.75
                    )
                    return (port, portRes.isSuccess)
                }
            }

            for await (port, isOpen) in group {
                if isOpen {
                    openPorts.append(port)
                }
            }
        }

        openPorts.sort()

        var snmpDescr: String? = nil
        if let snmp = snmpConfig {
            snmpDescr = "SNMP Agent Configured (v\(snmp.version) :\(snmp.port))"
        }

        return DeviceBaselineSample(
            avgLatencyMs: avgLat,
            minLatencyMs: minLat,
            maxLatencyMs: maxLat,
            jitterMs: jitter,
            packetLossPct: lossPct,
            openPorts: openPorts,
            snmpSysDescr: snmpDescr,
            measuredAt: Date()
        )
    }

    /// Measures live telemetry and compares against the recorded baseline to detect performance drift.
    public func auditDevice(
        device: NetworkDevice,
        baseline: DeviceBaseline,
        manager: DeviceManager
    ) async -> (sample: DeviceBaselineSample, comparison: BaselineComparisonResult) {
        let portsToCheck = Array(Set(baseline.openPorts + Self.standardAuditPorts)).sorted()
        let sample = await probeLiveBaseline(
            ipAddress: device.managementIP,
            customPorts: portsToCheck,
            pingCount: 5,
            snmpConfig: device.snmpConfig
        )

        let comparison = manager.compareWithBaseline(
            currentLatency: sample.avgLatencyMs,
            currentLoss: sample.packetLossPct,
            currentOpenPorts: sample.openPorts,
            baseline: baseline
        )

        return (sample, comparison)
    }
}
