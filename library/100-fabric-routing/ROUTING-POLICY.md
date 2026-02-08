## VLAN Planes & Trust Model

### Authoritative VLAN Classification

| VLAN Range | Plane | Trust | Purpose | Typical Systems | Inbound Policy | Outbound Policy | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **2–9** | Legacy / Quarantine | None | Backward compatibility, containment | Unknown hardware, vendor defaults, temporary migrations | **None by default** (explicit allow only) | WAN only (if strictly required) | **Never place new systems here.** Treat as hostile. Plan removal. |
| **10–19** | **Control Plane** | **Absolute** | Authority & recovery | Hypervisor mgmt, router/switch mgmt, OOB (IPMI/iDRAC/iLO), PXE/MAAS, **IdP**, **PKI/CA**, **auth DNS**, **auth NTP** | **Admin bastions only** (optional break-glass host) | Minimal dependencies only: WAN (updates), Service plane (logging/metrics if unavoidable) | **Total compromise = total loss.** No general services allowed. |
| **20–29** | **Service Plane** | Limited | Shared internal services | Git, CI, artifact registries, internal APIs, monitoring/log collectors, config mgmt, mirrors | From Endpoints / Corp / DMZ / Lab **only via policy router** | To Control (auth/certs/DNS/NTP), WAN (updates), DMZ (explicit backends) | Assume eventual compromise. Enforce least privilege and segmentation. |
| **30–39** | **Endpoint Plane** | Untrusted | Human-operated devices | Personal laptops/desktops, phones, dev workstations, VDI | Responses from Service plane + explicitly exposed inbound services | To Service, DMZ, WAN | No lateral trust. **Never** direct Control access. Default-deny inbound. |
| **40–49** | **Corp / Regulated Plane** | Semi-hostile | Employer / compliance devices | Work laptops, MDM phones, corp VPN clients | Explicitly permitted services only | WAN + minimal Service | Treat as external partner network. No trust transitivity. |
| **50–59** | **IoT / Untrusted Devices** | Hostile | Appliances & embedded systems | TVs, cameras, doorbells, smart plugs, consoles, **printers**, **NAS/appliances**, scanners | None (optional mgmt from bastion only) | WAN only (or tightly pinned Service targets) | Assume hostile firmware. Printers/NAS belong here unless proven otherwise. |
| **60–69** | **DMZ / Exposed Plane** | Exposed | Public-facing services | Reverse proxies, web/mail servers, public APIs, VPN endpoints, honeypots | From WAN (as published) | To Service plane (explicit backends only) | No implicit inward trust. Full logging. Tight egress controls. |
| **70–79** | **Lab / Adversarial Plane** | Actively hostile | Offensive testing & research | Fuzzers, exploit rigs, C2, Android emulators, MITM boxes, detonation VMs | None by default | WAN + explicitly allowed Service targets | Assume compromised by design. Kill-switch and strict egress required. |
| **80–89** | **Observability Plane** | Limited | Passive telemetry | IDS sensors, NetFlow/IPFIX collectors, span/packet brokers | From routers/taps only | To Service plane (logging/metrics) | No interactive access. Prefer one-way data flow. |
| **100–199** | **Access Transit** | Neutral | Policy↔Access interconnects | Policy↔Access router links, router VLAN subinterfaces | Routing peers only | Routing peers only | **No RA, no DHCP, static only.** One VLAN per adjacency. `/31` + `/127`. |
| **200–299** | **Core Transit** | Neutral | Core↔Policy interconnects | Core↔Policy router links | Routing peers only | Routing peers only | Same constraints as Access Transit. Separate range for clarity and fault isolation. |
| **1000–4094** | **Upstream / WAN** | Unknown | External L2 handoffs | ISP VLANs, provider handoffs, cloud L2 | Edge/Core only | Policy-gated everywhere | Treated as hostile. Never bridged inward. Ingress/egress filtering mandatory. |

* * *

## Reserved / Buffer VLAN Ranges

These ranges exist **to prevent accidental semantic drift**.

| VLAN Range | Status | Rationale |
| --- | --- | --- |
| **1–9** | Reserved | Avoid default/legacy footguns; keep low numbers out of circulation |
| **90–99** | Reserved buffer | Clean gap between host planes and transit; migration safety |
| **300–999** | Reserved buffer | Prevent “just grab one” creep; visually separates WAN block |

* * *

## Policy Anchors (Normative)

These rules are **design invariants**, not guidelines:

* **Control Plane defines trust.** If it grants authority, it lives in 10–19.
    
* **Service Plane consumes trust.** It never defines it.
    
* **Endpoints never directly access Control.** Bastion or jump host only.
    
* **IoT and appliances talk outward only** (unless explicitly pinned).
    
* **DMZ talks inward only via declared backends.**
    
* **Lab is hostile by definition.**
    
* **Transit carries routers only.** No hosts, no RA, no DHCP, no discovery protocols.
    

Violations are architectural bugs, not “temporary exceptions”.

* * *

## Printers (Explicit Classification)

| Attribute | Value |
| --- | --- |
| Plane | IoT / Untrusted Devices |
| VLAN | 50–59 (e.g. VLAN 51) |
| Allowed Access | Users → Printers (IPP/9100 only) via policy |
| Discovery | Central print server preferred; otherwise tightly scoped mDNS reflector |
| Trust Level | Hostile |
| Rationale | Accepts untrusted input, parses complex formats, runs opaque firmware, exposes web UI |

