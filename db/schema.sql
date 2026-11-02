-- D3: PROPOSED PostgreSQL DDL, derived from locked D1.
-- Not approved as executable implementation; review with product, Salesforce and DB owners.
-- Requires PostgreSQL with pgcrypto for gen_random_uuid().
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE customers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL,
 status text NOT NULL, owner text, portal_version bigint NOT NULL DEFAULT 1 CHECK (portal_version > 0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE contacts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), customer_id uuid NOT NULL REFERENCES customers(id),
 full_name text NOT NULL, phone text, email text, city text, owner text,
 portal_version bigint NOT NULL DEFAULT 1 CHECK (portal_version > 0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX contacts_customer_idx ON contacts(customer_id);

CREATE TABLE customer_identity_map (
 portal_id uuid PRIMARY KEY REFERENCES customers(id), salesforce_id text UNIQUE,
 mapping_status text NOT NULL CHECK (mapping_status IN ('PENDING','CONFIRMED','RECONCILIATION_REQUIRED')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (mapping_status <> 'CONFIRMED' OR salesforce_id IS NOT NULL)
);
CREATE TABLE contact_identity_map (
 portal_id uuid PRIMARY KEY REFERENCES contacts(id), salesforce_id text UNIQUE,
 mapping_status text NOT NULL CHECK (mapping_status IN ('PENDING','CONFIRMED','RECONCILIATION_REQUIRED')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (mapping_status <> 'CONFIRMED' OR salesforce_id IS NOT NULL)
);

CREATE TABLE salesforce_inbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), canonical_event_id text NOT NULL UNIQUE,
 object_type text NOT NULL CHECK (object_type IN ('CUSTOMER','CONTACT')),
 salesforce_id text NOT NULL, source_sequence text, occurred_at timestamptz,
 changed_by text, changed_fields jsonb NOT NULL, raw_payload jsonb NOT NULL,
 payload_hash text NOT NULL, intake_channel text NOT NULL CHECK (intake_channel IN ('WEBHOOK','HISTORY')),
 status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PROCESSING','PROCESSED','UNRESOLVED','RETRY')),
 attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0), next_attempt_at timestamptz NOT NULL DEFAULT now(),
 lease_token uuid, lease_expires_at timestamptz,
 received_at timestamptz NOT NULL DEFAULT now(), processed_at timestamptz
);
CREATE INDEX inbox_work_idx ON salesforce_inbox(next_attempt_at, received_at) WHERE status IN ('PENDING','RETRY');
CREATE INDEX inbox_record_idx ON salesforce_inbox(object_type, salesforce_id, occurred_at);

CREATE TABLE salesforce_outbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), object_type text NOT NULL CHECK (object_type IN ('CUSTOMER','CONTACT')),
 portal_id uuid NOT NULL, portal_version bigint NOT NULL CHECK (portal_version > 0),
 operation text NOT NULL CHECK (operation IN ('CREATE','UPDATE','RECONCILE')),
 changed_fields jsonb NOT NULL, origin_key text NOT NULL,
 status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PROCESSING','RETRY','AMBIGUOUS','BLOCKED','CONFIRMED','UNRESOLVED')),
 attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0), next_attempt_at timestamptz NOT NULL DEFAULT now(),
 lease_token uuid, lease_expires_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), confirmed_at timestamptz,
 UNIQUE(object_type, portal_id, portal_version)
);
CREATE INDEX outbox_fifo_idx ON salesforce_outbox(object_type, portal_id, portal_version);
CREATE INDEX outbox_work_idx ON salesforce_outbox(next_attempt_at, created_at) WHERE status IN ('PENDING','RETRY');
-- IMPORTANT: The unique key above assumes reconciliation is represented by a distinct
-- version/identity allocation. If reconciliation can share a portal_version, the D1
-- uniqueness contract must be reconciled before using this DDL in production.

CREATE TABLE customer_field_sync_state (
 portal_id uuid NOT NULL REFERENCES customers(id), field_name text NOT NULL,
 last_salesforce_sequence text, last_portal_version bigint, causal_baseline jsonb,
 resolution_status text NOT NULL DEFAULT 'CLEAR', updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(portal_id, field_name)
);
CREATE TABLE contact_field_sync_state (
 portal_id uuid NOT NULL REFERENCES contacts(id), field_name text NOT NULL,
 last_salesforce_sequence text, last_portal_version bigint, causal_baseline jsonb,
 resolution_status text NOT NULL DEFAULT 'CLEAR', updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(portal_id, field_name)
);
-- Source sequences are text until a verified Salesforce comparator is specified.
CREATE TABLE customer_confirmed_outbound_fields (
 portal_id uuid NOT NULL REFERENCES customers(id), field_name text NOT NULL,
 confirmed_value jsonb, confirmed_portal_version bigint NOT NULL,
 confirmation_evidence jsonb NOT NULL, confirmed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(portal_id, field_name)
);
CREATE TABLE contact_confirmed_outbound_fields (
 portal_id uuid NOT NULL REFERENCES contacts(id), field_name text NOT NULL,
 confirmed_value jsonb, confirmed_portal_version bigint NOT NULL,
 confirmation_evidence jsonb NOT NULL, confirmed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(portal_id, field_name)
);

CREATE TABLE audit_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), object_type text NOT NULL,
 portal_id uuid, salesforce_id text, logical_edit_id text NOT NULL UNIQUE,
 origin text NOT NULL, actor text, source_occurred_at timestamptz,
 change_set jsonb NOT NULL, -- one logical edit: all available field old/new values
 evidence jsonb NOT NULL DEFAULT '{}'::jsonb, recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_record_idx ON audit_history(object_type, portal_id, recorded_at);
CREATE TABLE conflict_resolution_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), object_type text NOT NULL,
 portal_id uuid, field_name text NOT NULL, competing_edit_ids jsonb NOT NULL,
 causal_evidence jsonb NOT NULL, chosen_value jsonb, losing_value jsonb,
 rule_used text NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now()
);
-- Append-only audit enforcement needs separate DB permissions/triggers in deployment.

CREATE TABLE portal_idempotency_records (
 scope text NOT NULL, idempotency_key text NOT NULL, request_hash text NOT NULL,
 response_status integer NOT NULL, response_body jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(scope, idempotency_key)
);
CREATE TABLE salesforce_outbound_attempts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), obligation_id uuid NOT NULL REFERENCES salesforce_outbox(id),
 attempt_number integer NOT NULL CHECK (attempt_number > 0),
 request_id text, actual_payload jsonb NOT NULL, sent_at timestamptz,
 completed_at timestamptz, response_evidence jsonb,
 outcome text NOT NULL CHECK (outcome IN ('PREPARED','SUCCEEDED','FAILED_TRANSIENT','FAILED_PERMANENT','AMBIGUOUS')),
 UNIQUE(obligation_id, attempt_number)
);

CREATE TABLE recovery_checkpoints (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), source_name text NOT NULL UNIQUE,
 durable_cursor text, run_status text NOT NULL, overlap_start timestamptz,
 high_watermark text, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE recovery_obligations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), object_type text, salesforce_id text,
 portal_id uuid, requirement text NOT NULL, status text NOT NULL DEFAULT 'OPEN',
 evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz
);
CREATE TABLE recovery_quarantine (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_id uuid REFERENCES salesforce_inbox(id),
 reason text NOT NULL, evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
 status text NOT NULL DEFAULT 'OPEN', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE recovery_quarantine_obligations (
 quarantine_id uuid NOT NULL REFERENCES recovery_quarantine(id),
 obligation_id uuid NOT NULL REFERENCES recovery_obligations(id),
 PRIMARY KEY(quarantine_id, obligation_id)
);
CREATE INDEX recovery_open_idx ON recovery_obligations(created_at) WHERE status = 'OPEN';

-- IMPLEMENTATION DEPENDENCIES (not claimed solved by these tables):
-- 1. Exact cross-system causal comparison, source-sequence comparator and event identity.
-- 2. Durable per-record lane ownership across lease expiry and in-flight Salesforce calls.
-- 3. Complete Salesforce historical source, external-ID upsert and verification contracts.
-- 4. Parent dependency gating, conflict winner propagation and recovery-barrier scheduler.
-- 5. Outbox uniqueness for reconciliation obligations sharing portal versions.
-- 6. Enforce append-only audit and referential object_type/portal_id integrity.
-- 7. Final indexes/partitioning/retention and migration plan after load testing.
