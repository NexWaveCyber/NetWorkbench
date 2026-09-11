# Privacy Principles & Data Handling

> **NexWave Network Workbench**  
> *Your network data stays on your Mac.*

---

## 1. Local-First Guarantee

NexWave is engineered from the ground up as a **local-first application**:
* **No Mandatory Account**: Full functionality (diagnostics, investigations, device management, SNMP, configs, packet summaries) is operational without creating an account or signing in.
* **No Cloud Database**: All investigations, device hostnames, IP addresses, network topologies, router configurations, and test logs remain exclusively on your Mac.
* **Zero Secret Telemetry**: We never collect or transmit IP addresses, domain names, network device credentials, CLI outputs, configuration files, or packet capture contents.

---

## 2. External Network Interaction Disclosure

NexWave performs network calls exclusively when explicitly commanded by the user or required for a requested diagnostic tool:
1. **Target Diagnostics**: When you diagnose a host or IP, packets are sent directly to that target (and intermediary hops for traceroute).
2. **Internet Intelligence (ASN / RDAP)**: Public WHOIS/RDAP/ASN queries connect directly to public registries (e.g. ARIN, RIPE, APNIC).
3. **Public DNS Resolvers**: When using DNS Studio resolver comparison, queries are transmitted directly to the selected public resolvers (e.g. Cloudflare 1.1.1.1, Google 8.8.8.8, Quad9 9.9.9.9).

---

## 3. Support Bundle Redaction

If you choose to export an internal diagnostic bundle for bug reporting:
* The bundle is generated locally in plain text/JSON.
* All IP addresses, hostnames, and credentials can be reviewed and redacted before sharing.
* NexWave does not transmit support bundles automatically.
