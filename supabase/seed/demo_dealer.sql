-- ============================================================
-- MUNSHI — Demo Dealer Seed Data
-- For development/staging only. NEVER run in production.
-- Creates a complete demo dealer with 5 live deals for demos.
-- ============================================================

-- Demo dealer
INSERT INTO dealers (id, name, phone, city, areas, ui_mode, voice_enabled, language, plan, status)
VALUES (
  '11111111-1111-1111-1111-111111111111',
  'الحمد پراپرٹیز',
  '+923001234567',
  'لاہور',
  ARRAY['DHA فیز 6', 'DHA فیز 5', 'بحریہ ٹاؤن'],
  'simple',
  true,
  'ur',
  'pro',
  'active'
) ON CONFLICT (phone) DO NOTHING;

-- Demo owner user
INSERT INTO users (id, dealer_id, phone, name, role, active)
VALUES (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  '+923001234567',
  'محمد یوسف',
  'owner',
  true
) ON CONFLICT (phone) DO NOTHING;

-- Demo staff
INSERT INTO users (id, dealer_id, phone, name, role, default_commission_pct, active)
VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '+923009876543', 'اسامہ خان', 'agent', 30.00, true),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '+923331112222', 'علی احمد', 'munshi', NULL, true)
ON CONFLICT (phone) DO NOTHING;

-- Demo properties
INSERT INTO properties (id, dealer_id, kind, society, block, size_marla, demand_rs, status, listed_at)
VALUES
  ('p1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'plot', 'DHA لاہور فیز 6', 'D', 10, 25000000, 'available', now() - interval '10 days'),
  ('p2222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'plot', 'DHA لاہور فیز 6', 'F', 5, 12500000, 'token_given', now() - interval '5 days'),
  ('p3333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'house', 'بحریہ ٹاؤن لاہور', 'پریمیم بلاک', 10, 35000000, 'bayana_done', now() - interval '30 days'),
  ('p4444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'file', 'DHA لاہور فیز 5', 'J', 1, 4500000, 'available', now() - interval '3 days'),
  ('p5555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'plot', 'DHA لاہور فیز 6', 'B', 20, 60000000, 'sold', now() - interval '60 days')
ON CONFLICT DO NOTHING;

-- Demo parties (buyers)
INSERT INTO parties (id, dealer_id, type, name, phone, source, wa_opt_in)
VALUES
  ('b1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'buyer', 'عمر فاروق', '+923451234567', 'zameen', true),
  ('b2222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'buyer', 'احمد رضا', '+923001112233', 'referral', true),
  ('b3333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'buyer', 'عائشہ بی بی', '+923334455667', 'facebook', false),
  ('s1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'seller', 'محمد اکبر', '+923009988776', 'walkin', false)
ON CONFLICT DO NOTHING;

-- Demo deals
INSERT INTO deals (
  id, dealer_id, property_id, buyer_party_id, seller_party_id,
  stage, token_type, token_rs, token_expires_at,
  deal_price_rs, comm_buyer_pct, comm_seller_pct,
  assigned_agent_id
)
VALUES
  -- Deal 1: Token stage, expiring in 2 days
  (
    'd1111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111111',
    'p2222222-2222-2222-2222-222222222222',
    'b1111111-1111-1111-1111-111111111111',
    's1111111-1111-1111-1111-111111111111',
    'token', 'confirmed', 50000, now() + interval '2 days',
    12500000, 1.00, 1.00,
    '33333333-3333-3333-3333-333333333333'
  ),
  -- Deal 2: Bayana stage
  (
    'd2222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111',
    'p3333333-3333-3333-3333-333333333333',
    'b2222222-2222-2222-2222-222222222222',
    's1111111-1111-1111-1111-111111111111',
    'bayana', 'confirmed', 200000, NULL,
    35000000, 1.00, 1.00,
    '33333333-3333-3333-3333-333333333333'
  ),
  -- Deal 3: Inquiry stage
  (
    'd3333333-3333-3333-3333-333333333333',
    '11111111-1111-1111-1111-111111111111',
    'p1111111-1111-1111-1111-111111111111',
    'b3333333-3333-3333-3333-333333333333',
    NULL,
    'inquiry', NULL, NULL, NULL,
    25000000, 1.00, 1.00,
    '33333333-3333-3333-3333-333333333333'
  )
ON CONFLICT DO NOTHING;

-- Demo commission splits for deal 2
INSERT INTO deal_splits (deal_id, dealer_id, user_id, pct, paid_rs)
VALUES
  ('d2222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 70.00, 0),
  ('d2222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 30.00, 0)
ON CONFLICT DO NOTHING;

-- Demo follow-ups due today
INSERT INTO followups (dealer_id, deal_id, party_id, kind, due_at, note_text, status)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111', 'call', now(), 'ٹوکن کی تصدیق', 'pending'),
  ('11111111-1111-1111-1111-111111111111', 'd3333333-3333-3333-3333-333333333333', 'b3333333-3333-3333-3333-333333333333', 'whatsapp', now() + interval '30 minutes', 'پراپرٹی وزٹ', 'pending')
ON CONFLICT DO NOTHING;
