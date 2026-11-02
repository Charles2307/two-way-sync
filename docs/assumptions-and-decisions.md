# D2 — Architecture Diagram and Reading Notes

![Proposed bidirectional synchronization architecture](D2-architecture.png)

**Status:** Proposed logical architecture derived from locked D1. No Salesforce tenant integration has been verified.

**Inbound:** Salesforce webhook → validated durable `salesforce_inbox` → leased inbound worker → atomic business, per-field synchronization state, and immutable audit transaction. Historical replay uses the same inbox and event-identity contract.

**Outbound:** Portal request → single PostgreSQL transaction for business edit, audit, idempotency response, and `salesforce_outbox` obligation → per-record FIFO worker lane → shared Salesforce API limiter → external write/verification → fenced confirmation transaction. External API calls do not occur within PostgreSQL transactions.

**Recovery:** Historical source → page ingestion and checkpoint atomically → normal inbox reconciliation → completeness evidence and recovery-barrier release → safe outbound backlog drain. Historical completeness and stable cross-channel identity are unverified Salesforce dependencies.

**Shared controls:** Field-specific source ordering and cross-system causal evidence; confirmed outbound values (not attempted values); origin-aware loop suppression; retry/ambiguous-write evidence; global 90 req/s operating budget under a 100 req/s Salesforce cap.

**Important limitation:** 30-second end-to-end synchronization is impossible during a Salesforce outage and is not proven as a worst-case healthy-operation guarantee. Per-record FIFO lane ownership and Salesforce historical/API contracts require further specification.
