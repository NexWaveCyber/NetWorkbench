# ADR 0004: Packet Workbench Strategy — Native Streaming Summaries + Wireshark Integration

## Status
Accepted

## Context
Network engineers need quick visibility into PCAP/PCAPNG capture files (top talkers, flow breakdowns, TCP retransmissions, DNS anomalies) without waiting 30 seconds for heavy tools like Wireshark to launch. However, attempting to replicate Wireshark's thousands of protocol dissectors in NexWave would be an architectural anti-pattern and a massive distraction from the core product mission.

Furthermore, bundling `tshark` inside NexWave is prohibited due to:
1. **GPLv2 License**: Wireshark/tshark is GPLv2, which contaminates commercial distribution.
2. **Binary Bloat**: Bundling tshark and its dynamic libraries adds >120MB to the application bundle.

## Decision
1. **Pure Swift Streaming PCAP/PCAPNG Summary Engine (`PacketKit`)**:
   * Uses memory-mapped I/O (`Data(contentsOf: options: .alwaysMapped)`) to stream multi-gigabyte captures with bounded, constant RAM footprint.
   * Parses standard headers: Section Header Block, Interface Description Block, Enhanced Packet Block, Ethernet II, IPv4/IPv6, TCP, UDP, DNS, and TLS ClientHello/ServerHello.
   * Extracts conversational flows, IP conversations, TCP flags (SYN, ACK, RST, FIN), retransmissions, zero-window events, and DNS failure rates.
2. **"Open in Wireshark" Integration Bridge**:
   * For deep, byte-level packet dissection, NexWave provides a prominent "Open in Wireshark" button that locates the local system installation (`/Applications/Wireshark.app`) and opens the file seamlessly via `NSWorkspace.shared.open()`.
3. **Explicit Positioning**:
   * NexWave positions Packet Workbench as an **executive summary and anomaly triage tool**, never a Wireshark replacement.

## Consequences
* Blazing fast capture analysis (summary generated in < 2 seconds for a 500MB capture).
* Zero GPL licensing liability.
* Preserves engineering focus on high-level troubleshooting and investigation workflows.
