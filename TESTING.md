# Testing Strategy & Quality Assurance

> **NexWave Network Workbench**  
> QA Strategy & Lab Environment

---

## 1. Testing Pyramid

To ensure reliability for enterprise network environments, NexWave adheres to a multi-tiered test strategy:

```
          / \
         / UI\        -> Critical User Workflows (Diagnose, Save Investigation, ACL Test)
        /-----\
       / Integr\      -> SQLite persistence, DNS engine, HTTP/TLS, Keychain
      /---------\
     / Fixtures  \    -> Real sanitized CLI outputs & PCAP headers
    /-------------\
   /  Unit Tests   \  -> Subnet calculations, VLSM, CIDRs, Correlation Rules, AST
  /-----------------\
```

---

## 2. Test Suites

### 2.1 Unit Tests
* **Subnet & VLSM Calculations**: Exhaustive boundary tests across RFC 1918, RFC 6598 (CGNAT), RFC 4193 (IPv6 ULA), /31 point-to-point subnets (RFC 3021), and /32 single hosts.
* **Correlation Rules**: Deterministic tests proving correct attribution for each of the canonical network failure modes (DNS failure, ICMP filter, port reject RST, port timeout, TLS certificate expiry, backend TTFB delay).
* **ACL Simulator**: Permutations of standard and extended Cisco access lists, verifying correct evaluation order, implicit deny behavior, and shadowed rule detection.

### 2.2 Integration Tests
* **PersistenceKit**: Concurrent read/write stress testing in SQLite WAL mode.
* **SecurityKit**: Keychain item creation, reading, updating, and deletion verification.
* **ReportingKit**: Verifying that Markdown and JSON report exports strip all sensitive credential fields.

### 2.3 Fixture-Driven Parser Tests
* Deterministic verification of `ParserKit` against raw terminal captures.

---

## 3. Network Test Lab

For end-to-end integration testing, developers and CI environments can utilize containerized network namespaces simulating real impairments:
* Packet loss (5%, 25%, 100%) via `tc netem`
* Latency and jitter injection (10ms ± 5ms)
* Asymmetric routing
* Path MTU black holes (MTU 1400 with DF bit set)
* BGP route changes and DNS resolver outages.
