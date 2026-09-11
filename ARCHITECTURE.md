# System Architecture & Technical Specifications

> **NexWave Network Workbench**  
> Technical Architecture Document

---

## 1. Architectural Philosophy

NexWave Network Workbench is designed under strict engineering constraints:
1. **Zero Monoliths**: Functionality is divided into decoupled Swift Packages (`NetworkCore`, `DiagnosticsEngine`, `PingEngine`, `ConfigKit`, etc.).
2. **Actor Concurrency Boundary**: All network I/O, socket descriptors, and packet captures are isolated behind Swift actors to eliminate data races and prevent main-thread hitching.
3. **No Fake AI**: Diagnostics use deterministic correlation logic first. AI models are reserved strictly for future summarization and natural language explanations.
4. **Local-First Reliability**: All investigations, device profiles, and telemetry are persisted locally in SQLite with WAL mode.

---

## 2. Module Boundaries & Dependency Graph

```mermaid
graph TD
    NexWaveApp[NexWaveApp (SwiftUI / UX)]
    
    subgraph Diagnostic Layer
        DiagnosticsEngine[DiagnosticsEngine]
        CorrelationEngine[CorrelationEngine]
    end

    subgraph Tooling Layer
        PingEngine[PingEngine]
        TracerouteEngine[TracerouteEngine]
        DNSEngine[DNSEngine]
        HTTPInspector[HTTPInspector]
        InternetIntel[InternetIntel]
        SNMPEngine[SNMPEngine]
        ConfigKit[ConfigKit]
        ACLAnalyzer[ACLAnalyzer]
        ParserKit[ParserKit]
        PacketKit[PacketKit]
        CommandLibrary[CommandLibrary]
    end

    subgraph Core & Workflow Layer
        InvestigationKit[InvestigationKit]
        DeviceKit[DeviceKit]
        EnvironmentKit[EnvironmentKit]
        ReportingKit[ReportingKit]
    end

    subgraph Infrastructure Layer
        NetworkCore[NetworkCore]
        PersistenceKit[PersistenceKit (SQLite WAL)]
        SecurityKit[SecurityKit (macOS Keychain)]
    end

    NexWaveApp --> DiagnosticsEngine
    NexWaveApp --> InvestigationKit
    NexWaveApp --> DeviceKit
    NexWaveApp --> ToolingLayer
    
    DiagnosticsEngine --> PingEngine
    DiagnosticsEngine --> TracerouteEngine
    DiagnosticsEngine --> DNSEngine
    DiagnosticsEngine --> HTTPInspector
    DiagnosticsEngine --> CorrelationEngine
    
    ToolingLayer --> NetworkCore
    DiagnosticsEngine --> NetworkCore
    InvestigationKit --> PersistenceKit
    DeviceKit --> SecurityKit
    DeviceKit --> PersistenceKit
    PersistenceKit --> NetworkCore
```

---

## 3. Core Subsystems

### 3.1 NetworkCore
Provides the immutable domain primitives:
* `IPAddress`: Swift representation of IPv4 (`in_addr`) and IPv6 (`in6_addr`) with binary operations, bit masking, and arithmetic.
* `IPNetwork` / `CIDR`: Subnet representation, broadcast calculations, usable host ranges, and longest-prefix-match algorithms.
* `NetworkTarget`: Polymorphic target representation (`IPv4`, `IPv6`, `FQDN`, `URL`, `Subnet`).
* `TargetClassifier`: High-speed regex and POSIX parser for classifying arbitrary user strings into target types.

### 3.2 DiagnosticsEngine & Correlation
* **Pipeline Coordinator**: Orchestrates a 20-step diagnosis asynchronously with timeouts and early-abort semantics.
* **Deterministic Rules Engine**:
  * Rules evaluate tuples of observations: `(DNS, ICMP, TCP, TLS, HTTP, Path) -> [DiagnosticFinding]`.
  * Findings explicitly categorize statements as:
    1. **Observed**: Raw measurement (e.g. `TCP Handshake completed in 42 ms`).
    2. **Derived**: Statistical aggregation (e.g. `Jitter: 2.3 ms, Loss: 0%`).
    3. **Inferred**: Deterministic fault domain attribution with explicit confidence level (e.g. `Intermediate firewall dropped SYN packets, Confidence: High`).

### 3.3 InvestigationKit & Persistence
* **Investigation Entity**:
  * Persistent ticket container with UUID, Title, Environment, Status (`Open`, `Monitoring`, `Resolved`, `Archived`), Severity, Timeline, Findings, and Attachments.
* **Chronological Timeline**:
  * Automated event recorder that appends timestamped entries whenever tests run or results are pinned.
* **Persistence Engine (`PersistenceKit`)**:
  * Built on `libsqlite3` with Write-Ahead Logging (`PRAGMA journal_mode=WAL;`).
  * Thread-safe query connections pool.
  * Separate storage directory for binary attachments (`~/Library/Application Support/NexWave/Captures/`).

### 3.4 ConfigKit & Structural Diff
* **AST Parser**: Lexical analyzer for Cisco IOS, IOS-XE, and NX-OS configurations. Recognizes hierarchical indentation and command blocks.
* **Semantic Difference Engine**: Compares configuration ASTs to identify meaningful network changes:
  * Interface changes (access VLAN, trunk allowed VLANs, IP address, shutdown state)
  * ACL modifications (rule additions, deletions, sequence reordering)
  * Routing protocol changes (BGP neighbor additions, OSPF network statements)
  * Hostname, NTP, SNMP, and AAA changes.
* **Redaction Engine**: Uses regular expression patterns to sanitize passwords (`secret 5/8/9`, `password 7`), SNMP community strings, and pre-shared keys.

### 3.5 SNMPEngine
* Pure Swift ASN.1 / BER parser and UDP protocol handler for SNMP v1, v2c, and v3.
* Implements `GetRequest`, `GetNextRequest`, `GetBulkRequest`, and `Walk` sequences over `NWConnection`.
* Integrated MIB dictionary mapping standard RFC OIDs to human-readable names and types (`Counter32`, `Counter64`, `Gauge32`, `TimeTicks`, `OctetString`).

---

## 4. Concurrency & Performance Architecture

1. **Swift 6 Strict Concurrency**: All packages are compiled with `-strict-concurrency=complete`. No global mutable state.
2. **Actor Isolation**:
   * `DiagnosticsPipelineActor`: Manages multi-stage execution and test cancellation.
   * `PersistenceActor`: Serializes write transactions to the SQLite database.
   * `MetricsAggregatorActor`: Ingests high-frequency ping samples into memory ring buffers before periodic batched database flushing.
3. **UI Responsiveness**:
   * All long-running tests use `AsyncSequence` to stream incremental metrics to SwiftUI views without triggering full table recalculations.
   * UI components use `@Observable` and `Identifiable` tokens to restrict redraws to dirty rows only.
