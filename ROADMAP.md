# Engineering Roadmap (16 Weeks to V1)

> **NexWave Network Workbench**  
> Execution Milestones & Deliverables

---

## Phase 0: Foundations & Architecture (Weeks 1–2)
- [x] Comprehensive Architecture, Security, and Networking specifications
- [x] Architecture Decision Records (ADRs 0001–0006)
- [x] Swift Package Workspace configuration with Swift 6 strict concurrency
- [x] PersistenceKit: SQLite WAL database engine, schema migrations, and repositories
- [x] SecurityKit: Keychain Services wrapper and sensitive credential redactor
- [x] App shell: macOS 15 SwiftUI window navigation, Sidebar, Command Palette (`Cmd+K`)

## Phase 1: Core Networking & First Vertical Slice (Weeks 3–5)
- [x] NetworkCore: IPAddress, CIDR, TargetClassifier, Protocol primitives
- [x] PingEngine: Unprivileged ICMP prober, TCP prober, jitter/percentile calculator
- [x] DNSEngine: System DNS resolver + Do53 direct UDP query engine
- [x] TracerouteEngine: Hop discovery runner with TTL stepping
- [x] HTTPInspector: Phase timing breakdowns (DNS, TCP, TLS, TTFB)
- [x] CorrelationEngine: Deterministic multi-layer rules engine
- [x] InvestigationKit: Investigation data model, timeline event logger, evidence attachment
- [x] **Milestone 1**: End-to-End **Diagnose Host** vertical slice operational in UI.

## Phase 2: Toolbox Expansion (Weeks 6–8)
- [x] DNS Studio: Multi-resolver comparison, DoH (RFC 8484), DoT (RFC 7858), DNSSEC validation
- [x] Path Analysis: Continuous MTR-style path monitoring with jitter and hop drift
- [x] IP Studio: IPv4/IPv6 subnet calculator, VLSM planner, CIDR aggregator, wildcard mask tools
- [x] TCP / Ports: Safe port scanner, listening sockets viewer
- [x] Internet Intelligence: ASN lookup, RDAP query, BGP prefix, RPKI validation

## Phase 3: Devices & SNMP Studio (Weeks 9–11)
- [x] DeviceKit: Saved device management, credential references, tag system
- [x] Local Network Discovery: ARP/NDP table inspection, Bonjour/mDNS resolution
- [x] SNMPEngine: Pure Swift ASN.1/BER engine, SNMP v1/v2c/v3 support
- [x] SNMP Studio UI: OID Trie browser, MIB dictionary, real-time interface error rate graph

## Phase 4: Configuration & Output Intelligence (Weeks 12–14)
- [x] ConfigKit: Cisco IOS / IOS-XE / NX-OS lexical parser, syntax viewer
- [x] Structural Config Diff: Semantic interface, VLAN, ACL, and routing change detection
- [x] ACL Analyzer: Deterministic packet flow simulator (Permit/Deny, shadow detection)
- [x] ParserKit: Vendor CLI output parsers (`show ip int brief`, `show interfaces`, etc.)

## Phase 5: Packet Workbench & Release Polish (Weeks 15–16)
- [x] PacketKit: Streaming PCAP/PCAPNG parser with top talkers, flow summary, TCP anomaly detection
- [x] "Open in Wireshark" integration bridge
- [x] ReportingKit: Markdown, JSON, and PDF audit-ready evidence export
- [x] Accessibility: VoiceOver label audit, keyboard tab order, high-contrast review
- [x] **Milestone 2**: Production V1 Candidate Release.

