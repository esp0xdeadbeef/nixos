
Still work in progress :)


# Table
| VLAN Range | Plane                       | Trust Level          | Primary Role                      | Typical Systems                                                                                                                                      | Allowed Inbound                                     | Allowed Outbound                                 | Special Notes                                   |
| ---------- | --------------------------- | -------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------- |
| **10–19**  | **Control Plane**           | **Absolute**         | Manage and recover infrastructure | Hypervisors, switches (mgmt), routers, IPMI/iDRAC/iLO, OOB consoles, PDUs, PXE/MAAS, deploy hosts, backup controllers, virtualization control planes | Only from admin bastions in User/Corp via edge      | Only to Service Plane (auth, logging, updates)   | Never internet-exposed; compromise = total loss |
| **20–29**  | **Service Plane**           | **Limited**          | Shared internal services          | Printers, NAS, DNS, NTP, LDAP/AD, PKI, Git, CI, artifact repos, monitoring, logging, secrets store                                                   | From Users, Corp, DMZ, Lab **only via edge policy** | To Control (auth), WAN (updates), DMZ (backends) | Treated as “servers”, not trusted infra         |
| **30–39**  | **Endpoint Plane**          | **Untrusted**        | Human devices                     | Laptops, desktops, phones, VDI, thin clients, dev workstations                                                                                       | From Service Plane (responses only)                 | To Service, DMZ, WAN                             | No lateral trust; no control-plane access       |
| **40–49**  | **Corp / Regulated Plane**  | **Semi-hostile**     | Compliance / employer devices     | Work laptops, MDM phones, corp VPN hosts                                                                                                             | Very limited (only specific services)               | To WAN + minimal Service                         | Treat as external partner zone                  |
| **50–59**  | **Trash / IoT Plane**       | **Hostile**          | Embedded consumer junk            | TVs, cameras, doorbells, smart plugs, vacuums, speakers, consoles                                                                                    | None                                                | To WAN only (via edge)                           | Never talk to users or services directly        |
| **60–69**  | **DMZ / Exposed Plane**     | **Exposed**          | Public-facing services            | Web servers, reverse proxies, mail, public APIs, VPN endpoints, honeypots                                                                            | From WAN                                            | To Service Plane (explicit backends)             | No trust inward; full logging                   |
| **70–79**  | **Lab / Adversarial Plane** | **Actively Hostile** | Exploit, malware, RE              | Fuzzers, C2, exploit rigs, Android emulators, MITM boxes                                                                                             | None                                                | To WAN + specific Services                       | Kill-switch enforced; strict egress             |
| **80–89**  | **Observability Plane**     | **Limited**          | Network sensors                   | IDS, NetFlow, span collectors, packet brokers                                                                                                        | From routers / taps                                 | To Service (logging/metrics)                     | No direct user access                           |
| **90–99**  | **Transit Plane**           | **Neutral**          | Router interconnects              | Core↔Edge links, VRFs, tunnels                                                                                                                       | Only routing peers                                  | Only routing peers                               | No RA, no DHCP, static only                     |
| **1000+**  | **Upstream / WAN**          | **Unknown**          | External networks                 | ISP, VPN providers, cloud links                                                                                                                      | From Edge/Core only                                 | Everywhere (policy-gated)                        | Treated as hostile                              |



## Policy Anchors (normative)

Control Plane is not a service plane.

Service Plane is not trusted.

Endpoints never see Control.

IoT never sees anything but WAN.

DMZ only talks inward through explicit backends.

Lab is assumed compromised by design.

## Printers (correct classification)

| Attribute | Value                                  |
| --------- | -------------------------------------- |
| Plane     | Service                                |
| VLAN      | 20–29 (e.g. VLAN 21)                   |
| Access    | Users → Printers (IPP/9100 only)       |
| Discovery | mDNS reflector or central print server |
| Trust     | Low                                    |
| Why       | Accepts jobs, runs code, has web UI    |

