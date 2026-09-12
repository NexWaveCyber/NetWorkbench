# Testing Strategy & Quality Assurance

> **NexWave Network Workbench**  
> Complete QA Strategy, Automated Test Matrix & Verification Reference

---

## 1. Testing Pyramid

To ensure absolute reliability for enterprise network engineering environments, NexWave adheres to a multi-tiered test strategy:

```
          / \
         / UI\        -> macOS Native Integration & MenuBar Probing
        /-----\
       / Integr\      -> SQLite WAL Persistence, DNS Engine, HTTP/TLS, PTY, Keychain
      /---------\
     / Fixtures  \    -> Real sanitized CLI outputs, PCAP headers, MIB OID Trees
    /-------------\
   /  Unit Tests   \  -> Subnet math, VLSM, CIDRs, Correlation Rules, AST Diffs, BPF
  /-----------------\
```

---

## 2. Test Suite Matrix (81 Tests across 19 Suites)

Every commit is verified against **19 automated test suites** spanning **81 tests** with a 100% pass requirement:

| Target / Suite | Tests | Key Capabilities Covered |
| :--- | :---: | :--- |
| **`NetworkCoreTests`** | 6 | IPv4/IPv6 classification, /31 & /32 subnets, VLSM partitioning, CIDR route aggregation, wildcard mask matching |
| **`DiagnosticsEngineTests`** | 2 | Multi-layer deterministic correlation engine, localhost loopback pipeline, root-cause rule evaluation |
| **`PingEngineTests`** | 2 | Percentile latency (p50/p90/p99), RFC 3550 jitter calculation, empty sample safety |
| **`DNSEngineTests`** | 2 | DNS record model, RFC 8484 DoH query wire serialization, multi-resolver race |
| **`TracerouteEngineTests`** | 2 | Hop distance discovery, target classification, timeout detection |
| **`HTTPInspectorTests`** | 2 | TLS certificate expiry, timing stage breakdown (DNS, TCP, TLS, TTFB) |
| **`InvestigationKitTests`** | 2 | Correlation engine rules, fault isolation, evidence snapshot recording |
| **`PersistenceKitTests`** | 2 | SQLite database migrations, WAL mode concurrent reads/writes, transaction safety |
| **`SecurityKitTests`** | 2 | Hardware Keychain credential storage, deterministic secret token redaction |
| **`InternetIntelTests`** | 3 | ASN formatting, RDAP origin resolution, RPKI ROA state verification |
| **`SNMPEngineTests`** | 5 | ASN.1 BER encoding/decoding (Integer, OctetString, OID, Null), SNMP v1/v2c PDU roundtrip, OID Trie lookups |
| **`ConfigKitTests`** | 4 | Cisco AST parser, structural configuration diffing, ACL simulator, shadowed rule detector |
| **`ParserKitTests`** | 7 | Real device output parsers (`show ip int br`, `show ver`, `show cdp nei`, `show mac`, `show ip route`, `show arp`, `arp -a`) |
| **`ReportingKitTests`** | 3 | Sanitized Markdown & JSON export for Device Audits, Config Diffs, and Packet Triage |
| **`WiFiKitTests`** | 5 | CoreWLAN RF metrics (RSSI, SNR, Noise), MCS index, BSSID roaming delta log, 2.4/5/6 GHz co-channel congestion |
| **`TimeSeriesKitTests`** | 4 | SQLite time-series storage, downsampling statistical buckets (10m to 7d), SLA breach threshold alerts |
| **`PacketKitTests`** | 10 | PCAP/PCAPNG header decoder, live chunk stream reassembly, 2,000-packet ring buffer, TCP anomaly detector, Wireshark bridge |
| **`DeviceKitTests`** | 6 | SQLite device inventory CRUD, baselines, 3-Tier Campus hierarchy, Spine-Leaf DC layout, Radial topology graph |
| **`TerminalKitTests`** | 5 | POSIX PTY allocation, USB serial discovery, Cisco/Arista CLI simulator, ANSI escape parsing, external terminal bridge |

---

## 3. Running Automated Tests

### Full Test Suite Run
```bash
swift test
```

### Running Specific Target Test Suites
```bash
# Wi-Fi Telemetry & RF Metrics
swift test --filter WiFiKitTests

# Long-term Time-Series & SLA Storage
swift test --filter TimeSeriesKitTests

# Live Packet Capture & BPF Streaming
swift test --filter LivePacketCaptureTests

# L2/L3 Network Topology Diagram Canvas
swift test --filter TopologyTests

# Direct Terminal & Console Session Bridge
swift test --filter TerminalTests

# Deterministic Diagnostic Correlation Rules
swift test --filter CorrelationEngineTests
```

---

## 4. Production Release Build & DMG Packaging

To build the optimized production release binary, sign ad-hoc, and package into a compressed drag-and-drop installer:

```bash
# 1. Compile & sign release application bundle
./run.sh

# 2. Build compressed Apple UDZO disk image (.dmg)
./build_dmg.sh
```

**Installer Verification**:
- Output File: `NexWave_Network_Workbench_v1.0_Candidate.dmg`
- System Target: macOS 14.0+ (Sonoma, Sequoia) on Apple Silicon & Intel
- Dependencies: 0 external libraries (100% native Darwin & Apple frameworks)
