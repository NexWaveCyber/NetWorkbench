import Foundation
import os.log

/// Structured logging subsystem for NexWave Network Workbench using Apple's unified `os.Logger`.
///
/// Filter live in Terminal via:
/// `log stream --predicate 'subsystem == "com.nexwave.workbench"' --style compact`
public enum WorkbenchLog {
    public static let subsystem = "com.nexwave.workbench"

    public static let telemetry = Logger(subsystem: subsystem, category: "telemetry")
    public static let packetCapture = Logger(subsystem: subsystem, category: "capture")
    public static let snmp = Logger(subsystem: subsystem, category: "snmp")
    public static let terminal = Logger(subsystem: subsystem, category: "terminal")
    public static let investigations = Logger(subsystem: subsystem, category: "investigations")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let governor = Logger(subsystem: subsystem, category: "governor")
}
