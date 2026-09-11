# ADR 0002: Privilege and Security Architecture

## Status
Accepted

## Context
Many legacy network applications ask for `sudo` or execute as root to send ICMP echo packets or capture network packets. Running a full macOS desktop application as root violates Apple security guidelines, exposes the system to immense privilege escalation risk, and breaks the macOS App Sandbox.

## Decision
1. **Zero Root Privilege Execution**: The NexWave macOS application operates entirely unprivileged in user space.
2. **Darwin Non-Root ICMP Datagram Sockets**: For ICMP and ICMPv6 echo requests (Ping, Traceroute), NexWave uses Darwin's unprivileged datagram socket support:
   ```c
   int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
   ```
   macOS handles echo reply demultiplexing in the kernel without needing root/raw sockets (`SOCK_RAW`).
3. **Hardware Keychain for Credentials**: All credentials (SSH private keys, passwords, SNMP v3 secrets, SNMP community strings) are stored exclusively in macOS Keychain Services (`kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). They are never written to SQLite, logs, plists, or diagnostic dumps.
4. **Isolated Privileged Helper for Live Sniffing (Future)**: When live packet sniffing from `/dev/bpf*` is introduced in a future release, it will be decoupled into an isolated Launchd helper daemon managed via `SMAppService.daemon`, communicating over an authenticated `NSXPCConnection` with code-signing validation.

## Consequences
* Immediate, frictionless user onboarding (no administrator password prompts needed on launch).
* Zero credential leakage risk from application crash dumps or local backups.
