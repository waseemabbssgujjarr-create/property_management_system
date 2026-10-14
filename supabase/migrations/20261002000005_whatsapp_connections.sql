-- ============================================================
-- MUNSHI — WhatsApp Connections (Our Own WA API)
-- Version: 1.1 | Date: 2026-10-13
--
-- Architecture:
--   Munshi → Our WhatsApp API → WhatsApp
--
-- Each dealer has one whatsapp_connection record linking their
-- dealer account to a connection in our WhatsApp API platform.
-- The API key and webhook secret are stored as pgcrypto bytea —
-- never returned to Flutter clients.
--
-- Security model:
--   - api_key_encrypted / webhook_secret_encrypted are bytea columns.
--     pgp_sym_encrypt() returns bytea; storing as bytea avoids the
--     silent implicit cast that truncates non-UTF-8 ciphertext when
--     text columns are used.
--   - authenticated clients receive only safe metadata columns via
--     a column-level GRANT that omits both credential columns.
--   - RLS alone is NOT relied on to hide columns; the GRANT is the
--     enforcement layer, RLS is the row-filter layer.
--   - All writes to credential columns go through store_wa_credentials()
--     (SECURITY DEFINER, service_role only). No client INSERT policy.
--   - Disconnect (status update) is the only client-writable UPDATE,
--     restricted to exactly the four columns needed.
--
-- Credentials NEVER stored in:
--   - Flutter source code
--   - .env files shipped in APK
--   - client-readable columns or SELECT grants
--   - logs or audit log plaintext
-- ============================================================

-- Enable pgcrypto if not already enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Main connections table ─────────────────────────────────────────────────

CREATE TABLE whatsapp_connections (
  id                       uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id                uuid        NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  office_id                uuid        REFERENCES offices(id),

  -- Connection identity (from our WA API)
  connection_id            text        NOT NULL,
  api_base_url             text        NOT NULL DEFAULT 'https://api.ourwhatsapp.example.com/v1',

  -- Credentials — stored as raw pgcrypto bytea, NEVER returned to clients.
  -- pgp_sym_encrypt() returns bytea; using bytea columns avoids the implicit
  -- ::text cast that silently corrupts non-UTF-8 binary ciphertext.
  api_key_encrypted        bytea       NOT NULL,
  webhook_secret_encrypted bytea       NOT NULL,

  -- Metadata (safe to return to clients)
  phone_number             text,           -- e.g. +923001234567
  display_name             text,           -- e.g. "Al-Hamid Properties"
  status                   text        NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','connecting','active','disconnected','error')),
  error_message            text,           -- last error, if any (non-sensitive)

  -- Health tracking
  last_health_check_at     timestamptz,
  last_webhook_at          timestamptz,
  last_message_sent_at     timestamptz,

  -- Audit
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  created_by               uuid        REFERENCES users(id),
  updated_by               uuid        REFERENCES users(id),
  disconnected_at          timestamptz,

  -- One active connection per dealer (can have history via soft disconnect)
  CONSTRAINT uq_dealer_active_connection UNIQUE (dealer_id, connection_id)
);

CREATE TRIGGER wa_connections_updated_at
  BEFORE UPDATE ON whatsapp_connections
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ── Webhook events log (idempotency) ─────────────────────────────────────

CREATE TABLE wa_webhook_events (
  -- INSERT-ONLY: idempotency + audit trail of all inbound webhooks
  id                uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id         uuid        NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  connection_id     text        NOT NULL,
  event_id          text        NOT NULL,     -- provider's event/message ID
  event_type        text        NOT NULL,     -- 'message_in'|'status_update'|'read'|etc.
  raw_payload       jsonb,                    -- sanitized; no secrets
  processed         boolean     NOT NULL DEFAULT false,
  processed_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Idempotency: same event_id + dealer never processed twice
  CONSTRAINT uq_wa_event_idempotency UNIQUE (dealer_id, event_id)
);

-- ── Outbound message queue ─────────────────────────────────────────────────

CREATE TABLE wa_outbound_queue (
  id                uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id         uuid        NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  connection_id     text        NOT NULL,
  party_id          uuid        REFERENCES parties(id),
  deal_id           uuid        REFERENCES deals(id),

  -- Message content
  to_phone          text        NOT NULL,
  message_type      text        NOT NULL DEFAULT 'text'
                      CHECK (message_type IN ('text','template','media')),
  message_body      text,
  template_name     text,
  template_vars     jsonb,
  media_url         text,

  -- Idempotency
  idempotency_key   text        NOT NULL UNIQUE,

  -- Status tracking
  status            text        NOT NULL DEFAULT 'queued'
                      CHECK (status IN ('queued','sending','sent','delivered','read','failed','cancelled')),
  provider_msg_id   text,           -- ID returned by our WA API
  error_message     text,
  retry_count       int         NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
  max_retries       int         NOT NULL DEFAULT 3,
  next_retry_at     timestamptz,

  -- Metadata
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  sent_at           timestamptz,
  delivered_at      timestamptz,
  read_at           timestamptz
);

CREATE TRIGGER wa_outbound_updated_at
  BEFORE UPDATE ON wa_outbound_queue
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE INDEX idx_wa_outbound_status     ON wa_outbound_queue (dealer_id, status, next_retry_at)
  WHERE status IN ('queued','failed');
CREATE INDEX idx_wa_outbound_connection ON wa_outbound_queue (connection_id);

-- ── Indexes ────────────────────────────────────────────────────────────────

CREATE INDEX idx_wa_connections_dealer    ON whatsapp_connections (dealer_id);
CREATE INDEX idx_wa_connections_status    ON whatsapp_connections (status);
CREATE INDEX idx_wa_webhook_events_dealer ON wa_webhook_events (dealer_id, created_at DESC);
CREATE INDEX idx_wa_webhook_unprocessed   ON wa_webhook_events (dealer_id, processed)
  WHERE processed = false;

-- ── RLS ────────────────────────────────────────────────────────────────────

ALTER TABLE whatsapp_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE wa_webhook_events    ENABLE ROW LEVEL SECURITY;
ALTER TABLE wa_outbound_queue    ENABLE ROW LEVEL SECURITY;

-- ── Privileges: REVOKE defaults, then GRANT minimum required ────────────────
--
-- Supabase's default privileges grant ALL (SELECT, INSERT, UPDATE, DELETE)
-- on every new table in the public schema to anon, authenticated, and
-- service_role. Column-level GRANTs are additive — they do NOT override
-- the table-level ALL. Without an explicit REVOKE, authenticated can still
-- SELECT api_key_encrypted through the table-level privilege.
--
-- The fix: REVOKE ALL first, then GRANT only the minimum required:
--   - whatsapp_connections: column-level SELECT (safe cols only) +
--     column-level UPDATE (disconnect cols only). No INSERT/DELETE.
--   - wa_webhook_events: NO access for authenticated. All operations are
--     service_role only (INSERT events, SELECT for idempotency, UPDATE to
--     mark processed). Payloads contain phone numbers and message bodies.
--   - wa_outbound_queue: SELECT + INSERT. UPDATE is service_role (via RLS).
--   - anon: no access on any WA table.
--   - service_role: implicit as table owner (postgres role), no GRANT needed.

-- ── whatsapp_connections ──────────────────────────────────────────────────
-- Revoke all default table-level privileges from client roles and PUBLIC.
-- PUBLIC is a pseudo-role that all roles inherit from; if any grant to
-- PUBLIC exists (from another migration or manual SQL), anon and
-- authenticated would inherit it, bypassing the column-level restrictions.
REVOKE ALL ON whatsapp_connections FROM PUBLIC;
REVOKE ALL ON whatsapp_connections FROM anon;
REVOKE ALL ON whatsapp_connections FROM authenticated;

-- Grant SELECT on safe metadata columns only.
-- api_key_encrypted and webhook_secret_encrypted are intentionally omitted —
-- they will not appear in any client query even if SELECT * is issued.
GRANT SELECT (
  id,
  dealer_id,
  office_id,
  connection_id,
  api_base_url,
  phone_number,
  display_name,
  status,
  error_message,
  last_health_check_at,
  last_webhook_at,
  last_message_sent_at,
  created_at,
  updated_at,
  created_by,
  disconnected_at
) ON whatsapp_connections TO authenticated;

-- Grant UPDATE on disconnect columns only.
-- The Flutter disconnect() workflow updates exactly these four columns.
-- api_key_encrypted, webhook_secret_encrypted, connection_id, dealer_id
-- are excluded — clients cannot overwrite credentials or change ownership.
GRANT UPDATE (
  status,
  disconnected_at,
  updated_by,
  error_message
) ON whatsapp_connections TO authenticated;

-- No INSERT or DELETE grant to authenticated:
-- All inserts go through store_wa_credentials() (SECURITY DEFINER,
-- service_role), which bypasses RLS and has owner privileges.
-- Granting INSERT would allow clients to write raw unencrypted values
-- directly into the credential columns.

-- ── wa_webhook_events ──────────────────────────────────────────────────────
-- This table is INSERT-only from service_role (webhook processor).
-- Authenticated clients have no access: webhook payloads contain phone numbers,
-- message bodies, and provider event IDs that must not be exposed to the client.
-- The webhook handler (wa-webhook Edge Function) uses service_role for all
-- reads, inserts, and status updates — it never uses the authenticated client.
REVOKE ALL ON wa_webhook_events FROM PUBLIC;
REVOKE ALL ON wa_webhook_events FROM anon;
REVOKE ALL ON wa_webhook_events FROM authenticated;
-- No GRANT to authenticated: service_role has implicit owner-level access.

-- ── wa_outbound_queue ──────────────────────────────────────────────────────
-- Revoke all defaults, then grant SELECT (table-level) + INSERT (column-level).
-- UPDATE is service_role only (delivery status updates from webhook processor).
-- DELETE is not granted to any client role.
REVOKE ALL ON wa_outbound_queue FROM PUBLIC;
REVOKE ALL ON wa_outbound_queue FROM anon;
REVOKE ALL ON wa_outbound_queue FROM authenticated;

-- Table-level SELECT is safe — no credential columns on this table.
GRANT SELECT ON wa_outbound_queue TO authenticated;

-- Column-level INSERT: clients may queue messages but cannot set
-- delivery-status fields (status, provider_msg_id, error_message,
-- retry_count, max_retries, next_retry_at, sent_at, delivered_at, read_at).
-- Those columns have database defaults or are nullable, so omitted
-- columns are initialized by PostgreSQL without client input.
GRANT INSERT (
  dealer_id,
  connection_id,
  party_id,
  deal_id,
  to_phone,
  message_type,
  message_body,
  template_name,
  template_vars,
  media_url,
  idempotency_key
) ON wa_outbound_queue TO authenticated;

-- ── RLS policies on whatsapp_connections ──────────────────────────────────

-- Row-level filter: authenticated clients see only their own dealer's rows.
-- Column-level restriction is enforced by the GRANT above.
CREATE POLICY "wa_connections_select" ON whatsapp_connections FOR SELECT
  USING (dealer_id = auth.dealer_id());

-- Disconnect-only UPDATE: owner/manager can update status to 'disconnected'.
-- Column-level GRANT already restricts which columns can be written;
-- this policy adds the row-ownership and role check.
-- The WITH CHECK prevents re-activating a connection from the client
-- (only service_role / store_wa_credentials can set status = 'active').
CREATE POLICY "wa_connections_disconnect" ON whatsapp_connections FOR UPDATE
  USING (
    dealer_id = auth.dealer_id()
    AND auth.current_role() IN ('owner', 'manager')
  )
  WITH CHECK (
    dealer_id = auth.dealer_id()
    AND status IN ('disconnected', 'error')
  );

-- No INSERT policy for authenticated: creates via store_wa_credentials() only.

-- wa_webhook_events: all access is service_role only.
-- INSERT: service_role only (webhook processor writes events).
-- SELECT/UPDATE: service_role only (idempotency check and mark-processed).
-- Authenticated clients have no access — webhook payloads are server-internal.
CREATE POLICY "wa_webhook_insert" ON wa_webhook_events FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- No SELECT policy for authenticated: service_role bypasses RLS entirely.
-- Authenticated clients cannot read webhook events regardless of dealer_id.

-- wa_outbound_queue: tenant-scoped; authenticated clients can queue messages
CREATE POLICY "wa_outbound_select" ON wa_outbound_queue FOR SELECT
  USING (dealer_id = auth.dealer_id());

CREATE POLICY "wa_outbound_insert" ON wa_outbound_queue FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());

-- Delivery status updates are service-role only (webhook processor)
CREATE POLICY "wa_outbound_update_service" ON wa_outbound_queue FOR UPDATE
  USING (auth.role() = 'service_role');

-- ── Secure credential retrieval (service_role Edge Functions only) ─────────
--
-- get_wa_credentials() decrypts api_key and webhook_secret for use in
-- Edge Functions (wa-send, wa-health-check, wa-webhook).
-- The columns are already bytea; no ::bytea cast is needed.

CREATE OR REPLACE FUNCTION get_wa_credentials(
  p_dealer_id     uuid,
  p_connection_id text
)
RETURNS TABLE (
  api_base_url   text,
  api_key        text,   -- decrypted plaintext
  webhook_secret text,   -- decrypted plaintext
  phone_number   text,
  display_name   text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enc_key text;
BEGIN
  v_enc_key := current_setting('app.wa_credential_key', true);

  IF v_enc_key IS NULL OR v_enc_key = '' THEN
    RAISE EXCEPTION
      'WA credential key not configured. '
      'Set app.wa_credential_key via Supabase Dashboard → '
      'Project Settings → Database → Configuration → Extra options, '
      'or via: ALTER ROLE authenticator SET app.wa_credential_key = ''...'';';
  END IF;

  RETURN QUERY
  SELECT
    wc.api_base_url,
    pgp_sym_decrypt(wc.api_key_encrypted,        v_enc_key)::text,
    pgp_sym_decrypt(wc.webhook_secret_encrypted, v_enc_key)::text,
    wc.phone_number,
    wc.display_name
  FROM whatsapp_connections wc
  WHERE wc.dealer_id     = p_dealer_id
    AND wc.connection_id = p_connection_id
    AND wc.status        = 'active';
END;
$$;

REVOKE ALL ON FUNCTION get_wa_credentials(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_wa_credentials(uuid, text) FROM authenticated;
REVOKE ALL ON FUNCTION get_wa_credentials(uuid, text) FROM anon;
GRANT  EXECUTE ON FUNCTION get_wa_credentials(uuid, text) TO service_role;

-- ── Credential storage (called from wa-connect Edge Function only) ─────────
--
-- store_wa_credentials() is the only path that writes to the credential
-- columns. It runs as SECURITY DEFINER under service_role.
-- pgp_sym_encrypt() returns bytea; no cast required for bytea columns.

CREATE OR REPLACE FUNCTION store_wa_credentials(
  p_dealer_id      uuid,
  p_connection_id  text,
  p_api_base_url   text,
  p_api_key        text,    -- plaintext — encrypted inside this function
  p_webhook_secret text,    -- plaintext — encrypted inside this function
  p_phone_number   text  DEFAULT NULL,
  p_display_name   text  DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enc_key text;
  v_new_id  uuid;
BEGIN
  v_enc_key := current_setting('app.wa_credential_key', true);

  IF v_enc_key IS NULL OR v_enc_key = '' THEN
    RAISE EXCEPTION 'WA credential key not configured. See get_wa_credentials for setup instructions.';
  END IF;

  INSERT INTO whatsapp_connections (
    dealer_id, connection_id, api_base_url,
    api_key_encrypted,                    webhook_secret_encrypted,
    phone_number, display_name, status
  ) VALUES (
    p_dealer_id, p_connection_id, p_api_base_url,
    pgp_sym_encrypt(p_api_key,        v_enc_key),   -- bytea, no cast needed
    pgp_sym_encrypt(p_webhook_secret, v_enc_key),   -- bytea, no cast needed
    p_phone_number, p_display_name, 'active'
  )
  ON CONFLICT (dealer_id, connection_id) DO UPDATE SET
    api_key_encrypted        = pgp_sym_encrypt(p_api_key,        v_enc_key),
    webhook_secret_encrypted = pgp_sym_encrypt(p_webhook_secret, v_enc_key),
    api_base_url             = p_api_base_url,
    phone_number             = COALESCE(p_phone_number, whatsapp_connections.phone_number),
    display_name             = COALESCE(p_display_name, whatsapp_connections.display_name),
    status                   = 'active',
    updated_at               = now()
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION store_wa_credentials(uuid, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION store_wa_credentials(uuid, text, text, text, text, text, text) FROM authenticated;
REVOKE ALL ON FUNCTION store_wa_credentials(uuid, text, text, text, text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION store_wa_credentials(uuid, text, text, text, text, text, text) TO service_role;

-- ── Table comments ─────────────────────────────────────────────────────────

COMMENT ON TABLE whatsapp_connections IS
  'WA API connections per dealer. '
  'api_key_encrypted and webhook_secret_encrypted are bytea — pgcrypto output. '
  'Never returned to Flutter clients: omitted from column-level GRANT to authenticated.';
COMMENT ON COLUMN whatsapp_connections.api_key_encrypted IS
  'pgp_sym_encrypt(api_key, app.wa_credential_key) — bytea. Service_role only.';
COMMENT ON COLUMN whatsapp_connections.webhook_secret_encrypted IS
  'pgp_sym_encrypt(webhook_secret, app.wa_credential_key) — bytea. Service_role only.';
COMMENT ON TABLE wa_webhook_events IS
  'Idempotency log for inbound webhooks from our WA API. '
  'All access is service_role only — authenticated clients have no SELECT or INSERT. '
  'Payloads contain phone numbers and message content (server-internal only).';
COMMENT ON TABLE wa_outbound_queue IS
  'Outbound message queue with delivery status tracking.';
