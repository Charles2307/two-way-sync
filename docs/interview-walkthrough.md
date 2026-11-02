# D6 — Ten-Minute Interview Walkthrough

**Status:** Presentation notes based on the approved D1 architecture. No production implementation or verified Salesforce integration is claimed.

## 0:00–1:00 — Restate the problem and guarantees

“Two systems independently edit approximately five million customer and contact records. We need bidirectional synchronization, a Salesforce API limit of 100 requests per second, duplicate/out-of-order/lost webhooks, six-hour outages, and no silent loss or infinite loops. I separate three promises: durable local acceptance, eventual recovery subject to Salesforce history, and a strict 30-second remote synchronization deadline that cannot hold during outages.”

## 1:00–3:00 — Draw the high-level architecture (D2)

“Salesforce sends webhooks to an API that validates and writes a durable PostgreSQL inbox before returning 2xx. Inbound workers reconcile field changes in atomic transactions. Portal edits commit business rows, immutable audit, idempotency response and an outbound obligation in one transaction. Outbound workers send under a global rate limiter and per-record FIFO lanes. Recovery workers replay historical changes through the same inbox. PostgreSQL also holds mappings, field sync state, confirmed remote values and recovery barriers.”

Point to the D2 diagram. Stress that remote API calls happen **outside** database transactions.

## 3:00–4:30 — Data model and ordering

“Portal records have UUIDs and optimistic `portal_version`; Salesforce has separate IDs and ordering. I map identities durably, block contact creation until its parent mapping exists, and track Salesforce sequence by field. I never compare a Salesforce sequence to a portal version directly. The inbox represents incoming events; the outbox represents logical obligations, while a separate attempts table records each actual remote request.”

## 4:30–6:00 — Conflicts, idempotency, and loop prevention

“Different-field changes merge. Known sequential same-field edits follow causality. Truly concurrent same-field edits use a provisional business-approved field-authority policy; unknown causality is quarantined, not guessed. Every logical edit keeps an immutable audit change set, including losing conflict evidence. Origin and correlation evidence prevent an inbound replication or remote echo from bouncing back indefinitely. Value equality alone is insufficient to identify an echo.”

## 6:00–8:00 — Failures, recovery, and capacity

“An accepted portal write remains in the outbox through outages. We operate provisionally at 90 of 100 Salesforce API requests per second, with weighted-fair live/recovery/retry scheduling. At 25 portal edits per second, a six-hour outage produces 540,000 logical obligations. If exactly one API call is needed per obligation, 50 backlog requests per second would take three hours in an ideal lower-bound model; real recovery also needs historical reads, verification, retries, and dependency handling. We retrieve historical changes with overlap, atomically checkpoint each ingested page, reconcile through the inbox, and release outbound barriers only with sufficient completeness evidence. Ambiguous remote writes are verified before unsafe retries.”

## 8:00–9:00 — Monitoring and SLA honesty

“Three primary metrics: end-to-end latency warns at 20 seconds and is critical at 30; oldest unresolved obligation warns at 15 seconds and is critical at 30; unresolved correctness exceptions warn at one and are critical at ten or any confirmed corruption. The healthy 30-second stage budgets are illustrative, not verified worst-case guarantees. Outages, per-record FIFO stalls, and silently missing webhook visibility can break the deadline.”

## 9:00–10:00 — Trade-offs and next validation

“The architecture prioritizes durability and auditable correctness over falsely claiming distributed exactly-once execution. Before committing to production guarantees I would verify Salesforce historical completeness, event identity, ordering, safe upserts, causal evidence and worst-case API latency; specify durable lane ownership; and obtain business approval for field authority. The system is designed to recover without silently dropping accepted edits, while explicitly documenting what cannot yet be guaranteed.”

## Likely follow-up questions

**Why not update Salesforce synchronously from the portal request?** The portal would become dependent on Salesforce availability and could lose reliable retry evidence. Atomic local edit + outbox provides durable acceptance and controlled retries.

**Why not just use timestamps for conflicts?** Clock skew and network delay do not prove causality. Use source ordering and causal baselines; reconcile when evidence is insufficient.

**Can PostgreSQL guarantee exactly once in Salesforce?** No. Remote calls are outside PostgreSQL transactions; retry-safe external IDs, verification and idempotency provide practical safety under verified contracts.

**How do you avoid overlapping writes on one record?** Per-record lane ownership, earliest-unresolved obligation gating, durable attempts and blocking ambiguous outcomes; exact implementation remains to be specified.

**Can you guarantee 30 seconds?** Not during a six-hour outage, and not without verified healthy-operation worst-case bounds.
