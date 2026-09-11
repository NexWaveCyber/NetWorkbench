# ADR 0005: Embedded Terminal and SSH Integration Strategy

## Status
Accepted

## Context
Network engineers constantly connect to network switches, firewalls, and routers via SSH. We evaluated whether to:
1. Re-implement an entire SSH client stack from scratch using Apple `swift-nio-ssh`.
2. Launch terminal sessions using the battle-tested, Apple-hardened macOS system `/usr/bin/ssh` client over a pseudo-terminal (PTY).

## Decision
We adopt a **two-pronged strategy**:
1. **Interactive Embedded Terminal**:
   * Uses a native POSIX pseudo-terminal (`openpty` / `forkpty`) to spawn macOS's native `/usr/bin/ssh`.
   * Automatically honors the engineer's existing SSH config (`~/.ssh/config`), known_hosts verification, macOS SSH agent, Secure Enclave keys, and YubiKeys.
   * Renders inside a clean, native terminal view supporting ANSI colors, text selection, copy/paste, and command bookmarking.
   * Strictly enforces known-host validation: changed host keys trigger an explicit modal dialog alerting the engineer to potential MITM attacks; changed keys are never silently accepted.
2. **External Terminal Launchers**:
   * Native actions to "Open in Terminal.app" or "Open in iTerm2" for engineers who prefer their dedicated terminal setup.
3. **Non-Interactive Structured Prober**:
   * For automated configuration backups or device polling, non-interactive SSH channels run discrete commands and feed raw output directly to `ParserKit`.

## Consequences
* Immediate compatibility with all enterprise SSH key types and hardware tokens.
* Eliminates the massive maintenance burden of building an RFC-compliant SSH client from scratch.
* Protects user security by strictly enforcing host key validation.
