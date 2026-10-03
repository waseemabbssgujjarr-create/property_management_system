# DATABASE DESIGN — Munshi
**Version:** 1.0 | **Date:** 2026-10-02

---

## 1. Principles

- **BIGINT rupees** — never float/decimal for money. Store in paisa or full rupees as integer. All money columns: `bigint CHECK (value >= 0)`.
- **Multi-tenant via RLS** — every business table carries `dealer_id uuid NOT NULL REFERENCES dealers(id)`. RLS policy: `dealer_id = auth.dealer_id()` (custom claim).
- **Immutable financial records** — payments are never updated. Corrections use reversal/adjustment rows. `deal_events` is insert-only.
- **Audit trail on money fields** — every money-field change writes to `audit_log`.
- **Soft deletes** — business records use `deleted_at timestamptz / deleted_by uuid`. Financial records are never deleted.
- **Voice as first-class** — every human-entered text field has a `_audio_url text` companion.
- **UUID primary keys** — all tables use `uuid DEFAULT gen_random_uuid()`.

---

## 2. Standard Row Template

Every business table includes:
```sql
id            uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
dealer_id     uuid        NOT NULL REFERENCES dealers(id) ON DELETE RESTRICT,
created_at    timestamptz DEFAULT now() NOT NULL,
updated_at    timestamptz DEFAULT now() NOT NULL,
created_by    uuid        REFERENCES users(id),
updated_by    uuid        REFERENCES users(id),
deleted_at    timestamptz,
deleted_by    uuid        REFERENCES users(id)
```

---

## 3. Schema Groups

### 3.1 Tenancy

```sql
dealers
  id, name, phone (unique), city, areas text[],
  logo_url, ui_mode ('simple'|'detail') DEFAULT 'simple',
  voice_enabled bool DEFAULT true, language ('ur'|'en') DEFAULT 'ur',
  plan ('starter'|'pro') DEFAULT 'starter',
  plan_started_at date, trial_ends_at timestamptz,
  status ('trial'|'active'|'past_due'|'grace'|'paused'|'cancelled'),
  waba_id, wa_phone_number_id, wa_display_number,
  wa_token_encrypted text,  -- AES-256-GCM encrypted
  wa_connected_at timestamptz,
  msg_allowance int DEFAULT 500, msg_used_this_cycle int DEFAULT 0,
  billing_due_day int DEFAULT 1,
  [standard row fields except dealer_id]

offices
  id, dealer_id, name, address, city, phone, active bool DEFAULT true
  [standard]

users
  id, dealer_id, phone (unique), name, name_audio_url,
  role ('owner'|'manager'|'agent'|'munshi'),
  office_id, active bool DEFAULT true, last_seen_at,
  default_commission_pct numeric(5,2)
  [standard]
```

### 3.2 Inventory

```sql
properties
  id, dealer_id, office_id,
  kind ('plot'|'file'|'house'|'shop'|'commercial'|'apartment'),
  society text, block text, sector text,
  size_marla numeric(10,2), size_label text,
  demand_rs bigint CHECK (demand_rs >= 0),
  status ('available'|'token_given'|'bayana_done'|'sold'|'withdrawn'),
  owner_party_id uuid REFERENCES parties(id),
  exclusive bool DEFAULT false,
  cert_no text,
  notes_text text, notes_audio_url text,
  listed_at timestamptz DEFAULT now()
  [standard]

property_photos
  id, property_id, dealer_id, url text, thumb_url text,
  sort int DEFAULT 0, caption text,
  [standard without deleted fields]

property_documents
  id, property_id, dealer_id, type text, file_url, thumb_url,
  uploaded_by uuid REFERENCES users(id), created_at

property_status_history
  id, property_id, dealer_id, from_status, to_status,
  changed_by uuid, changed_at timestamptz DEFAULT now(),
  note text
  -- INSERT-ONLY, no updates
```

### 3.3 Parties

```sql
parties
  id, dealer_id, office_id,
  type ('buyer'|'seller'|'investor'),
  name text NOT NULL, name_audio_url text,
  phone text, -- primary phone
  photo_url text,
  cnic text, -- stored encrypted in application layer
  source ('walkin'|'zameen'|'facebook'|'referral'|'other'),
  wa_opt_in bool DEFAULT false,
  wa_opt_in_at timestamptz,
  wa_opt_in_source text,
  notes_text text, notes_audio_url text
  [standard]

party_phones
  id, party_id, dealer_id, phone text, label text, is_primary bool DEFAULT false
  [standard]

requirements
  id, party_id, dealer_id,
  kinds text[],  -- property types interested in
  areas text[],
  budget_min_rs bigint, budget_max_rs bigint,
  size_min_marla numeric, size_max_marla numeric,
  urgency ('hot'|'warm'|'cold') DEFAULT 'warm',
  active bool DEFAULT true,
  notes_text text, notes_audio_url text
  [standard]
```

### 3.4 Deals (Core)

```sql
deals
  id, dealer_id, office_id,
  property_id uuid REFERENCES properties(id),
  buyer_party_id uuid REFERENCES parties(id),
  seller_party_id uuid REFERENCES parties(id),
  assigned_agent_id uuid REFERENCES users(id),
  stage ('inquiry'|'token'|'bayana'|'registry'|'closed'|'lost') DEFAULT 'inquiry',
  -- Token fields
  token_type ('conditional'|'confirmed') NULL,
  token_rs bigint NULL CHECK (token_rs >= 0),
  token_date date NULL,
  token_expires_at timestamptz NULL,
  token_terms_text text NULL,
  token_terms_audio_url text NULL,
  -- Bayana fields
  bayana_rs bigint NULL CHECK (bayana_rs >= 0),
  bayana_date date NULL,
  bayana_due_at timestamptz NULL,
  bayana_terms_text text NULL,
  bayana_terms_audio_url text NULL,
  -- Deal financials
  deal_price_rs bigint CHECK (deal_price_rs > 0),
  comm_buyer_pct numeric(5,2) DEFAULT 1.00 CHECK (comm_buyer_pct >= 0),
  comm_seller_pct numeric(5,2) DEFAULT 1.00 CHECK (comm_seller_pct >= 0),
  -- Generated: expected_comm_rs = deal_price_rs * (buyer+seller)/100
  -- Registry
  registry_expected_at date NULL,
  registry_completed_at date NULL,
  registry_ref text NULL,
  -- Outcome
  lost_reason ('price'|'found_elsewhere'|'cold_feet'|'financing'|'other') NULL,
  lost_note text NULL,
  source text,
  notes_text text, notes_audio_url text,
  closed_at timestamptz NULL
  [standard]

deal_events
  -- IMMUTABLE — INSERT ONLY, no UPDATE/DELETE
  id, deal_id, dealer_id,
  kind text NOT NULL,  -- 'stage_change'|'payment'|'note'|'token_set'|etc
  from_stage text NULL,
  to_stage text NULL,
  actor_id uuid REFERENCES users(id),
  occurred_at timestamptz DEFAULT now(),
  meta jsonb DEFAULT '{}'
  -- NO standard updated/deleted fields

deal_splits
  id, deal_id, dealer_id,
  user_id uuid REFERENCES users(id),
  pct numeric(5,2) NOT NULL CHECK (pct > 0 AND pct <= 100),
  earned_rs bigint GENERATED ALWAYS AS (
    (SELECT expected_comm_rs FROM deals WHERE id = deal_id) * pct / 100
  ) STORED,
  paid_rs bigint DEFAULT 0 CHECK (paid_rs >= 0),
  [standard]
  -- TRIGGER: sum(pct) per deal_id must equal 100
```

### 3.5 Money

```sql
payments
  -- APPEND-ONLY. No updates. Corrections via reversal.
  id, dealer_id, deal_id NULL,
  kind ('token_in'|'bayana_in'|'commission_in'|'split_paid'|'expense'|
        'other_in'|'other_out'|'reversal'|'adjustment'),
  amount_rs bigint NOT NULL CHECK (amount_rs >= 0),
  direction ('in'|'out') NOT NULL,
  method ('cash'|'bank'|'jazzcash'|'easypaisa'),
  ref_no text,
  receipt_no text UNIQUE,  -- null for non-receipt payments
  receipt_photo_url text,
  reversed_by_id uuid REFERENCES payments(id) NULL,
  reversal_of_id uuid REFERENCES payments(id) NULL,
  paid_to_user_id uuid REFERENCES users(id) NULL,
  category text NULL,  -- for expenses
  note_text text, note_audio_url text,
  occurred_at timestamptz DEFAULT now(),
  idempotency_key text UNIQUE NOT NULL,
  [standard without deleted fields -- financial records not deleted]

receipt_counters
  dealer_id uuid NOT NULL REFERENCES dealers(id),
  year int NOT NULL,
  last_no int NOT NULL DEFAULT 0,
  PRIMARY KEY (dealer_id, year)
  -- Used with SELECT ... FOR UPDATE to generate sequential receipt numbers

expenses
  -- View over payments WHERE kind = 'expense'
  -- Or separate table for UI convenience:
  id, dealer_id, payment_id uuid REFERENCES payments(id),
  category ('office'|'fuel'|'food'|'listing_fee'|'salary'|'other'),
  category_audio_url text,
  amount_rs bigint, spent_on date,
  note_text text, note_audio_url text
  [standard]
```

### 3.6 Voice Notes

```sql
voice_notes
  id, dealer_id,
  ref_table text NOT NULL,   -- 'deals'|'parties'|'properties'|etc
  ref_id uuid NOT NULL,
  audio_url text NOT NULL,
  transcript_ur text,        -- best-effort, audio is truth
  duration_s int,
  [standard without deleted fields]
```

### 3.7 Follow-ups

```sql
followups
  id, dealer_id, deal_id NULL, party_id NULL, assigned_to uuid NULL,
  kind ('call'|'visit'|'whatsapp'|'other'),
  due_at timestamptz NOT NULL,
  done_at timestamptz NULL,
  snoozed_until timestamptz NULL,
  status ('pending'|'done'|'snoozed'|'cancelled') DEFAULT 'pending',
  note_text text, note_audio_url text
  [standard]
```

### 3.8 WhatsApp (Phase 2)

```sql
wa_templates
  id, code text UNIQUE, category ('utility'|'marketing'|'authentication'),
  lang text DEFAULT 'ur', body text, vars text[],
  approved bool DEFAULT false, meta_template_id text,
  [standard without dealer_id -- platform-level]

wa_sequences
  id, dealer_id, name text, trigger_stage text, active bool DEFAULT true
  [standard]

wa_steps
  id, sequence_id, dealer_id,
  day_offset int NOT NULL,
  template_id uuid REFERENCES wa_templates(id),
  stage_gates text[],   -- stop if deal in these stages
  [standard]

wa_sends
  id, dealer_id, deal_id, party_id, step_id NULL,
  template_id, direction ('out'|'in'),
  status ('queued'|'sent'|'delivered'|'read'|'failed'|'cancelled'),
  wa_msg_id text,
  cost_usd numeric(8,4) DEFAULT 0,
  error_code text NULL,
  sent_at timestamptz,
  [standard without deleted fields]

wa_inbox
  id, dealer_id, party_id NULL, deal_id NULL,
  direction ('in'|'out'),
  body text NULL,
  audio_url text NULL,  -- voice note
  wa_msg_id text UNIQUE,
  status text,
  [standard without deleted fields]
```

### 3.9 Documents

```sql
documents
  id, dealer_id, deal_id NULL, party_id NULL, property_id NULL,
  type ('token_receipt'|'token_agreement'|'bayana_agreement'|
        'cnic'|'ownership_doc'|'registry'|'other'),
  title text,
  file_url text NOT NULL,   -- signed URL, private bucket
  thumb_url text NULL,
  checksum text,
  expiry_date date NULL,
  verified bool DEFAULT false,
  verified_by uuid NULL,
  version int DEFAULT 1,
  [standard]
```

### 3.10 Notifications

```sql
notifications
  id, dealer_id, user_id,
  kind text NOT NULL,
  title_ur text, body_ur text,
  voice_url text NULL,
  deep_link text NULL,
  read_at timestamptz NULL,
  priority ('low'|'normal'|'high'|'urgent') DEFAULT 'normal',
  [standard without deleted fields]
```

### 3.11 Audit

```sql
audit_log
  -- IMMUTABLE — INSERT ONLY
  id, dealer_id,
  actor_id uuid REFERENCES users(id),
  table_name text, row_id uuid,
  action ('insert'|'update'|'delete'|'stage_change'|'payment'|'reversal'|'export'|'impersonate'),
  before_data jsonb NULL,
  after_data jsonb NULL,
  diff jsonb NULL,
  session_id text,
  ip_inet inet NULL,
  occurred_at timestamptz DEFAULT now()
```

### 3.12 Platform / Billing

```sql
subscriptions
  id, dealer_id, plan ('starter'|'pro'),
  started_at date, renews_at date,
  status ('trial'|'active'|'past_due'|'grace'|'paused'|'cancelled'),
  trial_ends_at timestamptz,
  [standard]

invoices
  id, dealer_id, period_start date, period_end date,
  amount_rs bigint, plan text,
  status ('pending'|'paid'|'overdue'|'waived'),
  paid_at timestamptz NULL,
  payment_proof_url text NULL,
  verified_by uuid NULL
  [standard]

app_config
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  description text,
  updated_at timestamptz DEFAULT now(),
  updated_by uuid NULL
  -- Holds: WA rates, feature flags, min_supported_version, TTS defaults
```

---

## 4. Key Triggers

```sql
-- 1. deal_splits must sum to 100% per deal
CREATE OR REPLACE FUNCTION check_split_sum() RETURNS TRIGGER AS $$
BEGIN
  IF (SELECT SUM(pct) FROM deal_splits WHERE deal_id = NEW.deal_id AND deleted_at IS NULL) != 100 THEN
    RAISE EXCEPTION 'commission splits must sum to 100%%';
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

-- 2. deal_events and audit_log are insert-only
-- Enforced via RLS: no UPDATE/DELETE permission granted on these tables

-- 3. Receipt number generation (concurrency-safe)
CREATE OR REPLACE FUNCTION next_receipt_no(p_dealer_id uuid, p_year int) RETURNS text AS $$
DECLARE
  next_no int;
BEGIN
  INSERT INTO receipt_counters (dealer_id, year, last_no) VALUES (p_dealer_id, p_year, 1)
  ON CONFLICT (dealer_id, year) DO UPDATE SET last_no = receipt_counters.last_no + 1
  RETURNING last_no INTO next_no;
  RETURN p_dealer_id::text || '-' || p_year::text || '-' || LPAD(next_no::text, 5, '0');
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. updated_at auto-update
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
-- Applied to all mutable tables
```

---

## 5. Indexes

Critical indexes:
```sql
-- Tenant scoping (most queries)
CREATE INDEX ON deals (dealer_id, stage);
CREATE INDEX ON deals (dealer_id, token_expires_at) WHERE stage = 'token';
CREATE INDEX ON payments (dealer_id, kind, occurred_at);
CREATE INDEX ON followups (dealer_id, due_at) WHERE status = 'pending';
CREATE INDEX ON parties (dealer_id, phone);
CREATE INDEX ON parties (dealer_id, type);
CREATE INDEX ON properties (dealer_id, status);
CREATE INDEX ON wa_sends (dealer_id, status, sent_at);
CREATE INDEX ON audit_log (dealer_id, occurred_at);
CREATE INDEX ON notifications (dealer_id, user_id, read_at);

-- Search
CREATE INDEX ON parties USING gin(to_tsvector('simple', name || ' ' || COALESCE(phone,'')));
CREATE INDEX ON properties USING gin(to_tsvector('simple', society || ' ' || COALESCE(block,'') || ' ' || COALESCE(cert_no,'')));
```
