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

## Primary Workspaces & Studios

1. **Home / Dashboard**: Target classification hero bar, active investigations, favorite devices, pinned tools, and live diagnostic feed.
2. **Diagnose**: 20-step automated multi-layer diagnostic pipeline with deterministic root-cause correlation and findings.
3. **Wi-Fi Studio**: Native `CoreWLAN` integration, RF health gauges (RSSI, SNR, Noise), 802.11ax/be PHY metrics, BSSID roaming delta log, and 2.4/5/6 GHz co-channel congestion visualizer.
4. **macOS Menu Bar Quick Glance Companion**: Native status bar extra with live gateway RTT badge, floating popover, dual Gateway/Internet probers, and 1-click DNS cache flusher.
5. **Timeline Monitor**: Long-term continuous time-series SLA recording, SQLite WAL downsampling (10m to 7d), PingPlotter-style GPU Canvas chart with min-max jitter envelopes, and automated SLA breach engine.
6. **Devices & Inventory**: Saved router, switch, and firewall fleet profiles with Keychain credentials, LAN neighbor discovery (ARP/NDP), and device baselines.
7. **Topology Canvas**: Interactive GPU vector diagram canvas with draggable nodes, quadratic bezier links with port labels (`Gi0/1 <--> Eth1/1`), Hierarchical 3-Tier and Radial auto-layouts, and slide-over device inspector.
8. **Terminal & Console Bridge**: Zero-dependency native POSIX PTY allocation via Darwin `openpty()`, hardware USB serial console discovery (`/dev/cu.*`, FTDI, CP210x, Cisco rollover), Cisco/Arista CLI simulator, and 1-click command macro bar.
9. **SNMP Studio**: Pure Swift SNMP v1/v2c engine, OID trie browser, MIB dictionaries, and live interface error rate polling.
10. **Config Workbench**: Syntax-aware viewer, semantic structural diff (recognizing interface, VLAN, ACL, and routing changes), and sensitive credential redactor.
11. **Packet Workbench**: Live in-app streaming PCAP chunk decoder from `/usr/sbin/tcpdump`, 2,000-packet ring buffer, BPF filter chips, TCP anomaly detector, and Wireshark bridge.
12. **Engineering Toolbox**:
    * *IP Studio*: IPv4/IPv6 subnetting, VLSM planner, CIDR aggregator, wildcard mask calculator.
    * *DNS Studio*: Multi-resolver comparison, Do53, DoH (RFC 8484), DoT, DNSSEC validation, query timing.
    * *TCP / Ports*: Safe port probe, connect timing, local socket inspection.
    * *HTTP / TLS Studio*: Timing stages (DNS, Connect, TLS, TTFB, Transfer), ALPN, certificate chain inspection.
    * *Internet Intelligence*: ASN, RDAP, BGP origin, RPKI state validation.
13. **Investigations**: Persistent troubleshooting tickets with auto-updating chronological timelines and audit export.
14. **Environments & Runbooks**: Scoped site profiles (e.g., `SFO Production DC`, `HQ Campus`, `Branch Lab`, `Cloud VPC`) with runbook notes and gateway switching.
15. **Command Library & Settings**: Verified multi-vendor CLI command reference and full local privacy / parameter tuning.

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
