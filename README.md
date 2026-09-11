# NexWave Network Workbench

> **The native macOS workspace for network engineers.**  
> *Diagnose. Analyze. Document. Verify.*

---

## Overview

**NexWave Network Workbench** is a professional engineering workstation built natively for macOS (Apple Silicon and modern Intel Macs). Unlike basic consumer network utility widgets that provide disconnected buttons for Ping or DNS, NexWave is architected as an **IDE for network troubleshooting and assurance**.

The core philosophy of NexWave is:
> **Do not just provide tools. Help the engineer complete investigations.**

NexWave eliminates the friction of juggling Terminal tabs, online subnet calculators, unverified web tools, isolated SNMP browsers, scratchpad text files, and one-off diagnostic scripts by uniting diagnosis, path tracing, device intelligence, configuration analysis, and evidence management into a single local-first native application.

---

## Key Differentiators

* **The Investigation Abstraction**: Network problems are treated as first-class, durable investigations containing targets, automated diagnostic timelines, MTR runs, SNMP captures, device configuration diffs, ACL analysis, and verifiable resolutions.
* **Deterministic Diagnostic Correlation Engine**: Analyzes multi-layer observations (DNS, ICMP, TCP, TLS, HTTP, Path MTU) and produces actionable findings that strictly distinguish between **Observed** (measured facts), **Derived** (statistical computations), and **Inferred** (correlated fault domains).
* **Local-First & Privacy by Default**: All configurations, PCAP summaries, device credentials, and test history remain stored strictly on the local Mac. No mandatory cloud accounts or tracking.
* **Zero-Root Default Architecture**: Operates safely in user space using modern Darwin non-root ICMP sockets (`IPPROTO_ICMP`) and `Network.framework`.
* **Hardware-Backed Keychain Security**: SSH keys, SNMP community strings, and device credentials are stored exclusively in macOS Keychain Services.
* **Xcode & TablePlus Aesthetic**: Clean, high-density native SwiftUI interface supporting Dark Mode, System appearances, fast keyboard navigation (`Cmd+K` Command Palette), and split-view inspectors.

---

## Primary Workspaces

1. **Home / Dashboard**: Target classification hero bar, active investigations, favorite devices, pinned tools, and recent diagnostic feeds.
2. **Diagnose**: 20-step automated multi-layer diagnostic pipeline with deterministic correlation and findings.
3. **Toolbox**:
   * *Connectivity*: Continuous Ping, Multi-Ping, TCP Ping, jitter and percentile latency analysis.
   * *Path Analysis*: Traceroute, MTR-style continuous hop sampling, route drift detection.
   * *IP Studio*: IPv4/IPv6 subnetting, VLSM planner, CIDR aggregator, wildcard mask calculator.
   * *DNS Studio*: Multi-resolver comparison, Do53, DoH, DoT, DNSSEC validation, query timing.
   * *TCP / Ports*: Safe port probe, connect timing, local socket inspection.
   * *HTTP / TLS Studio*: Timing stages (DNS, Connect, TLS, TTFB, Transfer), ALPN, certificate chain inspection.
   * *Internet Intelligence*: ASN, RDAP, BGP origin, RPKI state validation.
4. **Devices**: Saved router, switch, and firewall profiles with Keychain credentials, interface inventories, and diagnostics.
5. **SNMP Studio**: Pure Swift SNMP v1/v2c/v3 engine, OID trie browser, MIB dictionaries, interface error rate monitoring.
6. **Config Workbench**: Syntax-aware viewer, semantic structural diff (recognizing interface, VLAN, ACL, and routing changes), and sensitive credential redactor.
7. **ACL Analyzer**: Deterministic rule simulator for Cisco-style ACLs with rule-shadowing detection.
8. **Packet Workbench**: High-speed PCAP/PCAPNG streaming summary (flow summaries, top talkers, TCP anomalies) and "Open in Wireshark" integration.
9. **Investigations**: Persistent troubleshooting tickets with auto-updating chronological timelines and audit export.
10. **Environments**: Logical scopes (e.g., `HomeLab`, `DC01-Production`, `Customer-East`).
11. **Command Library**: Verified multi-vendor CLI command reference (Cisco IOS-XE, NX-OS, Arista EOS, Juniper Junos).
12. **History & Settings**: Local audit log with configurable retention and entitlement preferences.

---

## Technology Stack

* **Platform**: macOS 15.0+ (Sequoia) & Apple Silicon optimized (Universal 2 binary support).
* **Language**: Swift 6 with strict concurrency (`Sendable`, `actor`, `TaskGroup`).
* **UI**: 100% Native SwiftUI + AppKit integration where appropriate.
* **Storage**: SQLite with Write-Ahead Logging (WAL) for relational metadata and streaming metrics; filesystem-backed storage for large PCAP/Config payloads.
* **Networking**: Apple `Network.framework`, Darwin BSD sockets, `Security.framework`.

---

## Documentation Index

* [Architecture Overview](ARCHITECTURE.md)
* [Security & Credential Model](SECURITY.md)
* [Privacy Principles](PRIVACY.md)
* [Networking Specifications & Socket Architecture](NETWORKING.md)
* [Vendor CLI Parsers](PARSERS.md)
* [Testing & Quality Assurance](TESTING.md)
* [Roadmap (12–16 Weeks)](ROADMAP.md)
* [Architecture Decision Records (ADRs)](docs/adr/)

---

## License & Copyright

Copyright © 2026 NexWave Cyber Solutions. All rights reserved.
