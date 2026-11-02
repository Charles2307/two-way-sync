# Architecture

The design has three main flows:

1. **Salesforce to portal:** The webhook API validates events, stores them in a durable inbox, and acknowledges only after the database commit. Inbound workers apply changes in PostgreSQL transactions.
2. **Portal to Salesforce:** Portal edits and outbound obligations are recorded atomically. Outbound workers process each record in order and share a Salesforce API rate limiter.
3. **Recovery:** Recovery workers retrieve Salesforce history with overlapping checkpoints, persist it, and track completeness so missing or unresolved events remain visible.

PostgreSQL stores business data, identity mappings, inbox and outbox records, confirmed outbound values, audit history, idempotency results, and recovery state.
