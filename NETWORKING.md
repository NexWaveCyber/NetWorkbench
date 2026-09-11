# Networking Architecture & Socket Specifications

> **NexWave Network Workbench**  
> Low-Level Networking Architecture

---

## 1. Socket Architecture & Protocols

NexWave uses specialized low-level networking primitives across each protocol layer:

### 1.1 ICMP / ICMPv6 Ping
* **Socket Type**: Darwin Unprivileged ICMP Datagram Socket (`SOCK_DGRAM`, `IPPROTO_ICMP` / `IPPROTO_ICMPV6`).
* **Packet Structure**:
  * RFC 792 (ICMP) and RFC 4443 (ICMPv6).
  * Type: 8 (Echo Request), Code: 0.
  * Identifier: Process PID & 0xFFFF.
  * Sequence: Monotonically increasing counter per probe.
  * Payload: 56 bytes payload containing nanosecond timestamp for sub-millisecond precision.
* **Kernel Filter**: The macOS kernel automatically routes matching Echo Replies (Type: 0) to the datagram socket based on the identifier.

### 1.2 TCP Connect & Port Probes
* **API**: Apple `Network.framework` (`NWConnection`) and POSIX non-blocking `connect()` with `select()`/`poll()`.
* **State Machine**:
  * `Ready`: Port is open and service responded with TCP SYN-ACK.
  * `Failed(ECONNREFUSED)`: Port is closed; host actively responded with TCP RST.
  * `Waiting(ETIMEDOUT)`: Port is filtered; packets silently dropped by firewall.
* **Timing**: Nanosecond-resolution delta between `NWConnection.stateUpdateHandler = .preparing` and `.ready`.

### 1.3 Path Analysis & Traceroute / MTR
* **Hop Discovery**:
  * Sends sequential UDP or ICMP probes with incrementing IP Time-to-Live (`IP_TTL` / `IPV6_UNICAST_HOPS`) starting at TTL=1.
  * Intermediary routers send back ICMP Type 11 (Time Exceeded).
  * Per-hop round-trip time, jitter, and packet loss are tracked across sliding time windows.
* **ICMP Rate Limiting Awareness**:
  * Many core Internet routers prioritize packet forwarding over generating ICMP Time Exceeded packets.
  * NexWave's correlation engine explicitly identifies single-hop packet loss that does NOT propagate to subsequent hops, correctly classifying it as router CPU ICMP rate-limiting rather than path loss.

### 1.4 DNS Studio & Resolvers
* **Standard DNS (Do53)**: UDP port 53 with fallback to TCP port 53 on truncated responses (TC bit set).
* **DNS-over-HTTPS (DoH)**: RFC 8484 over HTTP/2 with binary `application/dns-message` payload.
* **DNS-over-TLS (DoT)**: RFC 7858 over TLS on port 853.
* **DNSSEC**: Parsing of RRSIG, DNSKEY, and DS records; validates chain of trust from root anchors.

### 1.5 HTTP & TLS Inspection
* **Metrics**: Leverages `URLSessionTaskMetrics` for discrete phase breakdowns:
  * Domain Lookup Time (`domainLookupEndDate - domainLookupStartDate`)
  * TCP Handshake Time (`connectEndDate - connectStartDate`)
  * TLS Handshake Time (`secureConnectionEndDate - connectEndDate`)
  * Time to First Byte (TTFB) (`responseStartDate - requestStartDate`)
  * Response Transfer Time (`responseEndDate - responseStartDate`)
* **TLS Parameters**: Negotiated cipher suite (e.g. `TLS_AES_256_GCM_SHA384`), protocol version (`TLS 1.3`), ALPN negotiation (`h2`, `http/1.1`), and full X.509 certificate chain validation.
