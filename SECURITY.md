# Security Architecture & Credential Management

> **NexWave Network Workbench**  
> Security Policy & Architecture

---

## 1. Zero-Root Privilege Model

Professional network tools historically relied on executing as root or installing setuid-root binaries. NexWave strictly rejects this design:
* **User-Space Execution**: NexWave runs as an unprivileged application in the user's macOS session.
* **Modern Darwin ICMP Sockets**: Latency probes and traceroute utilize Darwin's unprivileged ICMP datagram socket API (`socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`), which macOS allows for non-root processes.
* **No Arbitrary Shell Interpolation**: NexWave never invokes `/bin/sh -c "<user_input>"`. If external utilities (e.g. system `/usr/bin/ssh`) are invoked, arguments are passed as discrete token arrays directly to `Process.executableURL` with environment sanitization.

---

## 2. Credential Storage & Keychain Services

No plaintext credentials (passwords, SNMP community strings, SSH private keys, API tokens) may ever touch the filesystem or SQLite database.
* **macOS Keychain Integration**: All sensitive credentials are saved using macOS Keychain Services (`Security.framework`).
  * Class: `kSecClassGenericPassword`
  * Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  * Account: Structured UUID reference (`device:<uuid>:snmp` or `device:<uuid>:ssh`)
* **Database Representation**: The SQLite database only stores the opaque `KeychainItemReference` string.
* **Sanitized Exports & Diagnostics**: During report generation or debug bundle export, credentials and sensitive tokens are automatically stripped or masked.

---

## 3. Network & Transport Security

* **Strict TLS Validation**: HTTPS, DoH, and TLS inspection validate certificate chains against the macOS system trust store (`SecTrustEvaluateWithError`) by default.
* **Certificate Analysis**: When inspecting TLS endpoints, certificate chains are parsed to inspect Subject Alternative Names (SANs), expiration dates, issuing CAs, key sizes, and negotiated cipher suites.
* **SSH Host Key Verification**: Embedded SSH sessions strictly enforce known-host verification. If an SSH host key changes, NexWave presents an explicit security alert requiring user confirmation; host keys are never silently accepted.

---

## 4. Input Sanitization & Parser Safety

* **Memory Safety**: 100% of network packet parsing, CLI output parsing, and configuration analysis is written in pure Swift, eliminating C-style buffer overflow vulnerabilities, dangling pointers, and use-after-free bugs.
* **Regex Denial of Service (ReDoS) Defense**: All regex-based output parsers use bounded input buffers and time-limited matching algorithms.
* **Fuzz Testing**: CLI and configuration parsers are subjected to automated fuzz testing with malformed inputs to prevent crashes on edge-case vendor outputs.
