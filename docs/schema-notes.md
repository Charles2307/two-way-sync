# D3 — PostgreSQL schema notes

The accompanying `D3-schema.sql` is **proposed DDL**, not production-ready or a modification to locked D1. It starts with `customers`, `contacts`, and the two identity mapping tables, then defines the inbox, outbox, per-field state, confirmed outbound values, immutable-evidence structures, portal idempotency, delivery attempts, and recovery tables.

The D1 decisions retained include one audit entry per logical edit, separate confirmed outbound field tables, response status/body in portal idempotency records, and a many-to-many quarantine-to-obligation join table.

**Review before implementation:** Salesforce sequence comparison and canonical event identity; exact causal evidence; parent dependencies; per-record lane fencing across remote calls; reconciliation obligation identity versus the approved outbox uniqueness key; append-only permissions; and foreign-key integrity for polymorphic object references. The SQL intentionally does not claim to implement those behaviors merely by defining columns.

The schema is designed for review and is **not verified against a live PostgreSQL instance**.
