
## High-Level Topology

```
ISP
 │
 │  (PPPoE, DHCPv6-PD)
 ▼
router-core
 │
 │  (routed prefixes, no clients)
 ▼
router-edge
 │
 │  (policy decisions, prefix slicing)
 ▼
router-access
 │
 │  (client VLANs, RA, SLAAC)
 ▼
Clients
router-egress
 │
 │  (VPN / WAN selection per VLAN)
 ▼
```

Each router has **one clear job**.  
No router tries to “do everything”.

* * *

## Router Roles

### 1. `router-core`

**Upstream termination and ownership**

Responsibilities:

* Terminates ISP connectivity
    
    * PPPoE
        
    * DHCPv6 Prefix Delegation (PD)
        
* Receives the _largest_ IPv6 prefix available from the ISP  
    (e.g. `/48`, `/52`, or whatever the ISP provides)
    
* Owns the upstream default route
    
* Does **not** serve clients directly
    

Key principles:

* Single source of truth for “what the ISP gave us”
    
* No VLAN logic
    
* No VPN logic
    
* No client-facing RA
    

Think of this as the **border router**.

* * *

### 2. `router-edge`

**Prefix slicing and routing policy**

Responsibilities:

* Receives a large prefix from `router-core`
    
* Subdivides that prefix into smaller prefixes
    
    * e.g. `/56` → `/60` → `/64`
        
* Decides **which downstream router gets which prefix**
    
* Aggregates and enforces routing policy
    

Key principles:

* This router decides _allocation_, not usage
    
* No VPN termination
    
* No client VLANs
    

Think of this as the **address space manager**.

* * *

### 3. `router-egress`

**Traffic exit and policy-based routing**

Responsibilities:

* Terminates VPN tunnels
    
    * WireGuard
        
    * OpenVPN
        
    * future transports
        
* Implements **policy-based routing**
    
* Maps VLANs or prefixes to:
    
    * specific VPNs
        
    * direct WAN
        
    * other exits
        
* Acts as a controlled **egress point**
    

Key principles:

* VPN is an _implementation detail_
    
* The real function is **egress selection**
    
* May handle NAT (IPv4 and/or IPv6 NPTv6 if required)
    

This router exists because **“where traffic leaves” is a distinct concern**.

* * *

### 4. `router-access`

**Client-facing router**

Responsibilities:

* Hosts client VLANs
    
* Advertises IPv6 prefixes via Router Advertisements (RA)
    
* Uses SLAAC (typically `/64` per VLAN)
    
* May run DHCPv4 for legacy clients
    
* Does **not** allocate prefixes upstream
    

Key principles:

* Simple, boring, predictable
    
* No upstream complexity
    
* No VPN logic
    
* No prefix slicing
    

This is the **only router clients ever see**.

* * *

## Why This Architecture Exists

Traditional firewall/router appliances mix:

* prefix delegation
    
* routing policy
    
* VPNs
    
* client services
    
* UI state
    

into a single mutable system.

This design:

* Separates concerns cleanly
    
* Makes IPv6 prefix flow explicit
    
* Allows independent testing of each stage
    
* Enables replacing _any_ layer without rewriting the rest
    
* Is fully declarative and reproducible
    

* * *

## IPv6 Design Philosophy

* **Prefixes flow downstream**
    
* Decisions flow upstream
    
* Each router:
    
    * either _owns_ a prefix
        
    * or _consumes_ a prefix
        
    * never both ambiguously
        
* `/64` is reserved for **client-facing networks**
    
* Larger prefixes are for **routing and delegation only**
    

* * *

## Naming Conventions

Directories and systems follow numeric order by position in the network:

```
routers/
├── 1-core/
├── 2-edge/
├── 3-egress/
├── 4-access/
```

System names:

* `router-core`
    
* `router-edge`
    
* `router-egress`
    
* `router-access`
    

This keeps:

* topology readable
    
* diffs obvious
    
* intent clear
    

* * *

## Status

This setup is:

* actively evolving
    
* used as a **prototype reference router**
    
* designed to eventually fully replace GUI-based routers
    

The priority is **correctness, clarity, and future-proofing**, not shortcuts.

* * *

## Non-Goals (Explicit)

* No implicit magic
    
* No hidden state
    
* No “it works but nobody knows why”
    
* No coupling router roles together “because it’s easier”
    
