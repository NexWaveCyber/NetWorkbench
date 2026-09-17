import Foundation
import AppKit

/// Generates integration links and automation triggers to launch sessions in external terminal emulators
public struct ExternalTerminalBridge: Sendable {
    public static let shared = ExternalTerminalBridge()

    public init() {}

    /// Generate an `ssh://` URL
    public func sshURL(host: String, port: Int = 22, username: String) -> URL? {
        let cleanHost = host.trimmingCharacters(in: .whitespaces)
        let cleanUser = username.trimmingCharacters(in: .whitespaces)
        let urlString = "ssh://\(cleanUser)@\(cleanHost):\(port)"
        return URL(string: urlString)
    }

    /// Generate command line string to run in an external shell
    public func sshCommand(host: String, port: Int = 22, username: String, identityFile: String? = nil) -> String {
        var cmd = "ssh"
        if port != 22 {
            cmd += " -p \(port)"
        }
        if let key = identityFile, !key.isEmpty {
            cmd += " -i \(key)"
        }
        cmd += " \(username)@\(host)"
        return cmd
    }

    /// Generate screen command for serial console
    public func serialScreenCommand(devicePath: String, baudRate: Int = 9600) -> String {
        "screen \(devicePath) \(baudRate)"
    }

    /// Generate telnet command for external shell
    public func telnetCommand(host: String, port: Int = 23) -> String {
        "telnet \(host) \(port)"
    }

    /// Open connection in macOS Terminal.app via AppleScript
    @MainActor
    public func launchInTerminalApp(command: String) {
        let scriptSource = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        if let appleScript = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
        }
    }

    /// Open connection in iTerm2 via AppleScript
    @MainActor
    public func launchInITerm2(command: String) {
        let scriptSource = """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
            end tell
        end tell
        """
        if let appleScript = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
        }
    }

    /// Check if iTerm is installed
    public var isITermInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
    }

    /// Check if Ghostty is installed
    public var isGhosttyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil
    }
}
