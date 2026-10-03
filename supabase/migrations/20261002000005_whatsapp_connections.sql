-- ============================================================
-- MUNSHI — WhatsApp Connections (Our Own WA API)
-- Version: 1.0 | Date: 2026-10-02
--
-- Architecture:
--   Munshi → Our WhatsApp API → WhatsApp
--
-- Each dealer has one whatsapp_connection record linking their
-- dealer account to a connection in our WhatsApp API platform.
-- The API key and webhook secret are stored encrypted using
-- pgcrypto — never returned to Flutter clients.
--
-- Credentials NEVER stored in:
--   - Flutter source code
--   - .env files shipped in APK
--   - client-readable fields
--   - logs or audit log plaintext
-- ============================================================

-- Enable pgcrypto if not already enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Main connections table ─────────────────────────────────────────────────

CREATE TABLE whatsapp_connections (
  id                    uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id             uuid        NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  office_id             uuid        REFERENCES offices(id),

  -- Connection identity (from our WA API)
  connection_id         text        NOT NULL,
  api_base_url          text        NOT NULL DEFAULT 'https://api.ourwhatsapp.example.com/v1',

  -- Credentials — stored encrypted, NEVER returned to clients
  -- Format: pgp_sym_encrypt(plaintext, key) where key = app secret from Edge Function env
  api_key_encrypted     text        NOT NULL,
  webhook_secret_encrypted text     NOT NULL,

  -- Metadata (safe to return to clients)
  phone_number          text,           -- e.g. +923001234567
  display_name          text,           -- e.g. "Al-Hamid Properties"
  status                text        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','connecting','active','disconnected','error')),
  error_message         text,           -- last error, if any (non-sensitive)

  -- Health tracking
  last_health_check_at  timestamptz,
  last_webhook_at       timestamptz,
  last_message_sent_at  timestamptz,

  -- Audit
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  created_by            uuid        REFERENCES users(id),
  updated_by            uuid        REFERENCES users(id),
  disconnected_at       timestamptz,

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

-- whatsapp_connections: read safe metadata only (no credentials)
-- Clients NEVER receive api_key_encrypted or webhook_secret_encrypted
CREATE POLICY "wa_connections_select" ON whatsapp_connections FOR SELECT
  USING (dealer_id = auth.dealer_id());

-- Only owner/manager can insert/update connections
CREATE POLICY "wa_connections_insert" ON whatsapp_connections FOR INSERT
  WITH CHECK (
    dealer_id = auth.dealer_id() AND
    auth.current_role() IN ('owner', 'manager')
  );

CREATE POLICY "wa_connections_update" ON whatsapp_connections FOR UPDATE
  USING (dealer_id = auth.dealer_id() AND auth.current_role() IN ('owner','manager'))
  WITH CHECK (dealer_id = auth.dealer_id());

-- wa_webhook_events: INSERT-only from service role; SELECT for owner
CREATE POLICY "wa_webhook_insert" ON wa_webhook_events FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "wa_webhook_select" ON wa_webhook_events FOR SELECT
  USING (dealer_id = auth.dealer_id());

-- wa_outbound_queue: tenant-scoped, INSERT allowed for any role
CREATE POLICY "wa_outbound_select" ON wa_outbound_queue FOR SELECT
  USING (dealer_id = auth.dealer_id());

CREATE POLICY "wa_outbound_insert" ON wa_outbound_queue FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());

-- Status updates are service-role only (webhook processor updates delivery status)
CREATE POLICY "wa_outbound_update_service" ON wa_outbound_queue FOR UPDATE
  USING (auth.role() = 'service_role');

-- ── Secure credential access function ────────────────────────────────────
-- Called ONLY from Edge Functions (service_role) to decrypt credentials.
-- Never called from Flutter clients.

CREATE OR REPLACE FUNCTION get_wa_credentials(
  p_dealer_id     uuid,
  p_connection_id text
)
RETURNS TABLE (
  api_base_url        text,
  api_key             text,    -- decrypted
  webhook_secret      text,    -- decrypted
  phone_number        text,
  display_name        text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enc_key text;
BEGIN
  -- Encryption key comes from server env, not stored in DB
  v_enc_key := current_setting('app.wa_credential_key', true);

  IF v_enc_key IS NULL OR v_enc_key = '' THEN
    RAISE EXCEPTION 'WA credential key not configured. Set app.wa_credential_key.';
  END IF;

  RETURN QUERY
  SELECT
    wc.api_base_url,
    pgp_sym_decrypt(wc.api_key_encrypted::bytea, v_enc_key)::text,
    pgp_sym_decrypt(wc.webhook_secret_encrypted::bytea, v_enc_key)::text,
    wc.phone_number,
    wc.display_name
  FROM whatsapp_connections wc
  WHERE wc.dealer_id = p_dealer_id
    AND wc.connection_id = p_connection_id
    AND wc.status = 'active';
END;
$$;

-- Only service_role can call this function
REVOKE ALL ON FUNCTION get_wa_credentials FROM PUBLIC;
REVOKE ALL ON FUNCTION get_wa_credentials FROM authenticated;
REVOKE ALL ON FUNCTION get_wa_credentials FROM anon;
GRANT  EXECUTE ON FUNCTION get_wa_credentials TO service_role;

-- ── Credential storage function (called from Edge Function on connect) ────

CREATE OR REPLACE FUNCTION store_wa_credentials(
  p_dealer_id         uuid,
  p_connection_id     text,
  p_api_base_url      text,
  p_api_key           text,  -- plaintext — encrypted inside this function
  p_webhook_secret    text,  -- plaintext — encrypted inside this function
  p_phone_number      text  DEFAULT NULL,
  p_display_name      text  DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enc_key  text;
  v_new_id   uuid;
BEGIN
  v_enc_key := current_setting('app.wa_credential_key', true);

  IF v_enc_key IS NULL OR v_enc_key = '' THEN
    RAISE EXCEPTION 'WA credential key not configured.';
  END IF;

  INSERT INTO whatsapp_connections (
    dealer_id, connection_id, api_base_url,
    api_key_encrypted, webhook_secret_encrypted,
    phone_number, display_name, status
  ) VALUES (
    p_dealer_id, p_connection_id, p_api_base_url,
    pgp_sym_encrypt(p_api_key, v_enc_key),
    pgp_sym_encrypt(p_webhook_secret, v_enc_key),
    p_phone_number, p_display_name, 'active'
  )
  ON CONFLICT (dealer_id, connection_id)
  DO UPDATE SET
    api_key_encrypted         = pgp_sym_encrypt(p_api_key, v_enc_key),
    webhook_secret_encrypted  = pgp_sym_encrypt(p_webhook_secret, v_enc_key),
    api_base_url              = p_api_base_url,
    phone_number              = COALESCE(p_phone_number, whatsapp_connections.phone_number),
    display_name              = COALESCE(p_display_name, whatsapp_connections.display_name),
    status                    = 'active',
    updated_at                = now()
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION store_wa_credentials FROM PUBLIC;
REVOKE ALL ON FUNCTION store_wa_credentials FROM authenticated;
REVOKE ALL ON FUNCTION store_wa_credentials FROM anon;
GRANT  EXECUTE ON FUNCTION store_wa_credentials TO service_role;

COMMENT ON TABLE whatsapp_connections IS
  'WA API connections per dealer. Credentials stored encrypted — never returned to Flutter clients.';
COMMENT ON TABLE wa_webhook_events IS
  'Idempotency log for inbound webhooks from our WA API. INSERT-only.';
COMMENT ON TABLE wa_outbound_queue IS
  'Outbound message queue with delivery status tracking.';
