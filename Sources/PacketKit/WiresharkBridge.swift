import Foundation
import AppKit

public enum WiresharkBridge {

    public static let downloadURL = URL(string: "https://www.wireshark.org/download.html")!

    public static var wiresharkAppURL: URL? {
        // 1. Check standard application bundle paths
        let standardPaths = [
            "/Applications/Wireshark.app",
            "/Applications/Utilities/Wireshark.app",
            NSHomeDirectory() + "/Applications/Wireshark.app"
        ]
        for path in standardPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 2. Query LaunchServices for bundle ID
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.wireshark.Wireshark") {
            return appURL
        }

        return nil
    }

    public static var isWiresharkInstalled: Bool {
        return wiresharkAppURL != nil
    }

    @discardableResult
    public static func openInWireshark(fileURL: URL) -> Bool {
        if let appURL = wiresharkAppURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { _, error in
                if let error = error {
                    print("Error opening capture in Wireshark: \(error.localizedDescription)")
                }
            }
            return true
        } else {
            // Fall back to opening with system default handler for .pcap
            return NSWorkspace.shared.open(fileURL)
        }
    }

    @discardableResult
    public static func openDataInWireshark(data: Data, suggestedFileName: String = "nexwave_capture.pcap") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let safeName = suggestedFileName.hasSuffix(".pcap") || suggestedFileName.hasSuffix(".pcapng")
            ? suggestedFileName
            : "\(suggestedFileName).pcap"
        let targetURL = tempDir.appendingPathComponent(safeName)

        try data.write(to: targetURL, options: .atomic)
        _ = openInWireshark(fileURL: targetURL)
        return targetURL
    }
}
