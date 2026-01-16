
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

## Storage & Persistence Model

The system distinguishes **logical state** from **durable persistence**.

### Design Principle

The control plane operates on _declared state_, not transactional durability.  
Disk writes exist to preserve intent across restarts — not to guarantee synchronous durability.

### Storage Tiers

| Layer | Purpose | Characteristics |
| --- | --- | --- |
| **tmpfs (RAM)** | Active working state | Fast, volatile, frequently updated |
| **Persistent storage (NAS)** | Durable snapshot of state | Slower, authoritative, infrequently written |

### Write Strategy

* All active state is written to an in-memory filesystem (e.g. `/run/vmctl`)
    
* Periodic flush synchronizes state to persistent storage
    
* Flushes are **batched and atomic**
    
* No per-event synchronous writes
    

This avoids disk spin-ups, minimizes latency, and preserves correctness.

### Persistence Guarantees

* Loss of power may lose _recent_ state updates
    
* System recovers by reconciling desired state with actual state
    
* No correctness depends on sub-second durability
    

This design favors **determinism and recoverability** over immediacy.

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
    
* Enforce local safety constraints
    
* Report observed state back to NAS
    

### Host State Semantics

**Important distinction:**

* **HELD** — operator-initiated pause (administrative)
    
* **SUSPENDED** — infrastructure-induced pause (e.g., storage unavailable)
    

This distinction is critical for recovery logic and operational clarity.

* * *

## VM Lifecycle

Each VM is managed as an independent state machine.

* State transitions are explicit
    
* No implicit side effects
    
* Runtime behavior is isolated from placement logic
    

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
    

This prevents split-brain execution during coordinator failure or restart.

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

