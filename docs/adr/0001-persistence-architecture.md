# ADR 0001: Persistence Architecture — Hybrid SQLite (WAL) + Filesystem Store vs. SwiftData

## Status
Accepted

## Context
NexWave requires local persistence for high-level domain entities (`Investigation`, `TimelineEvent`, `Device`, `Environment`, `SavedCommand`) as well as streaming, high-frequency network metrics (continuous ping records at 100ms intervals, MTR hop records, SNMP interface counters) and large binary artifacts (router config files, PCAP/PCAPNG captures, exported PDF/Markdown reports).

We evaluated three architectural candidates:
1. **SwiftData** (Apple's modern persistence framework for Swift):
   * *Pros*: Native `@Model` macro, tight SwiftUI integration.
   * *Cons*: Immature multi-threaded actor boundaries (frequent `Illegal attempt to map a relationship across concurrency contexts` crashes in high-throughput loops), unpredictable memory overhead when inserting thousands of streaming metric points per minute, opaque schema migration capabilities.
2. **Core Data**:
   * *Pros*: Mature, battle-tested.
   * *Cons*: Heavy legacy Objective-C runtime baggage, cumbersome `NSManagedObject` lifecycle, poor ergonomical fit for modern Swift 6 strict concurrency.
3. **Hybrid SQLite with Write-Ahead Logging (WAL) + Filesystem Store**:
   * *Pros*: Deterministic query planner, sub-millisecond concurrent transactions, zero UI thread hitches, explicit versioned schema migrations, rock-solid cross-process safety, pure Swift typed repository interfaces.
   * *Cons*: Requires maintaining SQL schema migrations.

## Decision
We select **SQLite with Write-Ahead Logging (WAL) mode** as the primary metadata persistence engine, combined with a **Filesystem-backed store** for large binary payloads:
1. **Relational Models & History**: Stored in `~/Library/Application Support/NexWave/nexwave.sqlite` with WAL mode enabled.
2. **High-Frequency Metrics**: Stored in in-memory ring buffers (`RingBuffer<T>`) for real-time UI charting, with periodic aggregated rollups committed to SQLite.
3. **Binary Blobs**: Large configuration files (`.cfg`) and packet captures (`.pcap`/`.pcapng`) are stored directly on disk in dedicated sandboxed subdirectories (`~/Library/Application Support/NexWave/Captures/`), referenced in SQLite by UUID and cryptographic SHA-256 hash.

## Consequences
* High-frequency telemetry can never corrupt or lock the primary domain entity tables.
* Database backup and migration remains deterministic and transparent.
* Memory usage remains bounded even when running continuous diagnostics for hours.
