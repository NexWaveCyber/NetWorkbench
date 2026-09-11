# Vendor CLI Output Parsers Architecture

> **NexWave Network Workbench**  
> `ParserKit` Specification

---

## 1. Parser Architecture

Network engineers constantly paste raw command output from switches and routers. `ParserKit` transforms unformatted text into typed, structured tabular data while **always preserving the original raw text**.

### 1.1 The `VendorOutputParser` Protocol

```swift
public protocol VendorOutputParser: Sendable {
    var vendor: Vendor { get }
    var operatingSystem: OperatingSystem { get }
    var commandFamily: CommandFamily { get }
    var supportedVersions: [String] { get }
    var parserVersion: String { get }

    func canParse(rawOutput: String) -> Double // Confidence score 0.0 ... 1.0
    func parse(rawOutput: String) throws -> StructuredResult
}
```

---

## 2. Supported Vendor Commands (V1 Seed)

1. **`show interfaces`** (Cisco IOS-XE / NX-OS / Arista EOS)
   * Extracted Fields: Interface name, admin state, operational state, hardware type, MAC, IP, MTU, bandwidth, duplex, speed, input/output packets, byte counts, CRC errors, frame errors, input discards.
   * Anomaly Flags: Non-zero CRC, increasing errors, half-duplex on gigabit links, flap detection.
2. **`show ip interface brief`** (Cisco IOS-XE)
   * Extracted Fields: Interface, IP address, OK status, Method, Status, Protocol.
3. **`show ip route`** (Cisco / Arista)
   * Extracted Fields: Protocol code (C, S, R, B, O, D), network prefix, metric/administrative distance, next-hop IP, outgoing interface, route age.
4. **`show mac address-table`** (Cisco IOS-XE / Arista EOS)
   * Extracted Fields: VLAN, MAC address, Type (dynamic/static), Ports.
5. **`show arp`** (Cisco IOS-XE)
   * Extracted Fields: Protocol, IP Address, Age (min), MAC address, Type, Interface.
6. **`show cdp neighbors` / `show lldp neighbors`** (Cisco / Arista)
   * Extracted Fields: Device ID, Local Interface, Holdtime, Capability, Platform, Port ID.
7. **`show bgp summary` / `show ip bgp summary`**
   * Extracted Fields: Neighbor IP, BGP version, Remote AS, MsgRcvd, MsgSent, TableVersion, InQ, OutQ, Up/Down time, State/PfxRcd.

---

## 3. Fixture-Driven Parser Testing

All parsers are verified against sanitized, real-world CLI capture fixtures located in:
`Tests/ParserKitTests/Fixtures/<Vendor>/<OS>/<Command>/`
Each test pair consists of:
* `sample_NN.txt`: Raw CLI output as copied from an engineering terminal.
* `sample_NN.json`: Expected parsed JSON object structure.
Any deviation in schema or field extraction fails the unit test suite automatically.
