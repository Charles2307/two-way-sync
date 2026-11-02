# Salesforce–PostgreSQL Synchronization Design

This repository contains my system design for bidirectional synchronization between Salesforce CRM and the Tequity portal backed by PostgreSQL.

The design covers the 5-million-record scale, the 30-second synchronization target, Salesforce API limits, duplicate or out-of-order webhooks, missing events, and recovery after an outage.

## Contents

- `docs/assumptions-and-decisions.md` — assumptions and decisions
- `docs/architecture.png` — architecture diagram
- `docs/architecture.pdf` — printable architecture diagram
- `docs/architecture.dot` — editable diagram source
- `db/schema.sql` — proposed PostgreSQL schema
- `docs/schema-notes.md` — schema explanation
- `docs/transactions.md` — transaction flows
- `docs/failure-scenarios.md` — failure handling and recovery
- `docs/interview-walkthrough.md` — design walkthrough
- `docs/system-design.pdf` — supporting design document

## Contribution

This repository documents my system design and supporting materials. It does not claim application implementation work that I did not perform.
