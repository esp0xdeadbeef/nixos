
# Table

| VLAN Range | Plane | Trust Level | Primary Role | Typical Systems | Allowed Inbound | Allowed Outbound | Special Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **2–9**    | Legacy / Quarantine | None        | Backward compatibility / junk drawer | Old devices, temporary migrations, unknown hardware, vendor defaults                                                                          | **None by default** (explicit allow only)                 | Internet only (if absolutely required)                                           | **Never place new devices here.** Treat as hostile. Plan removal. |
| **10–19** | **Control Plane** | **Absolute** | Authority + recovery | Hypervisor mgmt, router/switch mgmt, OOB (IPMI/iDRAC/iLO), provisioning (PXE/MAAS), **IdP/LDAP/Kerberos**, **PKI/CA**, **authoritative DNS**, **authoritative NTP** | **Only from Admin Bastion(s)** (and optionally a break-glass host) | To **minimal** required deps: WAN (updates) + Service plane (logging/metrics if you must) | If compromised: _total loss_. Treat as crown jewels. No “general services” here. |
| **20–29** | **Platform / Service Plane** | **Limited** | Shared internal services (consumers of trust) | Git, CI runners/controllers, artifact repos, internal registries, internal APIs, monitoring collectors, log ingest, config mgmt, update cache/mirror | From Endpoints/Corp/DMZ/Lab **only via edge policy** | To Control (auth/certs/DNS/NTP), WAN (updates), DMZ (explicit backends) | Assume compromise over time. Strong segmentation + hardening + least privilege. |
| **30–39** | **Endpoint Plane** | **Untrusted** | Human devices | Personal laptops/desktops, phones, dev workstations, VDI/thin clients | From Service plane (responses only) + explicit inbound services | To Service, DMZ, WAN | No lateral trust. No direct Control access. Default deny inbound. |
| **40–49** | **Corp / Regulated Plane** | **Semi-hostile** | Employer/compliance devices | Work laptops, MDM phones, corp VPN clients/hosts | Very limited, explicit services only | To WAN + minimal Service | Treat like an external partner zone. Avoid trust transitivity. |
| **50–59** | **Untrusted Devices / IoT** | **Hostile** | “Smart” junk + appliances | TVs, cameras, doorbells, smart plugs, consoles, **printers**, **NAS/appliances**, scanners | None (or explicit mgmt from bastion only) | To WAN only (or tightly pinned Service targets) | Printers/NAS behave like IoT. Put them here unless you can actually harden/audit them. |
| **60–69** | **DMZ / Exposed Plane** | **Exposed** | Public-facing services | Reverse proxies, web servers, mail, public APIs, VPN endpoints, honeypots | From WAN (as published) | To Service plane (explicit backends only) | No implicit trust inward. Full logging. Tight egress. |
| **70–79** | **Lab / Adversarial Plane** | **Actively hostile** | Malware/RE/exploit/testing | Fuzzers, C2, exploit rigs, Android emulators, MITM boxes, detonation VMs | None by default | To WAN + specific Service targets (if needed) | Assume owned. Kill-switch + strict egress + no inbound from trusted planes. |
| **80–89** | **Observability Plane** | **Limited** | Passive sensors + telemetry | IDS sensors, NetFlow/IPFIX collectors, span collectors, packet brokers | From routers/taps only | To Service plane (logging/metrics) | No direct user access. Prefer one-way flows. |
| **100–199** | **Transit Plane** | **Neutral** | Router↔router interconnects | Core↔Edge links, Edge↔Access links, router-to-router VLAN subifs, VRF uplinks, underlay for tunnels | Only routing peers on that VLAN | Only routing peers on that VLAN | **No RA, no DHCP, static only.** One VLAN per adjacency. IPv4 `/31` (or `/30`), IPv6 `/127`. |
| **1000–4094** | **Upstream / WAN** | **Unknown** | External L2 handoffs | ISP VLANs, provider handoffs, cloud L2, upstream transit VLANs | From Edge/Core only | Everywhere (policy-gated) | Treated as hostile. Don’t bridge into internal. Ingress/egress filtering mandatory. |

* * *

## Documented Spares / Reserved Blocks

These are intentional “do not allocate casually” buffers.

| VLAN Range | Status | Why |
| --- | --- | --- |
| **1–9** | Reserved | Avoid default/legacy footguns; keep small numbers out of circulation |
| **90–99** | Reserved spare | Keeps a clean gap between host planes and transit; also a migration buffer if you ever used 90–99 before |
| **200–299** | Reserved spare | Future needs (storage plane, backup-only, guest Wi-Fi, dedicated printer plane if you insist) |
| **300–999** | Reserved spare | Large gap to stop accidental semantic creep (“just grab one”) and to keep WAN block visually separate |

* * *

## Policy Anchors (normative)

* **Control Plane is authority.** If it grants trust, it lives in 10–19.
    
* **Service Plane is not trusted.** It consumes trust, doesn’t define it.
    
* **Endpoints never see Control.** Access only via bastion / jump + strong auth.
    
* **IoT/Devices never see anything but WAN (and explicitly pinned services).**
    
* **DMZ talks inward only through explicit backends.**
    
* **Lab is assumed compromised by design.**
    
* **Transit carries routers only.** No RA/DHCP/mDNS/hosts.
    

* * *

## Printers (correct classification, reconciled)

| Attribute | Value |
| --- | --- |
| Plane | Untrusted Devices / IoT |
| VLAN | 50–59 (e.g. VLAN 51) |
| Access | Users → Printers (IPP/9100 only) via policy |
| Discovery | Prefer central print server; otherwise mDNS reflector with tight scoping |
| Trust | Low/Hostile |
| Why | Accepts jobs, parses input, runs firmware, exposes web UI |

