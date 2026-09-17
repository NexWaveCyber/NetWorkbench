import Foundation

/// Embedded SSH Key Management and Generation Studio (MobaKeyGen equivalent)
/// Discovers existing local keypairs in `~/.ssh/`, generates modern Ed25519 & RSA-4096 keys,
/// exports public keys, and handles remote key deployment to servers.
public final class SSHKeyStudio: @unchecked Sendable {
    public static let shared = SSHKeyStudio()

    public init() {}

    private var sshDirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
    }

    /// Discovers all SSH public/private keypairs stored in `~/.ssh/`
    public func discoverLocalKeys() -> [SSHKeyInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sshDirURL.path) else {
            return []
        }

        var keys: [SSHKeyInfo] = []
        let pubFiles = files.filter { $0.hasSuffix(".pub") }

        for pubFile in pubFiles {
            let pubURL = sshDirURL.appendingPathComponent(pubFile)
            let privName = String(pubFile.dropLast(4)) // Remove .pub
            let privURL = sshDirURL.appendingPathComponent(privName)

            let pubContent = (try? String(contentsOf: pubURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !pubContent.isEmpty else { continue }

            // Extract key type and comment from public key string
            // Format: [algorithm] [base64_key] [optional comment]
            let parts = pubContent.components(separatedBy: " ")
            let algo = parts.first ?? ""
            let comment = parts.count >= 3 ? parts.dropFirst(2).joined(separator: " ") : ""

            let keyType: String
            if algo.contains("ed25519") {
                keyType = "Ed25519"
            } else if algo.contains("rsa") {
                keyType = "RSA"
            } else if algo.contains("ecdsa") {
                keyType = "ECDSA"
            } else {
                keyType = algo
            }

            // Get fingerprint using ssh-keygen -lf
            let fingerprint = getFingerprint(for: pubURL.path)

            keys.append(SSHKeyInfo(
                name: privName,
                privateKeyPath: privURL.path,
                publicKeyPath: pubURL.path,
                keyType: keyType,
                fingerprint: fingerprint,
                comment: comment,
                publicKeyString: pubContent
            ))
        }

        return keys.sorted { $0.name < $1.name }
    }

    /// Generate modern, ultra-secure Ed25519 keypair with optional passphrase
    @discardableResult
    public func generateEd25519Key(
        filename: String = "id_ed25519",
        passphrase: String = "",
        comment: String = "nexwave@mac",
        overwrite: Bool = false
    ) throws -> SSHKeyInfo {
        let privURL = sshDirURL.appendingPathComponent(filename)
        let pubURL = sshDirURL.appendingPathComponent("\(filename).pub")
        let fm = FileManager.default

        // Create ~/.ssh directory if not exists
        if !fm.fileExists(atPath: sshDirURL.path) {
            try fm.createDirectory(at: sshDirURL, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        if fm.fileExists(atPath: privURL.path) && !overwrite {
            throw NSError(domain: "SSHKeyStudio", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "Key '\(filename)' already exists in ~/.ssh/. Choose a different name or enable overwrite."
            ])
        }

        if overwrite {
            try? fm.removeItem(at: privURL)
            try? fm.removeItem(at: pubURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = [
            "-t", "ed25519",
            "-f", privURL.path,
            "-N", passphrase,
            "-C", comment
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown ssh-keygen error"
            throw NSError(domain: "SSHKeyStudio", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Failed to generate Ed25519 key: \(errMsg)"
            ])
        }

        // Enforce strict POSIX permissions (0600 private, 0644 public)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privURL.path)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pubURL.path)

        let pubContent = (try? String(contentsOf: pubURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fingerprint = getFingerprint(for: pubURL.path)

        return SSHKeyInfo(
            name: filename,
            privateKeyPath: privURL.path,
            publicKeyPath: pubURL.path,
            keyType: "Ed25519",
            fingerprint: fingerprint,
            comment: comment,
            publicKeyString: pubContent
        )
    }

    /// Generate enterprise RSA 4096-bit keypair with optional passphrase
    @discardableResult
    public func generateRSAKey(
        filename: String = "id_rsa",
        bits: Int = 4096,
        passphrase: String = "",
        comment: String = "nexwave@mac",
        overwrite: Bool = false
    ) throws -> SSHKeyInfo {
        let privURL = sshDirURL.appendingPathComponent(filename)
        let pubURL = sshDirURL.appendingPathComponent("\(filename).pub")
        let fm = FileManager.default

        if !fm.fileExists(atPath: sshDirURL.path) {
            try fm.createDirectory(at: sshDirURL, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        if fm.fileExists(atPath: privURL.path) && !overwrite {
            throw NSError(domain: "SSHKeyStudio", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "Key '\(filename)' already exists in ~/.ssh/. Choose a different name or enable overwrite."
            ])
        }

        if overwrite {
            try? fm.removeItem(at: privURL)
            try? fm.removeItem(at: pubURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = [
            "-t", "rsa",
            "-b", "\(bits)",
            "-f", privURL.path,
            "-N", passphrase,
            "-C", comment
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown ssh-keygen error"
            throw NSError(domain: "SSHKeyStudio", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Failed to generate RSA key: \(errMsg)"
            ])
        }

        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privURL.path)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pubURL.path)

        let pubContent = (try? String(contentsOf: pubURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fingerprint = getFingerprint(for: pubURL.path)

        return SSHKeyInfo(
            name: filename,
            privateKeyPath: privURL.path,
            publicKeyPath: pubURL.path,
            keyType: "RSA",
            fingerprint: fingerprint,
            comment: comment,
            publicKeyString: pubContent
        )
    }

    /// Execute ssh-copy-id equivalent command to install the public key on remote host
    public func deployKeyToServer(
        publicKeyPath: String,
        host: String,
        port: Int = 22,
        username: String = "ubuntu"
    ) async throws -> String {
        let pubContent = (try? String(contentsOfFile: publicKeyPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pubContent.isEmpty else {
            throw NSError(domain: "SSHKeyStudio", code: 404, userInfo: [NSLocalizedDescriptionKey: "Public key file could not be read or is empty."])
        }

        // Install command: creates ~/.ssh, sets 700, appends key to authorized_keys, sets 600
        let remoteInstallCommand = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '\(pubContent)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-p", "\(port)",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(username)@\(host)",
            remoteInstallCommand
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return "Public key successfully deployed to \(username)@\(host):~/.ssh/authorized_keys"
        } else {
            throw NSError(domain: "SSHKeyStudio", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Key deployment failed (exit code \(process.terminationStatus)): \(output)"
            ])
        }
    }

    private func getFingerprint(for pubKeyPath: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-lf", pubKeyPath]

        let pipe = Pipe()
        process.standardOutput = pipe

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Output format: 256 SHA256:abc... comment (ED25519)
        let parts = raw.components(separatedBy: " ")
        if parts.count >= 2 {
            return parts[1]
        }
        return raw
    }

    // MARK: - Known Hosts Management

    /// Reads and parses all entries from ~/.ssh/known_hosts
    public func loadKnownHosts() -> [KnownHostEntry] {
        let knownHostsURL = sshDirURL.appendingPathComponent("known_hosts")
        guard let content = try? String(contentsOf: knownHostsURL, encoding: .utf8) else {
            return []
        }

        var entries: [KnownHostEntry] = []
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let hostPart = parts[0]
            let isHashed = hostPart.hasPrefix("|1|")
            let host = isHashed ? "[Hashed Host: \(hostPart.prefix(12))...]" : hostPart

            let keyType = parts.count >= 3 ? parts[1] : "unknown"
            let key = parts.count >= 3 ? parts[2] : parts[1]
            let snippet = key.count > 24 ? "\(key.prefix(12))...\(key.suffix(8))" : key

            entries.append(KnownHostEntry(
                host: host,
                keyType: keyType,
                keySnippet: snippet,
                rawLine: trimmed,
                lineNumber: index + 1,
                isHashed: isHashed
            ))
        }

        return entries
    }

    /// Removes a host from known_hosts using ssh-keygen -R to resolve host identification changed errors
    public func removeKnownHost(target: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-R", target]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Failed to remove known host"
            throw NSError(domain: "SSHKeyStudio", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errMsg
            ])
        }
    }
}
