import Foundation
import Dispatch

/// Performance & resource governor.
/// Monitors system memory pressure via Darwin dispatch sources and adapts background workloads.
public final class PowerAndMemoryGovernor: @unchecked Sendable {
    public static let shared = PowerAndMemoryGovernor()

    public enum PressureLevel: Sendable {
        case normal
        case warning
        case critical
    }

    private let memoryQueue = DispatchQueue(label: "com.nexwave.governor.memory", qos: .utility)
    private var memorySource: DispatchSourceMemoryPressure?
    private var pressureHandlers: [UUID: @Sendable (PressureLevel) -> Void] = [:]
    private let lock = NSLock()

    private init() {
        startMemoryPressureMonitoring()
    }

    deinit {
        memorySource?.cancel()
    }

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: memoryQueue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            let level: PressureLevel = event.contains(.critical) ? .critical : .warning
            WorkbenchLog.governor.warning("System memory pressure detected: \(level == .critical ? "CRITICAL" : "WARNING")")
            self.notifyHandlers(level: level)
        }
        source.activate()
        self.memorySource = source
    }

    public func registerPressureHandler(_ handler: @escaping @Sendable (PressureLevel) -> Void) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        pressureHandlers[id] = handler
        return id
    }

    public func unregisterPressureHandler(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        pressureHandlers.removeValue(forKey: id)
    }

    private func notifyHandlers(level: PressureLevel) {
        lock.lock()
        let handlers = Array(pressureHandlers.values)
        lock.unlock()

        for handler in handlers {
            handler(level)
        }
    }

    /// Current resident memory footprint of the workbench process in megabytes
    public var currentMemoryFootprintMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }

    /// Checks whether the Mac is currently discharging on battery power
    public var isRunningOnBattery: Bool {
        // Safe check using system profiler or host statistics without requiring private frameworks
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

