# ADR 0006: Entitlement and Commercial Licensing Architecture

## Status
Accepted

## Context
NexWave will offer both a Community (Free) tier and a Professional tier. We must ensure that monetization and feature gates do not pollute networking logic, socket handlers, or persistence schemas with ad-hoc conditionals.

## Decision
1. **EntitlementService Protocol**:
   * All feature gating is centralized behind an injected `EntitlementService` protocol:
     ```swift
     public protocol EntitlementService: Sendable {
         func isFeatureUnlocked(_ feature: FeatureKey) -> Bool
         func requireEntitlement(for feature: FeatureKey) throws
     }
     ```
2. **Feature Matrix**:
   * **Free (Community)**: Basic Ping, System DNS lookup, Subnet calculator, Single-port probe, basic traceroute, limited local history (last 50 queries), single active investigation.
   * **Professional**: Multi-Ping, Continuous MTR with hop drift, DNS Studio (DoH, DoT, DNSSEC, resolver matrix), SNMP Studio, Device Workbench, Config Workbench (semantic diff & search), ACL Analyzer, Packet Workbench, unlimited Investigations, Vendor Output Parser, audit PDF/Markdown reporting.
3. **UI Demarcation**:
   * Pro features display subtle "Pro" badges with clear explanations of professional utility, rather than abrasive paywalls.

## Consequences
* Core networking code remains 100% decoupled from billing or App Store Receipt validation.
* Adding enterprise or team collaboration licensing in future versions requires zero changes to the underlying networking engines.
