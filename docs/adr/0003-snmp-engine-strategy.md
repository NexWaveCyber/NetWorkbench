# ADR 0003: Pure Swift SNMP Engine vs. Net-SNMP C Library

## Status
Accepted

## Context
SNMP v1, v2c, and v3 are core enterprise network monitoring protocols. We evaluated whether to integrate the industry-standard `net-snmp` C library or implement a pure Swift protocol engine.

### Candidate A: `net-snmp` C Library
* *Drawbacks*:
  * Ancient C codebase with known buffer overflow histories.
  * Awkward multi-architecture compilation (arm64 and x86_64) inside Swift Package Manager.
  * Lack of thread safety for concurrent multi-device queries.
  * Blocks modern Swift structured concurrency (`async/await`, `CancellationHandler`).

### Candidate B: Pure Swift SNMP ASN.1/BER Engine
* *Advantages*:
  * 100% memory safety.
  * Zero external C dependencies or compilation hurdles.
  * Native Swift 6 `async/await` and task cancellation integration.
  * SNMP packet format (RFC 1157, RFC 3416, RFC 3414) is well-defined and bounded.
  * Seamless integration with Apple's `Network.framework` (`NWConnection` UDP) and `CryptoKit`.

## Decision
We choose **Candidate B: Pure Swift SNMP Protocol Engine (`SNMPEngine`)**.
* The engine will implement ASN.1 BER encoding and decoding directly in Swift.
* SNMP v1 and v2c community operations (`Get`, `GetNext`, `GetBulk`, `Walk`) are supported natively over UDP port 161.
* SNMP v3 User-based Security Model (USM) uses native `CryptoKit` for HMAC-SHA256 authentication and AES-128/256 CFB/CTR privacy encryption.
* Standard MIB trees (RFC 1213 MIB-II, IF-MIB, IP-MIB) are pre-compiled into a high-speed OID lookup trie.

## Consequences
* Completely eliminates C pointer corruption, memory leaks, and complex bridging headers.
* Provides instantaneous, non-blocking SNMP table streaming to SwiftUI tables.
