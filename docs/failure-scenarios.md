# D5 — Correctness and Failure-Scenario Review

**Status:** Proposed validation matrix, not results from a running implementation. Expected outcomes assume the unverified Salesforce capabilities identified in D1.

| ID | Scenario / injection | Required result | Durable evidence / check |
|---|---|---|---|
| S1 | Same webhook delivered twice | One logical business effect; identical duplicate acknowledged | Canonical inbox event identity and payload hash; one audit logical edit |
| S2 | Salesforce field updates 202 then 201 | Older same-field update cannot regress newer field | Per-field Salesforce source ordering plus cross-system causal eligibility |
| S3 | Older city event follows newer phone event | Eligible city edit still applied independently | Per-field sequence and complete available audit change set |
| S4 | Salesforce edits phone, portal edits city concurrently | Both survive if causally independent | Per-field merge, two logical audit edits |
| S5 | Both sides concurrently edit phone | Provisional Salesforce authority; losing portal value audited | Causal evidence, field policy, append-only conflict resolution |
| S6 | Unknown cross-system causality | No arbitrary winner or destructive replay | Unresolved obligation and quarantine/reconciliation evidence |
| S7 | Worker crashes after DB write but before commit | Transaction rolls back and leased work can retry | No partial business/audit/completion commit |
| S8 | Worker crashes after remote Salesforce success, before local confirmation | Verify ambiguous outcome before retry or lane progression | Attempt record, verification evidence, fenced confirmation |
| S9 | Create times out after Salesforce creates record | No duplicate remote record if verified external-ID upsert contract holds | Mapping and external-ID verification; block until resolved otherwise |
| S10 | Salesforce webhook silently lost | Recover through complete historical source and shared inbox | Historical checkpoint + event dedup; completeness obligation |
| S11 | Historical page inserted, checkpoint transaction fails | Replay page safely; checkpoint does not falsely advance | Same transaction for page inserts and checkpoint |
| S12 | Six-hour Salesforce outage at 25 portal edits/s | 540,000 logical outbound obligations retained; no claimed 30s SLA | Outbox backlog, audit, retries and active recovery barriers |
| S13 | Newer portal update while older same-record request is in flight | No unsafe overlapping remote effects | Durable per-record lane ownership; unresolved ambiguity blocks FIFO |
| S14 | Contact create arrives before parent mapping | Contact waits; no guessed parent Salesforce ID | Mapping state and dependency-blocked obligation |
| S15 | Echo webhook from successful outbound update | No infinite loop or duplicate outbound obligation | Origin/correlation/causal evidence, not field-value equality alone |
| S16 | Same event identity but different payload | Integrity exception; no silent overwrite | Inbox payload hash, quarantine, correctness exception metric |
| S17 | Historical source incomplete beyond retention | Completeness cannot be asserted; barrier remains | Recovery obligation and explicit unsupported guarantee |
| S18 | API rate pressure / 429 responses | Shared budget applies to writes, reads, retries, verification | Global limiter logs and backoff attempt history |

## Acceptance criteria

- **Durability:** Every accepted portal edit and acknowledged Salesforce event is durably recoverable.
- **Ordering:** Per-field Salesforce source ordering and per-record outbound FIFO prevent regression without discarding unrelated edits.
- **Conflict handling:** Causally sequential edits retain order; truly concurrent same-field edits follow business-approved authority; unresolved causality remains visible.
- **Auditability:** One immutable edit record retains available old/new field values; losing conflict evidence is preserved separately.
- **No loops:** Inbound replication and confirmed echoes do not create unbounded outbound replication.
- **Recovery:** Checkpoint advancement is atomic with historical ingestion; barriers require completeness proof, not just a high-water mark.
- **Honest SLA:** Healthy-operation stage budgets are targets; six-hour outage violates 30-second remote sync; strict worst-case proof remains pending.

## Suggested test harness (not executed)

Use a deterministic fake Salesforce API that can inject duplicates, reordered events, dropped webhooks, 429s, timeouts after success, ambiguous creates, slow writes, and six-hour outage simulation. Assert PostgreSQL invariants after worker restarts and retry storms. Use randomized per-field edit histories and compare the final state against a causal reference model. Verify that the three D1 primary metrics trigger at their defined thresholds. No claim is made that this harness or any integration test has been run.
