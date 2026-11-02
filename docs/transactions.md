# D4 — Five Critical Transaction Workflows (Pseudocode)

**Status:** Proposed implementation pseudocode derived from D1, not executable code. The Salesforce ordering, causal-evidence, retry-safe upsert and worker-lane contracts are unverified dependencies. All external calls happen **outside** PostgreSQL transactions.

## T1 — Portal create/update, audit, outbox and idempotency (atomic)

```text
BEGIN;
  INSERT idempotency reservation / lock existing scoped key;
  IF existing completed key THEN
    IF request hash differs THEN reject reuse;
    ELSE return persisted original response after transaction;
  END IF;
  SELECT business row FOR UPDATE (for updates);
  IF expected portal_version != stored portal_version THEN
    persist deterministic 409 response for this idempotency key; COMMIT; return 409;
  END IF;
  validate parent and changed fields;
  INSERT or UPDATE business row; increment portal_version;
  INSERT audit_history(logical_edit_id, full available changed-field old/new set);
  INSERT salesforce_outbox(object_type, portal_id, portal_version, changed_fields,
                          origin_key, status='PENDING');
  persist original HTTP response status/body in portal_idempotency_records;
COMMIT;
return persisted response;
```

The reservation and concurrent same-key behavior must be implemented with a concrete transaction-safe mechanism. Accepted changes never exist without their audit and outbound obligation.

## T2 — Webhook or historical-event durable ingestion (atomic)

```text
validate source authentication and payload; derive canonical event identity;
BEGIN;
  INSERT salesforce_inbox(event_id, payload_hash, raw_payload, changed_fields,
                         source_order, status='PENDING') ON CONFLICT DO NOTHING;
  IF event identity exists AND payload hash differs THEN
     record integrity exception / quarantine evidence; COMMIT; return error;
  END IF;
  -- for historical pages only: update recovery_checkpoints to next durable cursor
  -- in the SAME transaction as inserting all page events;
COMMIT;
return webhook 2xx only after commit; -- never means business application completed
```

Historical checkpoint advancement proves durable ingestion, not processing or completeness. Live and historical event identity must match under a verified contract.

## T3 — Inbound worker apply, reconcile and audit (atomic)

```text
claim eligible inbox item using SKIP LOCKED + durable lease token (short transaction);
BEGIN;
  verify lease token and unexpired ownership;
  resolve stable Salesforce-to-portal mapping or mark dependency unresolved;
  SELECT business row FOR UPDATE;
  lock changed field_sync_state rows in deterministic order;
  FOR EACH changed field:
    compare source sequence using VERIFIED Salesforce ordering contract;
    evaluate cross-system causal baseline, not only source sequence;
    IF established stale or duplicate THEN skip business effect;
    ELSE IF independent/sequential THEN apply eligible value;
    ELSE IF genuinely concurrent THEN apply approved field authority,
         append separate conflict-resolution evidence;
    ELSE mark field unresolved and require reconciliation;
  END FOR;
  append one immutable audit edit with all available changed-field evidence;
  update field sync state, business version as appropriate and inbox status;
  DO NOT generate an ordinary outbound obligation for Salesforce-origin application;
COMMIT;
```

If the worker crashes before commit, business, audit and completion roll back together. Do not invent old values missing from Salesforce evidence.

## T4 — Outbound worker, external call, and fenced confirmation

```text
BEGIN;
  claim earliest unresolved per-record obligation with SKIP LOCKED;
  acquire durable per-record lane ownership; verify no earlier ambiguous/in-flight call;
  ensure confirmed parent Salesforce mapping for contact creation;
  write attempt record with exact outbound payload, request identity, and lease token;
COMMIT;

acquire token from global weighted-fair Salesforce limiter (all calls count);
CALL Salesforce external-ID upsert/update OUTSIDE transaction;
IF response is ambiguous:
  mark attempt/obligation AMBIGUOUS in a fenced DB transaction;
  block record lane; verify outcome through supported Salesforce mechanism;
  DO NOT blindly retry or send later record versions;
END IF;

BEGIN;
  verify current lane ownership / lease fencing;
  persist actual response/verification evidence on attempt;
  insert or validate Salesforce identity mapping;
  update confirmed_outbound_fields from ACTUAL SENT payload, monotonically;
  mark obligation CONFIRMED and release lane when safe;
COMMIT;
```

A database fence does **not** cancel an already in-flight remote request. Exact lane ownership and ambiguous-outcome reconciliation are outstanding implementation dependencies.

## T5 — Six-hour outage historical recovery and safe backlog drain

```text
record recovery window, overlap and high-water mark; activate appropriate barriers;
WHILE historical pages remain:
  use shared Salesforce limiter to fetch page OUTSIDE DB transaction;
  BEGIN;
    insert page events into normal inbox with canonical event deduplication;
    advance checkpoint only if entire page is durably stored;
  COMMIT;
END WHILE;
process historical events through T3; resolve identity, causal and ordering gaps;
FOR EACH affected record:
  IF historical completeness AND relevant parent/causal dependencies proven THEN
    durably release that record's recovery barrier;
  ELSE retain barrier, create recovery obligation and quarantine evidence;
END FOR;
resume T4 FIFO lanes for safely released records;
monitor outstanding age, latency and unresolved correctness exceptions;
```

**Never** infer history completeness from a checkpoint alone. The 30-second end-to-end SLA cannot be satisfied during the outage and is not guaranteed while recovering.

## Cross-transaction invariants

1. A successful portal edit commits business, audit, idempotency response and outbound obligation together.
2. Webhook `2xx` follows a committed inbox write.
3. An external Salesforce request is never inside a PostgreSQL transaction.
4. The same logical edit is not re-applied because of retry or cross-channel replay.
5. Source sequence and portal version are never directly compared as one global version.
6. Outbound confirmation uses the actual sent payload and durable acceptance evidence.
7. Ambiguous writes and unproven recovery completeness block unsafe replay.
8. All losing and unresolved edits retain available audit evidence.
