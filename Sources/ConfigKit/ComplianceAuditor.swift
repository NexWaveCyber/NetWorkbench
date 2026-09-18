import Foundation

/// Enterprise CIS Benchmark and DISA STIG Security Hardening Auditor for multi-vendor network configurations.
public final class ComplianceAuditor: Sendable {
    public init() {}

    /// Performs a full CIS / STIG hardening audit against the parsed AST and raw configuration text.
    public func audit(ast: ConfigAST, rawConfig: String) -> ComplianceAuditReport {
        var findings: [ComplianceFinding] = []
        let lines = rawConfig.components(separatedBy: .newlines)
        let lowerText = rawConfig.lowercased()
        let vendor = ast.vendor

        // Rule 1: Secret Encryption (CIS 1.1)
        checkPasswordEncryption(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 2: Management Plane - Secure SSH vs Unencrypted Telnet (CIS 1.2 / STIG NET-0410)
        checkTelnetAndSSH(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 3: SSH Protocol Version 2 (CIS 1.3)
        checkSSHVersion(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 4: SNMP Community String Security (CIS 2.1 / STIG NET-0620)
        checkSNMPCommunities(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 5: Interactive Session Inactivity Timeout (CIS 1.4 / STIG NET-0430)
        checkExecTimeout(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 6: AAA Framework Activation (CIS 1.5)
        checkAAAFramework(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 7: Legal Warning Banner / MOTD (CIS 1.6 / STIG NET-0440)
        checkLoginBanner(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 8: Centralized Time Synchronization (NTP) (CIS 2.2 / STIG NET-0500)
        checkNTPConfiguration(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 9: Centralized Security Auditing (Syslog) (CIS 2.3)
        checkSyslogLogging(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 10: IP Source Routing & ICMP Redirects (CIS 3.1)
        checkIPSourceRouting(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 11: Layer 2 Edge Spanning Tree Security (BPDU Guard) (CIS 4.1)
        checkBPDUGuard(ast: ast, lowerText: lowerText, lines: lines, vendor: vendor, findings: &findings)

        // Rule 12: Unused Port Hardening / Shutdown (CIS 4.2)
        checkUnusedPorts(ast: ast, findings: &findings)

        // Score Calculation (Weighted)
        let passed = findings.filter { $0.isCompliant }.count
        let failed = findings.filter { !$0.isCompliant }.count

        var earnedPoints: Double = 0
        var totalMaxPoints: Double = 0

        for finding in findings {
            let weight: Double
            switch finding.severity {
            case .critical: weight = 15.0
            case .high:     weight = 10.0
            case .medium:   weight = 6.0
            case .low:      weight = 3.0
            case .info:     weight = 1.0
            }
            totalMaxPoints += weight
            if finding.isCompliant {
                earnedPoints += weight
            }
        }

        let totalScore = totalMaxPoints > 0 ? ((earnedPoints / totalMaxPoints) * 100.0) : 100.0

        // Aggregated Remediation Script
        let failedFindings = findings.filter { !$0.isCompliant && !$0.remediationCLI.isEmpty }
        var scriptLines: [String] = [
            "# ========================================================",
            "# NEXWAVE CIS / STIG COMPLIANCE REMEDIATION PLAYBOOK",
            "# Target Device: \(ast.hostname ?? "Device") [\(vendor.rawValue)]",
            "# Generated Timestamp: \(ISO8601DateFormatter().string(from: Date()))",
            "# Total Hardening Findings: \(failed) non-compliant item(s)",
            "# ========================================================",
            ""
        ]

        if vendor == .ciscoIOS || vendor == .ciscoNXOS || vendor == .aristaEOS {
            scriptLines.append("configure terminal")
        } else if vendor == .juniperJunos {
            scriptLines.append("configure")
        } else if vendor == .huaweiVRP {
            scriptLines.append("system-view")
        }

        for finding in failedFindings {
            scriptLines.append("# [\(finding.severity.rawValue)] \(finding.ruleId): \(finding.title)")
            scriptLines.append(finding.remediationCLI)
            scriptLines.append("")
        }

        if vendor == .ciscoIOS || vendor == .aristaEOS {
            scriptLines.append("end")
            scriptLines.append("write memory")
        } else if vendor == .ciscoNXOS {
            scriptLines.append("end")
            scriptLines.append("copy running-config startup-config")
        } else if vendor == .juniperJunos {
            scriptLines.append("commit and-quit")
        } else if vendor == .huaweiVRP {
            scriptLines.append("return")
            scriptLines.append("save")
        }

        let fullScript = scriptLines.joined(separator: "\n")

        return ComplianceAuditReport(
            deviceHostname: ast.hostname,
            vendor: vendor,
            totalScore: max(0.0, min(100.0, (totalScore * 10.0).rounded() / 10.0)),
            passedRulesCount: passed,
            failedRulesCount: failed,
            findings: findings.sorted { (lhs, rhs) -> Bool in
                if lhs.isCompliant != rhs.isCompliant {
                    return !lhs.isCompliant && rhs.isCompliant
                }
                return lhs.severity > rhs.severity
            },
            fullRemediationScript: fullScript
        )
    }

    // MARK: - Audit Check Methods

    private func checkPasswordEncryption(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let isCompliant: Bool
        let affectedLines: [Int]
        let remediation: String

        switch vendor {
        case .ciscoIOS, .ciscoNXOS, .aristaEOS:
            let hasServicePW = lowerText.contains("service password-encryption")
            let hasPlainEnable = lines.enumerated().filter { $0.element.trimmingCharacters(in: .whitespaces).starts(with: "enable password") }
            isCompliant = hasServicePW && hasPlainEnable.isEmpty
            affectedLines = hasPlainEnable.map { $0.offset + 1 }
            remediation = """
            service password-encryption
            no enable password
            enable algorithm-type sha256 secret <EnterStrongAdminSecret>
            """
        case .juniperJunos:
            let hasPlainRoot = lowerText.contains("plain-text-password")
            isCompliant = !hasPlainRoot
            affectedLines = []
            remediation = "set system root-authentication encrypted-password \"<EncryptedHash>\""
        default:
            isCompliant = !lowerText.contains("password 0 ")
            affectedLines = []
            remediation = "Ensure all credentials utilize Type 8/9, SHA-512, or encrypted password stores."
        }

        findings.append(ComplianceFinding(
            ruleId: "CIS-1.1.1",
            title: "Enable Strong Password Encryption & Hashing",
            category: "Authentication",
            severity: .high,
            isCompliant: isCompliant,
            rationale: isCompliant ? "Passwords utilize reversible encryption or modern SHA hashing." : "Plaintext or legacy reversibly-encrypted passwords detected in running configuration.",
            affectedLines: affectedLines,
            remediationCLI: remediation
        ))
    }

    private func checkTelnetAndSSH(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let isCompliant: Bool
        var affectedLines: [Int] = []
        let remediation: String

        switch vendor {
        case .ciscoIOS, .aristaEOS:
            let hasTelnet = lowerText.contains("transport input telnet") || lowerText.contains("transport input all")
            let hasSSH = lowerText.contains("transport input ssh")
            isCompliant = hasSSH && !hasTelnet
            for (idx, line) in lines.enumerated() {
                if line.contains("transport input telnet") || line.contains("transport input all") {
                    affectedLines.append(idx + 1)
                }
            }
            remediation = """
            line vty 0 15
             transport input ssh
             transport output none
            """
        case .juniperJunos:
            let hasTelnet = lowerText.contains("system services telnet")
            isCompliant = !hasTelnet
            remediation = """
            delete system services telnet
            set system services ssh
            """
        default:
            isCompliant = !lowerText.contains("telnet")
            remediation = "Disable Telnet daemon on management interfaces and enforce SSHv2."
        }

        findings.append(ComplianceFinding(
            ruleId: "CIS-1.2.1",
            title: "Enforce SSHv2 and Prohibit Cleartext Telnet",
            category: "Management Plane",
            severity: .critical,
            isCompliant: isCompliant,
            rationale: isCompliant ? "Inbound management is strictly restricted to encrypted SSH." : "Cleartext Telnet access is allowed or explicitly enabled on VTY management lines.",
            affectedLines: affectedLines,
            remediationCLI: remediation
        ))
    }

    private func checkSSHVersion(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let isCompliant: Bool
        let remediation: String

        switch vendor {
        case .ciscoIOS, .aristaEOS:
            isCompliant = lowerText.contains("ip ssh version 2")
            remediation = """
            ip domain-name enterprise.internal
            crypto key generate rsa modulus 4096
            ip ssh version 2
            ip ssh time-out 60
            ip ssh authentication-retries 3
            """
        case .juniperJunos:
            isCompliant = lowerText.contains("system services ssh") && !lowerText.contains("ssh protocol-v1")
            remediation = "set system services ssh protocol-version v2"
        default:
            isCompliant = true
            remediation = "Enforce SSH protocol version 2 with minimum 2048-bit keys."
        }

        findings.append(ComplianceFinding(
            ruleId: "CIS-1.2.2",
            title: "Restrict SSH Protocol to Version 2",
            category: "Management Plane",
            severity: .high,
            isCompliant: isCompliant,
            rationale: isCompliant ? "SSHv2 is explicitly locked down, mitigating SSHv1 downgrade attacks." : "SSH version 2 is not explicitly configured, leaving fallback vulnerabilities open.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkSNMPCommunities(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        var defaultFound = false
        var affectedLines: [Int] = []

        let defaultStrings = ["public", "private", "cisco", "community1", "snmp"]
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.contains("snmp-server community") || trimmed.contains("snmp community") {
                for def in defaultStrings {
                    if trimmed.contains("community \(def)") || trimmed.contains("snmp-server community \(def)") {
                        defaultFound = true
                        affectedLines.append(idx + 1)
                    }
                }
            }
        }

        let isCompliant = !defaultFound
        let remediation = """
        no snmp-server community public
        no snmp-server community private
        snmp-server group SECURE_NMS v3 priv
        snmp-server user nms_admin SECURE_NMS v3 auth sha <AuthKey> priv aes 128 <PrivKey>
        """

        findings.append(ComplianceFinding(
            ruleId: "CIS-2.1.1",
            title: "Eliminate Default SNMP Community Strings",
            category: "Management Plane",
            severity: .critical,
            isCompliant: isCompliant,
            rationale: isCompliant ? "No common default SNMP community strings (public/private) detected." : "Default factory SNMP community strings detected, exposing device to unauthorized MIB polling and modification.",
            affectedLines: affectedLines,
            remediationCLI: remediation
        ))
    }

    private func checkExecTimeout(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let hasExecTimeout = lowerText.contains("exec-timeout")
        let hasZeroTimeout = lowerText.contains("exec-timeout 0 0") || lowerText.contains("exec-timeout 0")
        let isCompliant = hasExecTimeout && !hasZeroTimeout

        let remediation = """
        line con 0
         exec-timeout 10 0
        line vty 0 15
         exec-timeout 10 0
        """

        findings.append(ComplianceFinding(
            ruleId: "CIS-1.3.1",
            title: "Configure Interactive Session Inactivity Timeout (Exec-Timeout)",
            category: "Access Control",
            severity: .medium,
            isCompliant: isCompliant,
            rationale: isCompliant ? "Terminal line inactivity timeouts are properly configured." : "Exec timeout is missing or set to 0 (infinite), allowing orphaned privileged sessions.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkAAAFramework(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let isCompliant: Bool
        let remediation: String

        switch vendor {
        case .ciscoIOS, .ciscoNXOS:
            isCompliant = lowerText.contains("aaa new-model")
            remediation = """
            aaa new-model
            aaa authentication login default local
            aaa authorization exec default local
            """
        default:
            isCompliant = true
            remediation = "Ensure AAA authentication and accounting are enabled."
        }

        findings.append(ComplianceFinding(
            ruleId: "CIS-1.4.1",
            title: "Enable AAA Authentication and Accounting Framework",
            category: "AAA & Identity",
            severity: .high,
            isCompliant: isCompliant,
            rationale: isCompliant ? "AAA framework is active for centralized access control and accounting." : "'aaa new-model' is missing; device uses fallback per-line passwords.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkLoginBanner(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let hasBanner = lowerText.contains("banner motd") || lowerText.contains("banner login") || lowerText.contains("system login message")
        let isCompliant = hasBanner

        let remediation = """
        banner motd ^C
        ========================================================================
        AUTHORIZED ACCESS ONLY. ALL SESSIONS MONITORED AND RECORDED.
        UNAUTHORIZED ACCESS IS PROHIBITED AND SUBJECT TO PROSECUTION.
        ========================================================================
        ^C
        """

        findings.append(ComplianceFinding(
            ruleId: "CIS-1.5.1",
            title: "Establish Legal Warning Banner (MOTD / Login)",
            category: "Policy & Compliance",
            severity: .medium,
            isCompliant: isCompliant,
            rationale: isCompliant ? "Legal advisory login/MOTD banner is defined." : "No legal notice or warning banner configured for unauthorized access.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkNTPConfiguration(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let hasNTP = lowerText.contains("ntp server") || lowerText.contains("system ntp")
        let isCompliant = hasNTP

        let remediation = """
        ntp server 10.0.0.1 prefer
        ntp server 10.0.0.2
        service timestamps log datetime msec show-timezone
        service timestamps debug datetime msec show-timezone
        """

        findings.append(ComplianceFinding(
            ruleId: "CIS-2.2.1",
            title: "Centralized Network Time Protocol (NTP) Synchronization",
            category: "Auditing & Logging",
            severity: .medium,
            isCompliant: isCompliant,
            rationale: isCompliant ? "NTP synchronization servers configured for clock alignment." : "No NTP time server configured; log timestamps may desynchronize during incident triage.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkSyslogLogging(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let hasLogging = lowerText.contains("logging host") || lowerText.contains("logging server") || lowerText.contains("system syslog")
        let isCompliant = hasLogging

        let remediation = """
        logging buffered 64000 informational
        logging host 10.0.0.10 transport udp port 514
        logging trap notifications
        """

        findings.append(ComplianceFinding(
            ruleId: "CIS-2.3.1",
            title: "Centralized Remote Syslog Destination",
            category: "Auditing & Logging",
            severity: .high,
            isCompliant: isCompliant,
            rationale: isCompliant ? "Remote syslog host is defined for off-box tamper-resistant log retention." : "No centralized syslog collector configured. Event logs remain solely on volatile local ring buffers.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkIPSourceRouting(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let isCompliant: Bool
        let remediation: String

        if vendor == .ciscoIOS || vendor == .aristaEOS {
            isCompliant = lowerText.contains("no ip source-route")
            remediation = "no ip source-route"
        } else {
            isCompliant = true
            remediation = "Disable IP source routing on forwarding engines."
        }

        findings.append(ComplianceFinding(
            ruleId: "CIS-3.1.1",
            title: "Disable IP Source Routing",
            category: "Network Defense",
            severity: .medium,
            isCompliant: isCompliant,
            rationale: isCompliant ? "IP source routing is disabled, preventing packet redirection attacks." : "IP source routing is not explicitly disabled.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkBPDUGuard(ast: ConfigAST, lowerText: String, lines: [String], vendor: VendorOS, findings: inout [ComplianceFinding]) {
        let hasBPDUGuard = lowerText.contains("bpduguard enable") || lowerText.contains("spanning-tree portfast bpduguard default")
        let isCompliant = hasBPDUGuard

        let remediation = """
        spanning-tree portfast default
        spanning-tree portfast bpduguard default
        """

        findings.append(ComplianceFinding(
            ruleId: "CIS-4.1.1",
            title: "Enable STP PortFast BPDU Guard on Edge Ports",
            category: "Layer 2 Security",
            severity: .high,
            isCompliant: isCompliant,
            rationale: isCompliant ? "Spanning-tree BPDU Guard is active on edge access interfaces." : "BPDU Guard not detected; rogue switches or topology disruption attacks can trigger STP reconvergence.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }

    private func checkUnusedPorts(ast: ConfigAST, findings: inout [ComplianceFinding]) {
        let parser = ConfigParser()
        let interfaces = parser.extractInterfaces(from: ast)
        if interfaces.isEmpty { return }

        let unshutdownWithoutIP = interfaces.filter { intf in
            if intf.isShutdown { return false }
            if intf.ipAddress != nil { return false }
            if intf.accessVlan != nil { return false }
            if !intf.trunkAllowedVlans.isEmpty { return false }
            return true
        }

        let isCompliant = unshutdownWithoutIP.isEmpty
        let remediation = unshutdownWithoutIP.map {
            """
            interface \($0.name)
             description UNUSED_PORT_ISOLATED
             shutdown
            """
        }.joined(separator: "\n")

        findings.append(ComplianceFinding(
            ruleId: "CIS-4.2.1",
            title: "Shutdown Unassigned and Unused Physical Ports",
            category: "Layer 2 Security",
            severity: .low,
            isCompliant: isCompliant,
            rationale: isCompliant ? "All unconfigured interfaces are administratively shutdown." : "\(unshutdownWithoutIP.count) interface(s) are active without IP or VLAN assignment.",
            affectedLines: [],
            remediationCLI: remediation
        ))
    }
}
