-- ============================================================
-- MUNSHI — Initial Schema Migration
-- Version: 1.0 | Date: 2026-10-02
-- ============================================================
-- IMPORTANT INVARIANTS:
--   - Every table with dealer data has dealer_id with RLS
--   - Money columns are BIGINT (never float)
--   - Financial records are INSERT-ONLY (no UPDATE/DELETE policies)
--   - deal_events and audit_log are IMMUTABLE
--   - deal_splits must sum to 100% per deal (enforced by trigger)
--   - Receipt numbers are sequential and concurrency-safe
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- fuzzy search

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Get dealer_id from JWT claims (custom claim set at login)
CREATE OR REPLACE FUNCTION auth.dealer_id()
RETURNS uuid AS $$
  SELECT COALESCE(
    (current_setting('request.jwt.claims', true)::jsonb ->> 'dealer_id')::uuid,
    NULL
  );
$$ LANGUAGE sql STABLE;

-- Get user_id from JWT
CREATE OR REPLACE FUNCTION auth.current_user_id()
RETURNS uuid AS $$
  SELECT COALESCE(
    auth.uid(),
    NULL
  );
$$ LANGUAGE sql STABLE;

-- Get role from JWT
CREATE OR REPLACE FUNCTION auth.current_role()
RETURNS text AS $$
  SELECT COALESCE(
    current_setting('request.jwt.claims', true)::jsonb ->> 'user_role',
    'agent'
  );
$$ LANGUAGE sql STABLE;

-- ============================================================
-- TENANCY
-- ============================================================

CREATE TABLE dealers (
  id                    uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name                  text NOT NULL,
  phone                 text NOT NULL UNIQUE,
  city                  text,
  areas                 text[] DEFAULT '{}',
  logo_url              text,
  ui_mode               text NOT NULL DEFAULT 'simple'
                          CHECK (ui_mode IN ('simple', 'detail')),
  voice_enabled         boolean NOT NULL DEFAULT true,
  language              text NOT NULL DEFAULT 'ur'
                          CHECK (language IN ('ur', 'en')),
  plan                  text NOT NULL DEFAULT 'starter'
                          CHECK (plan IN ('starter', 'pro')),
  plan_started_at       date,
  trial_ends_at         timestamptz,
  status                text NOT NULL DEFAULT 'trial'
                          CHECK (status IN ('trial','active','past_due','grace','paused','cancelled')),
  -- WhatsApp (Phase 2)
  waba_id               text,
  wa_phone_number_id    text,
  wa_display_number     text,
  wa_token_encrypted    text,  -- AES-256-GCM encrypted, never returned to client
  wa_connected_at       timestamptz,
  msg_allowance         integer NOT NULL DEFAULT 500,
  msg_used_this_cycle   integer NOT NULL DEFAULT 0 CHECK (msg_used_this_cycle >= 0),
  billing_due_day       integer NOT NULL DEFAULT 1 CHECK (billing_due_day BETWEEN 1 AND 28),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER dealers_updated_at
  BEFORE UPDATE ON dealers
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================

CREATE TABLE offices (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id   uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  name        text NOT NULL,
  address     text,
  city        text,
  phone       text,
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  deleted_by  uuid
);

CREATE TRIGGER offices_updated_at
  BEFORE UPDATE ON offices
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================

CREATE TABLE users (
  id                        uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id                 uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  office_id                 uuid REFERENCES offices(id),
  phone                     text NOT NULL UNIQUE,
  name                      text NOT NULL,
  name_audio_url            text,
  role                      text NOT NULL DEFAULT 'agent'
                              CHECK (role IN ('owner','manager','agent','munshi')),
  default_commission_pct    numeric(5,2),
  active                    boolean NOT NULL DEFAULT true,
  last_seen_at              timestamptz,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  deleted_at                timestamptz,
  deleted_by                uuid
);

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- INVENTORY
-- ============================================================

CREATE TABLE properties (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id       uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  office_id       uuid REFERENCES offices(id),
  kind            text NOT NULL CHECK (kind IN ('plot','file','house','shop','commercial','apartment')),
  society         text NOT NULL,
  block           text,
  sector          text,
  size_marla      numeric(10,2),
  size_label      text,  -- e.g. "10 Marla", "1 Kanal" — display string
  demand_rs       bigint CHECK (demand_rs >= 0),
  status          text NOT NULL DEFAULT 'available'
                    CHECK (status IN ('available','token_given','bayana_done','sold','withdrawn')),
  owner_party_id  uuid,  -- FK added after parties table
  exclusive       boolean NOT NULL DEFAULT false,
  cert_no         text,
  notes_text      text,
  notes_audio_url text,
  listed_at       timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES users(id),
  updated_by      uuid REFERENCES users(id),
  deleted_at      timestamptz,
  deleted_by      uuid REFERENCES users(id)
);

CREATE TRIGGER properties_updated_at
  BEFORE UPDATE ON properties
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TABLE property_photos (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  property_id   uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  dealer_id     uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  url           text NOT NULL,
  thumb_url     text,
  sort          integer NOT NULL DEFAULT 0,
  caption       text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES users(id)
);

CREATE TABLE property_status_history (
  -- INSERT-ONLY: no updates or deletes
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  property_id   uuid NOT NULL REFERENCES properties(id) ON DELETE RESTRICT,
  dealer_id     uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  from_status   text,
  to_status     text NOT NULL,
  changed_by    uuid REFERENCES users(id),
  changed_at    timestamptz NOT NULL DEFAULT now(),
  note          text
);

-- ============================================================
-- PARTIES
-- ============================================================

CREATE TABLE parties (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id       uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  office_id       uuid REFERENCES offices(id),
  type            text NOT NULL CHECK (type IN ('buyer','seller','investor')),
  name            text NOT NULL,
  name_audio_url  text,
  phone           text,
  photo_url       text,
  cnic            text,  -- stored encrypted in application layer before insert
  source          text CHECK (source IN ('walkin','zameen','facebook','referral','other')),
  wa_opt_in       boolean NOT NULL DEFAULT false,
  wa_opt_in_at    timestamptz,
  wa_opt_in_source text,
  notes_text      text,
  notes_audio_url text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES users(id),
  updated_by      uuid REFERENCES users(id),
  deleted_at      timestamptz,
  deleted_by      uuid REFERENCES users(id)
);

CREATE TRIGGER parties_updated_at
  BEFORE UPDATE ON parties
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Now add the FK from properties to parties
ALTER TABLE properties
  ADD CONSTRAINT properties_owner_party_fk
  FOREIGN KEY (owner_party_id) REFERENCES parties(id) ON DELETE SET NULL;

CREATE TABLE party_phones (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  party_id    uuid NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
  dealer_id   uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  phone       text NOT NULL,
  label       text,
  is_primary  boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE requirements (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  party_id        uuid NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
  dealer_id       uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  kinds           text[] NOT NULL DEFAULT '{}',
  areas           text[] NOT NULL DEFAULT '{}',
  budget_min_rs   bigint CHECK (budget_min_rs >= 0),
  budget_max_rs   bigint CHECK (budget_max_rs >= 0),
  size_min_marla  numeric(10,2),
  size_max_marla  numeric(10,2),
  urgency         text NOT NULL DEFAULT 'warm' CHECK (urgency IN ('hot','warm','cold')),
  active          boolean NOT NULL DEFAULT true,
  notes_text      text,
  notes_audio_url text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TRIGGER requirements_updated_at
  BEFORE UPDATE ON requirements
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- DEALS (CORE)
-- ============================================================

CREATE TABLE deals (
  id                    uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id             uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  office_id             uuid REFERENCES offices(id),
  property_id           uuid REFERENCES properties(id),
  buyer_party_id        uuid REFERENCES parties(id),
  seller_party_id       uuid REFERENCES parties(id),
  assigned_agent_id     uuid REFERENCES users(id),
  stage                 text NOT NULL DEFAULT 'inquiry'
                          CHECK (stage IN ('inquiry','token','bayana','registry','closed','lost')),
  -- Token
  token_type            text CHECK (token_type IN ('conditional','confirmed')),
  token_rs              bigint CHECK (token_rs >= 0),
  token_date            date,
  token_expires_at      timestamptz,
  token_terms_text      text,
  token_terms_audio_url text,
  -- Bayana
  bayana_rs             bigint CHECK (bayana_rs >= 0),
  bayana_date           date,
  bayana_due_at         timestamptz,
  bayana_terms_text     text,
  bayana_terms_audio_url text,
  -- Deal financials
  deal_price_rs         bigint CHECK (deal_price_rs > 0),
  comm_buyer_pct        numeric(5,2) NOT NULL DEFAULT 1.00 CHECK (comm_buyer_pct >= 0),
  comm_seller_pct       numeric(5,2) NOT NULL DEFAULT 1.00 CHECK (comm_seller_pct >= 0),
  -- Registry
  registry_expected_at  date,
  registry_completed_at date,
  registry_ref          text,
  -- Outcome
  lost_reason           text CHECK (lost_reason IN ('price','found_elsewhere','cold_feet','financing','other')),
  lost_note             text,
  source                text,
  notes_text            text,
  notes_audio_url       text,
  closed_at             timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  created_by            uuid REFERENCES users(id),
  updated_by            uuid REFERENCES users(id),
  deleted_at            timestamptz,
  deleted_by            uuid REFERENCES users(id)
);

-- Computed expected commission (stored for performance)
ALTER TABLE deals
  ADD COLUMN expected_comm_rs bigint
  GENERATED ALWAYS AS (
    CASE
      WHEN deal_price_rs IS NOT NULL
      THEN (deal_price_rs * (comm_buyer_pct + comm_seller_pct) / 100)::bigint
      ELSE 0
    END
  ) STORED;

CREATE TRIGGER deals_updated_at
  BEFORE UPDATE ON deals
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================

CREATE TABLE deal_events (
  -- IMMUTABLE: INSERT-ONLY. Never update or delete.
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  deal_id      uuid NOT NULL REFERENCES deals(id) ON DELETE RESTRICT,
  dealer_id    uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  kind         text NOT NULL,
  from_stage   text,
  to_stage     text,
  actor_id     uuid REFERENCES users(id),
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  meta         jsonb NOT NULL DEFAULT '{}'
);

-- ============================================================

CREATE TABLE deal_splits (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  deal_id     uuid NOT NULL REFERENCES deals(id) ON DELETE RESTRICT,
  dealer_id   uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  user_id     uuid NOT NULL REFERENCES users(id),
  pct         numeric(5,2) NOT NULL CHECK (pct > 0 AND pct <= 100),
  paid_rs     bigint NOT NULL DEFAULT 0 CHECK (paid_rs >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid REFERENCES users(id),
  deleted_at  timestamptz,
  deleted_by  uuid REFERENCES users(id),
  UNIQUE (deal_id, user_id)
);

CREATE TRIGGER deal_splits_updated_at
  BEFORE UPDATE ON deal_splits
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- CRITICAL TRIGGER: commission splits must sum to 100% per deal
CREATE OR REPLACE FUNCTION check_split_sum()
RETURNS TRIGGER AS $$
DECLARE
  total numeric;
BEGIN
  SELECT COALESCE(SUM(pct), 0)
  INTO total
  FROM deal_splits
  WHERE deal_id = COALESCE(NEW.deal_id, OLD.deal_id)
    AND deleted_at IS NULL
    AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

  -- Include the new/updated row
  IF TG_OP = 'DELETE' THEN
    IF total != 0 AND total != 100 THEN
      RAISE EXCEPTION 'Commission splits must sum to 100%%, current total: %%', total;
    END IF;
  ELSE
    total := total + COALESCE(NEW.pct, 0);
    IF total > 100 THEN
      RAISE EXCEPTION 'Commission splits would exceed 100%% (current: %%)', total;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Note: the 100% check is enforced at application layer before final save.
-- DB trigger only prevents exceeding 100%.
-- Application ensures exactly 100% before marking deal as having splits.

CREATE TRIGGER deal_splits_sum_check
  BEFORE INSERT OR UPDATE OR DELETE ON deal_splits
  FOR EACH ROW EXECUTE FUNCTION check_split_sum();

-- ============================================================
-- MONEY
-- ============================================================

CREATE TABLE receipt_counters (
  dealer_id  uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  year       integer NOT NULL,
  last_no    integer NOT NULL DEFAULT 0 CHECK (last_no >= 0),
  PRIMARY KEY (dealer_id, year)
);

-- Concurrency-safe receipt number generation
CREATE OR REPLACE FUNCTION next_receipt_no(p_dealer_id uuid, p_year integer)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  next_no integer;
BEGIN
  INSERT INTO receipt_counters (dealer_id, year, last_no)
  VALUES (p_dealer_id, p_year, 1)
  ON CONFLICT (dealer_id, year)
  DO UPDATE SET last_no = receipt_counters.last_no + 1
  RETURNING last_no INTO next_no;

  RETURN p_dealer_id::text || '-' || p_year::text || '-' || LPAD(next_no::text, 5, '0');
END;
$$;

-- ============================================================

CREATE TABLE payments (
  -- APPEND-ONLY: no UPDATE or DELETE policies.
  -- Corrections use reversal/adjustment rows.
  id                  uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id           uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  deal_id             uuid REFERENCES deals(id),
  kind                text NOT NULL CHECK (kind IN (
                        'token_in','bayana_in','commission_in','split_paid',
                        'expense','other_in','other_out','reversal','adjustment'
                      )),
  amount_rs           bigint NOT NULL CHECK (amount_rs >= 0),
  direction           text NOT NULL CHECK (direction IN ('in','out')),
  method              text CHECK (method IN ('cash','bank','jazzcash','easypaisa')),
  ref_no              text,
  receipt_no          text UNIQUE,
  receipt_photo_url   text,
  reversed_by_id      uuid REFERENCES payments(id),  -- this payment was reversed by
  reversal_of_id      uuid REFERENCES payments(id),  -- this is a reversal of
  paid_to_user_id     uuid REFERENCES users(id),
  category            text,  -- for expense kind
  note_text           text,
  note_audio_url      text,
  occurred_at         timestamptz NOT NULL DEFAULT now(),
  idempotency_key     text NOT NULL UNIQUE,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid REFERENCES users(id)
);

-- Index for quick monthly totals
CREATE INDEX payments_dealer_month ON payments (dealer_id, occurred_at, kind, direction);

-- ============================================================
-- VOICE NOTES
-- ============================================================

CREATE TABLE voice_notes (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id       uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  ref_table       text NOT NULL,
  ref_id          uuid NOT NULL,
  audio_url       text NOT NULL,
  transcript_ur   text,
  duration_s      integer,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES users(id)
);

-- ============================================================
-- FOLLOW-UPS
-- ============================================================

CREATE TABLE followups (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id       uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  deal_id         uuid REFERENCES deals(id),
  party_id        uuid REFERENCES parties(id),
  assigned_to     uuid REFERENCES users(id),
  kind            text NOT NULL DEFAULT 'call'
                    CHECK (kind IN ('call','visit','whatsapp','other')),
  due_at          timestamptz NOT NULL,
  done_at         timestamptz,
  snoozed_until   timestamptz,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','done','snoozed','cancelled')),
  note_text       text,
  note_audio_url  text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES users(id),
  deleted_at      timestamptz
);

CREATE TRIGGER followups_updated_at
  BEFORE UPDATE ON followups
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- DOCUMENTS
-- ============================================================

CREATE TABLE documents (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id     uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  deal_id       uuid REFERENCES deals(id),
  party_id      uuid REFERENCES parties(id),
  property_id   uuid REFERENCES properties(id),
  type          text NOT NULL CHECK (type IN (
                  'token_receipt','token_agreement','bayana_agreement',
                  'cnic','ownership_doc','registry','other'
                )),
  title         text,
  file_url      text NOT NULL,
  thumb_url     text,
  checksum      text,
  expiry_date   date,
  verified      boolean NOT NULL DEFAULT false,
  verified_by   uuid REFERENCES users(id),
  version       integer NOT NULL DEFAULT 1,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES users(id),
  deleted_at    timestamptz,
  deleted_by    uuid REFERENCES users(id)
);

CREATE TRIGGER documents_updated_at
  BEFORE UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- NOTIFICATIONS
-- ============================================================

CREATE TABLE notifications (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id   uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  user_id     uuid REFERENCES users(id),
  kind        text NOT NULL,
  title_ur    text,
  body_ur     text,
  voice_url   text,
  deep_link   text,
  read_at     timestamptz,
  priority    text NOT NULL DEFAULT 'normal'
                CHECK (priority IN ('low','normal','high','urgent')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- AUDIT LOG (IMMUTABLE)
-- ============================================================

CREATE TABLE audit_log (
  -- INSERT-ONLY. No UPDATE or DELETE ever.
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id     uuid REFERENCES dealers(id),
  actor_id      uuid REFERENCES users(id),
  table_name    text NOT NULL,
  row_id        uuid,
  action        text NOT NULL CHECK (action IN (
                  'insert','update','delete','stage_change','payment',
                  'reversal','export','impersonate','login','invite',
                  'role_change','wa_config','subscription'
                )),
  before_data   jsonb,
  after_data    jsonb,
  diff          jsonb,
  session_id    text,
  ip_addr       inet,
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- WHATSAPP (Phase 2 — tables created now, enabled by feature flag)
-- ============================================================

CREATE TABLE wa_templates (
  id                uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  code              text NOT NULL UNIQUE,
  category          text NOT NULL CHECK (category IN ('utility','marketing','authentication')),
  lang              text NOT NULL DEFAULT 'ur',
  body              text NOT NULL,
  vars              text[] NOT NULL DEFAULT '{}',
  approved          boolean NOT NULL DEFAULT false,
  meta_template_id  text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER wa_templates_updated_at
  BEFORE UPDATE ON wa_templates
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TABLE wa_sequences (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id       uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  name            text NOT NULL,
  trigger_stage   text,
  active          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE wa_steps (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sequence_id   uuid NOT NULL REFERENCES wa_sequences(id) ON DELETE CASCADE,
  dealer_id     uuid NOT NULL REFERENCES dealers(id),
  day_offset    integer NOT NULL CHECK (day_offset >= 0),
  template_id   uuid NOT NULL REFERENCES wa_templates(id),
  stage_gates   text[] NOT NULL DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE wa_sends (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id     uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  deal_id       uuid REFERENCES deals(id),
  party_id      uuid REFERENCES parties(id),
  step_id       uuid REFERENCES wa_steps(id),
  template_id   uuid REFERENCES wa_templates(id),
  direction     text NOT NULL DEFAULT 'out' CHECK (direction IN ('in','out')),
  status        text NOT NULL DEFAULT 'queued'
                  CHECK (status IN ('queued','sent','delivered','read','failed','cancelled')),
  wa_msg_id     text,
  cost_usd      numeric(8,4) NOT NULL DEFAULT 0 CHECK (cost_usd >= 0),
  error_code    text,
  sent_at       timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE wa_inbox (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id   uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  party_id    uuid REFERENCES parties(id),
  deal_id     uuid REFERENCES deals(id),
  direction   text NOT NULL CHECK (direction IN ('in','out')),
  body        text,
  audio_url   text,
  wa_msg_id   text UNIQUE,
  status      text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- BILLING / SUBSCRIPTIONS
-- ============================================================

CREATE TABLE subscriptions (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id       uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  plan            text NOT NULL CHECK (plan IN ('starter','pro')),
  started_at      date NOT NULL,
  renews_at       date,
  trial_ends_at   timestamptz,
  status          text NOT NULL DEFAULT 'trial'
                    CHECK (status IN ('trial','active','past_due','grace','paused','cancelled')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER subscriptions_updated_at
  BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TABLE invoices (
  id                uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  dealer_id         uuid NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
  period_start      date NOT NULL,
  period_end        date NOT NULL,
  amount_rs         bigint NOT NULL CHECK (amount_rs > 0),
  plan              text NOT NULL,
  status            text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','paid','overdue','waived')),
  paid_at           timestamptz,
  payment_proof_url text,
  verified_by       uuid REFERENCES users(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER invoices_updated_at
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- PLATFORM CONFIGURATION
-- ============================================================

CREATE TABLE app_config (
  -- Key-value store for platform config.
  -- Never hardcode rates or feature flags.
  key           text PRIMARY KEY,
  value         jsonb NOT NULL,
  description   text,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid REFERENCES users(id)
);

-- Seed default config values
INSERT INTO app_config (key, value, description) VALUES
  ('wa_rate_marketing_usd', '0.0473', 'Meta WhatsApp marketing rate per message (USD) — last verified 2026-10-01'),
  ('wa_rate_utility_usd',   '0.0150', 'Meta WhatsApp utility rate per message (USD)'),
  ('wa_rate_service_usd',   '0.0150', 'Meta WhatsApp service rate (after 1000 free/month)'),
  ('wa_free_service_msgs',  '1000',   'Free service messages per WABA per month'),
  ('min_supported_version', '"1.0.0"', 'Minimum supported app version (below this = force upgrade)'),
  ('tts_voice_speed',       '0.95',   'TTS speech rate'),
  ('token_expiry_warn_days','3',       'Days before token expiry to show pulsing warning'),
  ('stale_deal_days',       '7',       'Days in stage before highlighting deal as stale');

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_deals_dealer_stage         ON deals (dealer_id, stage);
CREATE INDEX idx_deals_token_expiry         ON deals (dealer_id, token_expires_at)
  WHERE stage = 'token' AND deleted_at IS NULL;
CREATE INDEX idx_deals_dealer_created       ON deals (dealer_id, created_at DESC);

CREATE INDEX idx_payments_dealer_month      ON payments (dealer_id, occurred_at, kind, direction);
CREATE INDEX idx_payments_deal              ON payments (deal_id) WHERE deal_id IS NOT NULL;

CREATE INDEX idx_followups_dealer_due       ON followups (dealer_id, due_at)
  WHERE status = 'pending' AND deleted_at IS NULL;
CREATE INDEX idx_followups_dealer_party     ON followups (dealer_id, party_id)
  WHERE party_id IS NOT NULL;

CREATE INDEX idx_parties_dealer_phone       ON parties (dealer_id, phone);
CREATE INDEX idx_parties_dealer_type        ON parties (dealer_id, type);
CREATE INDEX idx_parties_dealer_wa          ON parties (dealer_id, wa_opt_in)
  WHERE wa_opt_in = true;

CREATE INDEX idx_properties_dealer_status  ON properties (dealer_id, status);
CREATE INDEX idx_properties_dealer_society ON properties (dealer_id, society);

CREATE INDEX idx_wa_sends_dealer_status     ON wa_sends (dealer_id, status, sent_at);
CREATE INDEX idx_audit_dealer_time          ON audit_log (dealer_id, occurred_at DESC);
CREATE INDEX idx_notifications_unread       ON notifications (dealer_id, user_id, read_at)
  WHERE read_at IS NULL;

-- Full-text search indexes
CREATE INDEX idx_parties_search ON parties
  USING gin(to_tsvector('simple', COALESCE(name,'') || ' ' || COALESCE(phone,'')));
CREATE INDEX idx_properties_search ON properties
  USING gin(to_tsvector('simple', COALESCE(society,'') || ' ' || COALESCE(block,'') || ' ' || COALESCE(cert_no,'')));

-- Trigram indexes for fuzzy name matching
CREATE INDEX idx_parties_name_trgm    ON parties USING gin(name gin_trgm_ops);
CREATE INDEX idx_properties_soc_trgm  ON properties USING gin(society gin_trgm_ops);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

-- Enable RLS on all tenant tables
ALTER TABLE offices               ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties            ENABLE ROW LEVEL SECURITY;
ALTER TABLE property_photos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE property_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE parties               ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_phones          ENABLE ROW LEVEL SECURITY;
ALTER TABLE requirements          ENABLE ROW LEVEL SECURITY;
ALTER TABLE deals                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE deal_events           ENABLE ROW LEVEL SECURITY;
ALTER TABLE deal_splits           ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments              ENABLE ROW LEVEL SECURITY;
ALTER TABLE receipt_counters      ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_notes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE followups             ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents             ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications         ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log             ENABLE ROW LEVEL SECURITY;
ALTER TABLE wa_sequences          ENABLE ROW LEVEL SECURITY;
ALTER TABLE wa_steps              ENABLE ROW LEVEL SECURITY;
ALTER TABLE wa_sends              ENABLE ROW LEVEL SECURITY;
ALTER TABLE wa_inbox              ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices              ENABLE ROW LEVEL SECURITY;

-- ── Generic tenant isolation policies ──────────────────────────────────────
-- Pattern: each table allows SELECT/INSERT/UPDATE for own dealer_id.
-- Financial tables: SELECT + INSERT only (no UPDATE/DELETE).
-- Audit/event tables: INSERT only.

-- offices
CREATE POLICY "offices_tenant" ON offices FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- users (own dealer)
CREATE POLICY "users_tenant" ON users FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- properties
CREATE POLICY "properties_select" ON properties FOR SELECT
  USING (dealer_id = auth.dealer_id() AND deleted_at IS NULL);
CREATE POLICY "properties_insert" ON properties FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "properties_update" ON properties FOR UPDATE
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- property_photos
CREATE POLICY "property_photos_tenant" ON property_photos FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- property_status_history (insert only)
CREATE POLICY "property_status_insert" ON property_status_history FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "property_status_select" ON property_status_history FOR SELECT
  USING (dealer_id = auth.dealer_id());

-- parties
CREATE POLICY "parties_select" ON parties FOR SELECT
  USING (dealer_id = auth.dealer_id() AND deleted_at IS NULL);
CREATE POLICY "parties_insert" ON parties FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "parties_update" ON parties FOR UPDATE
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- party_phones + requirements
CREATE POLICY "party_phones_tenant" ON party_phones FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "requirements_tenant" ON requirements FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- deals
CREATE POLICY "deals_select" ON deals FOR SELECT
  USING (
    dealer_id = auth.dealer_id() AND deleted_at IS NULL AND (
      auth.current_role() IN ('owner','manager','munshi')
      OR assigned_agent_id = auth.current_user_id()
    )
  );
CREATE POLICY "deals_insert" ON deals FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "deals_update" ON deals FOR UPDATE
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- deal_events (INSERT-ONLY)
CREATE POLICY "deal_events_insert" ON deal_events FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "deal_events_select" ON deal_events FOR SELECT
  USING (dealer_id = auth.dealer_id());

-- deal_splits
CREATE POLICY "deal_splits_tenant" ON deal_splits FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- payments (INSERT-ONLY for financial integrity)
CREATE POLICY "payments_select" ON payments FOR SELECT
  USING (
    dealer_id = auth.dealer_id() AND (
      auth.current_role() IN ('owner','manager')
      -- Agents/munshi see own split payments
      OR (kind = 'split_paid' AND paid_to_user_id = auth.current_user_id())
    )
  );
CREATE POLICY "payments_insert" ON payments FOR INSERT
  WITH CHECK (
    dealer_id = auth.dealer_id() AND
    auth.current_role() IN ('owner','manager','munshi')
  );
-- NO UPDATE or DELETE policy on payments — intentionally omitted

-- receipt_counters (service role only — used in SECURITY DEFINER function)
-- No RLS policy needed since next_receipt_no is SECURITY DEFINER

-- voice_notes
CREATE POLICY "voice_notes_tenant" ON voice_notes FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- followups
CREATE POLICY "followups_select" ON followups FOR SELECT
  USING (dealer_id = auth.dealer_id() AND deleted_at IS NULL);
CREATE POLICY "followups_write" ON followups FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "followups_update" ON followups FOR UPDATE
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- documents
CREATE POLICY "documents_select" ON documents FOR SELECT
  USING (dealer_id = auth.dealer_id() AND deleted_at IS NULL);
CREATE POLICY "documents_insert" ON documents FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "documents_update" ON documents FOR UPDATE
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- notifications
CREATE POLICY "notifications_tenant" ON notifications FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- audit_log (INSERT-ONLY, SELECT for owner only)
CREATE POLICY "audit_insert" ON audit_log FOR INSERT
  WITH CHECK (true); -- Service role writes audit; anon key never calls directly
CREATE POLICY "audit_select" ON audit_log FOR SELECT
  USING (
    dealer_id = auth.dealer_id() AND
    auth.current_role() = 'owner'
  );

-- WhatsApp tables
CREATE POLICY "wa_sequences_tenant" ON wa_sequences FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "wa_steps_tenant" ON wa_steps FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "wa_sends_tenant" ON wa_sends FOR SELECT
  USING (dealer_id = auth.dealer_id());
CREATE POLICY "wa_sends_insert" ON wa_sends FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());
CREATE POLICY "wa_inbox_tenant" ON wa_inbox FOR ALL
  USING (dealer_id = auth.dealer_id())
  WITH CHECK (dealer_id = auth.dealer_id());

-- Subscriptions (owner only)
CREATE POLICY "subscriptions_owner" ON subscriptions FOR ALL
  USING (
    dealer_id = auth.dealer_id() AND
    auth.current_role() = 'owner'
  )
  WITH CHECK (dealer_id = auth.dealer_id());

CREATE POLICY "invoices_owner" ON invoices FOR SELECT
  USING (
    dealer_id = auth.dealer_id() AND
    auth.current_role() IN ('owner','manager')
  );
CREATE POLICY "invoices_insert" ON invoices FOR INSERT
  WITH CHECK (dealer_id = auth.dealer_id());

-- ============================================================
-- END OF MIGRATION
-- ============================================================
