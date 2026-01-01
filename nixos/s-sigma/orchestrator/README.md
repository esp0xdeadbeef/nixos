
# VM Control Plane – Architecture & Design

This document defines the architecture, responsibilities, and operational guarantees of the VM control system. The system is intentionally simple, deterministic, and auditable, favoring explicit state transitions over implicit behavior.

* * *

## Authority Model

| Component | Authority Over | Notes |
| --- | --- | --- |
| Coordinator | Desired state, placement, migration | Never executes workloads |
| Host | Actual VM execution | Acts only on declared state |
| NAS | Source of truth | No logic, no orchestration |
| VM | Internal lifecycle only | No orchestration authority |

**Rule:**  
No component may mutate state owned by another component. All cross-component interaction occurs through declared state files.

* * *

## File Ownership Rules

| Path | Written By | Read By |
| --- | --- | --- |
| `/hosts/*/config.yaml` | Host | Coordinator |
| `/hosts/*/heartbeat.json` | Host | Coordinator |
| `/assignments/*.yaml` | Coordinator | Host |
| `/migrations/*.yaml` | Coordinator | Host |
| `/vms/*/manifest.yaml` | Operator | Coordinator, Host |
| `/vms/*/snapshots/` | Host | Host |

This contract is strict. Violations are considered bugs.

* * *

## Coordinator Behavior

The coordinator is **stateless** and **level-triggered**.

### Key Properties

* Reads current system state from NAS
    
* Computes desired state deterministically
    
* Writes assignments and migration intents
    
* Never executes VM operations
    
* Safe to restart at any time
    

### Execution Model

The coordinator reacts to **current observed state**, not events.

> The system converges because state is reconciled continuously, not because actions are sequenced.

This guarantees:

* Idempotent operation
    
* Safe restarts
    
* No dependency on event ordering
    

* * *

## Host Behavior

Each host is an autonomous executor that reconciles declared state with reality.

### Host Responsibilities

* Register itself and report heartbeat
    
* Execute assigned VM lifecycle actions
    
* Enforce local safety and resource limits
    
* Report actual state back to NAS
    

### Host State Semantics

**Important distinction:**

* **HELD** — operator-initiated pause (intentional, administrative)
    
* **SUSPENDED** — infrastructure-induced pause (e.g. NAS unavailable)
    

This distinction is critical for incident analysis and recovery automation.

* * *

## VM Lifecycle

Each VM is managed as an independent state machine:

* State transitions are explicit
    
* No implicit side effects
    
* VM runtime behavior is isolated from placement logic
    

VMs respond only to:

* Assignment changes
    
* Explicit lifecycle commands
    
* Host availability
    

* * *

## Migration Semantics

Migration is a controlled, serialized operation.

### Invariants

* At most **one active migration per VM**
    
* Migration requires an exclusive lock
    
* Locks are time-bound and recoverable
    
* Hosts must refuse to act on conflicting migrations
    

This prevents split-brain execution during coordinator restarts or network partitions.

* * *

## Service Overview

| Layer | Service | Purpose |
| --- | --- | --- |
| Coordinator | `vmctl-coordinator.service` | Assigns VMs, manages failover |
| Host | `vmctl.service` | Host-level reconciliation |
| Host | `vmctl-heartbeat.timer` | Periodic liveness reporting |
| Host | `vmctl-vm@.service` | Per-VM execution |
| Host | `vmctl-health.service` | Health monitoring & fault signaling |
| Host | `vmctl-snapshot.timer` | Periodic snapshot management |

* * *

## Design Guarantees

| Property | Guarantee |
| --- | --- |
| Stateless control plane | Coordinator restart-safe |
| Deterministic behavior | State-derived, not event-driven |
| No split-brain | Single authoritative state store |
| Graceful degradation | Hosts continue safely without coordinator |
| Auditable behavior | All actions persisted as state transitions |

