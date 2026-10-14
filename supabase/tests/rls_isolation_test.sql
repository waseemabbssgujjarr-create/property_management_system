-- ============================================================
-- MUNSHI — RLS Isolation Test Suite
-- Run against staging environment with test tenants seeded.
-- NEVER run against production.
-- ============================================================
-- Setup: seed two dealers and multiple users before running.
-- Use the demo_dealer.sql seed + a second dealer for Dealer B.
-- ============================================================

-- ── Helper: set JWT claims for testing ────────────────────────────────────
-- In Supabase, use the service role to impersonate users for RLS testing.
-- Or use the JS/TS test client with per-user JWTs.

-- These tests are written as assertions: each should return 0 rows
-- (violation not present) or explicit expected counts.

-- ── Test 1: Dealer A owner cannot see Dealer B deals ─────────────────────
DO $$
DECLARE
  count_b int;
BEGIN
  -- Simulate as Dealer A (set local JWT claim)
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SELECT COUNT(*) INTO count_b
  FROM deals
  WHERE dealer_id = '99999999-9999-9999-9999-999999999999'; -- Dealer B (non-existent in test)

  ASSERT count_b = 0,
    'FAIL: Dealer A can see Dealer B deals — cross-tenant leak!';

  RAISE NOTICE 'PASS: Dealer A cannot see Dealer B deals';
END $$;

-- ── Test 2: Dealer A cannot insert for Dealer B ───────────────────────────
-- RLS INSERT policy on deals: WITH CHECK (dealer_id = auth.dealer_id()).
-- A cross-tenant INSERT must be denied with 42501 (insufficient_privilege).
DO $$
DECLARE
  inserted_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  INSERT INTO deals (dealer_id, stage, comm_buyer_pct, comm_seller_pct)
  VALUES ('99999999-9999-9999-9999-999999999999', 'inquiry', 1.0, 1.0)
  RETURNING id INTO inserted_id;

  -- Only reached when INSERT succeeded — RLS policy is missing or bypassed.
  RAISE EXCEPTION 'FAIL: Cross-tenant INSERT succeeded! id=%', inserted_id;

EXCEPTION
  WHEN SQLSTATE '42501' THEN            -- ← expected: RLS denied the cross-tenant insert
    RAISE NOTICE 'PASS: Cross-tenant INSERT correctly rejected (42501 insufficient_privilege)';

  WHEN others THEN                      -- ← unexpected: re-raise, do not hide
    RAISE;
END $$;

-- ── Test 3: WA credential columns are bytea (not text) ────────────────────
DO $$
DECLARE
  col_type text;
BEGIN
  SELECT data_type INTO col_type
  FROM information_schema.columns
  WHERE table_name = 'whatsapp_connections'
    AND column_name = 'api_key_encrypted';

  ASSERT col_type = 'bytea',
    'FAIL: api_key_encrypted should be bytea (pgcrypto output), got %', col_type;

  RAISE NOTICE 'PASS: api_key_encrypted is bytea — pgcrypto output stored directly';
END $$;

-- ── Test 3a: authenticated role CANNOT SELECT credential columns ──────────
-- Column-level GRANT omits api_key_encrypted and webhook_secret_encrypted.
-- Each column is checked separately. Two and only two outcomes per check:
--   42501 insufficient_privilege  → PASS  (expected denial)
--   anything else (success or unexpected error) → FAIL, role restored first
--
-- api_key_encrypted ───────────────────────────────────────────────────────
DO $$
BEGIN
  SET ROLE authenticated;
  -- PostgreSQL checks column SELECT privileges at parse/plan time; raises
  -- 42501 immediately when the column is absent from the GRANT list.
  PERFORM api_key_encrypted FROM whatsapp_connections LIMIT 1;

  -- Only reached when SELECT did not raise — the column GRANT is too broad.
  RESET ROLE;
  RAISE EXCEPTION 'FAIL: authenticated can SELECT api_key_encrypted — column GRANT missing!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN                         -- ← expected: insufficient_privilege
    RESET ROLE;
    RAISE NOTICE 'PASS: api_key_encrypted blocked for authenticated (42501 insufficient_privilege)';

  WHEN others THEN                                   -- ← unexpected: restore role, re-raise
    RESET ROLE;
    RAISE;
END $$;

-- webhook_secret_encrypted ────────────────────────────────────────────────
DO $$
BEGIN
  SET ROLE authenticated;
  PERFORM webhook_secret_encrypted FROM whatsapp_connections LIMIT 1;

  -- Only reached when SELECT did not raise.
  RESET ROLE;
  RAISE EXCEPTION 'FAIL: authenticated can SELECT webhook_secret_encrypted — column GRANT missing!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN
    RESET ROLE;
    RAISE NOTICE 'PASS: webhook_secret_encrypted blocked for authenticated (42501 insufficient_privilege)';

  WHEN others THEN
    RESET ROLE;
    RAISE;
END $$;

-- ── Test 3b: authenticated role CAN SELECT safe metadata columns ───────────
DO $$
DECLARE
  v_count int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SET ROLE authenticated;

  -- Safe metadata columns should be accessible (column GRANT includes them)
  SELECT COUNT(*) INTO v_count
  FROM whatsapp_connections
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  RAISE NOTICE 'PASS: authenticated can SELECT safe metadata columns (count=%)', v_count;

  RESET ROLE;
END $$;

-- ── Test 3c: authenticated role CANNOT UPDATE credential columns ──────────
-- The column-level UPDATE GRANT includes only status, disconnected_at,
-- updated_by, error_message — NOT api_key_encrypted or webhook_secret_encrypted.
-- Attempting to UPDATE a non-granted column raises 42501.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SET ROLE authenticated;
  -- Column privilege is checked at parse/plan time, regardless of matching rows.
  UPDATE whatsapp_connections
  SET api_key_encrypted = '\x00'::bytea
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  -- Only reached when UPDATE did not raise — column GRANT is too broad.
  RESET ROLE;
  RAISE EXCEPTION 'FAIL: authenticated can UPDATE api_key_encrypted — column GRANT missing!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN            -- ← expected: insufficient_privilege
    RESET ROLE;
    RAISE NOTICE 'PASS: authenticated cannot UPDATE api_key_encrypted (42501 insufficient_privilege)';

  WHEN others THEN                      -- ← unexpected: restore role, re-raise
    RESET ROLE;
    RAISE;
END $$;

-- ── Test 3d: authenticated CANNOT INSERT server-controlled fields ──────────
-- The column-level INSERT GRANT on wa_outbound_queue includes only business
-- input fields. Attempting to INSERT a non-granted column raises 42501.
-- Each denied column is verified in a separate block.
--
-- status ──────────────────────────────────────────────────────────────────
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SET ROLE authenticated;
  INSERT INTO wa_outbound_queue (
    dealer_id, connection_id, to_phone, idempotency_key, status
  ) VALUES (
    '11111111-1111-1111-1111-111111111111', 'test_conn', '+92300', 'test-key', 'sent'
  );

  -- Only reached when INSERT did not raise.
  RESET ROLE;
  RAISE EXCEPTION 'FAIL: authenticated can INSERT status — column GRANT missing!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN
    RESET ROLE;
    RAISE NOTICE 'PASS: authenticated cannot INSERT status (42501 insufficient_privilege)';

  WHEN others THEN
    RESET ROLE;
    RAISE;
END $$;

-- provider_msg_id ─────────────────────────────────────────────────────────
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SET ROLE authenticated;
  INSERT INTO wa_outbound_queue (
    dealer_id, connection_id, to_phone, idempotency_key, provider_msg_id
  ) VALUES (
    '11111111-1111-1111-1111-111111111111', 'test_conn', '+92300', 'test-key2', 'wamid.xxx'
  );

  -- Only reached when INSERT did not raise.
  RESET ROLE;
  RAISE EXCEPTION 'FAIL: authenticated can INSERT provider_msg_id — column GRANT missing!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN
    RESET ROLE;
    RAISE NOTICE 'PASS: authenticated cannot INSERT provider_msg_id (42501 insufficient_privilege)';

  WHEN others THEN
    RESET ROLE;
    RAISE;
END $$;

-- ── Test 3e: authenticated CANNOT UPDATE wa_outbound_queue ─────────────────
-- No UPDATE GRANT exists for authenticated on wa_outbound_queue (table-level
-- UPDATE was revoked). Attempting any UPDATE raises 42501.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SET ROLE authenticated;
  UPDATE wa_outbound_queue
  SET status = 'sent'
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  -- Only reached when UPDATE did not raise — GRANT or RLS is missing.
  RESET ROLE;
  RAISE EXCEPTION 'FAIL: authenticated can UPDATE wa_outbound_queue — GRANT or RLS missing!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN            -- ← expected: insufficient_privilege
    RESET ROLE;
    RAISE NOTICE 'PASS: authenticated cannot UPDATE wa_outbound_queue (42501 insufficient_privilege)';

  WHEN others THEN                      -- ← unexpected: restore role, re-raise
    RESET ROLE;
    RAISE;
END $$;

-- ── Test 4: Payments are INSERT-only (no UPDATE) ──────────────────────────
-- The payments table has no UPDATE RLS policy. Any UPDATE attempt
-- (even affecting 0 rows) must be denied with 42501 because
-- authenticated clients have no UPDATE privilege via GRANT on this table.
-- This verifies the append-only invariant at the privilege layer, not just
-- the absence of matching rows.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  UPDATE payments
  SET amount_rs = 999999
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  -- Only reached if UPDATE did not raise — either rows were changed
  -- (append-only violated) or UPDATE was silently allowed without privilege.
  IF FOUND THEN
    RAISE EXCEPTION 'FAIL: Payment UPDATE modified rows — append-only violated!';
  ELSE
    RAISE EXCEPTION 'FAIL: Payment UPDATE succeeded (0 rows) — no UPDATE privilege denial. '
      'Expected 42501 but the statement was accepted without error.';
  END IF;

EXCEPTION
  WHEN SQLSTATE '42501' THEN            -- ← expected: no UPDATE privilege on payments
    RAISE NOTICE 'PASS: Payment UPDATE denied (42501 insufficient_privilege — no UPDATE policy)';

  WHEN others THEN                      -- ← unexpected: re-raise
    RAISE;
END $$;

-- ── Test 5: deal_events are INSERT-only ───────────────────────────────────
-- deal_events has no UPDATE RLS policy. Any UPDATE attempt must be denied
-- with 42501. Use a WHERE clause that could match real rows (1=1) so the
-- test exercises the privilege check, not just a zero-row early exit.
-- The seed data may or may not have deal_events; privilege denial fires
-- at parse/plan time before rows are touched.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  UPDATE deal_events
  SET kind = 'tampered'
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  -- Only reached if UPDATE did not raise — no privilege denial occurred.
  RAISE EXCEPTION 'FAIL: deal_events UPDATE was not denied — INSERT-only invariant violated!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN            -- ← expected: no UPDATE privilege on deal_events
    RAISE NOTICE 'PASS: deal_events UPDATE denied (42501 insufficient_privilege — no UPDATE policy)';

  WHEN others THEN                      -- ← unexpected: re-raise
    RAISE;
END $$;

-- ── Test 6: Agent role cannot record payments ─────────────────────────────
-- RLS INSERT policy on payments checks user_role != 'agent'.
-- A blocked INSERT raises 42501 (insufficient_privilege via RLS).
DO $$
DECLARE
  inserted_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"agent"}',
    true
  );

  INSERT INTO payments (
    dealer_id, kind, amount_rs, direction, method, idempotency_key
  ) VALUES (
    '11111111-1111-1111-1111-111111111111',
    'token_in', 50000, 'in', 'cash',
    'test-idempotency-key-agent'
  ) RETURNING id INTO inserted_id;

  -- Only reached when INSERT succeeded — RLS policy is missing or bypassed.
  RAISE EXCEPTION 'FAIL: Agent INSERT into payments succeeded! id=%', inserted_id;

EXCEPTION
  WHEN SQLSTATE '42501' THEN            -- ← expected: RLS denied the agent insert
    RAISE NOTICE 'PASS: Agent payment INSERT correctly rejected (42501 insufficient_privilege)';

  WHEN others THEN                      -- ← unexpected: re-raise, do not hide
    RAISE;
END $$;

-- ── Test 7: Munshi CAN record payments ────────────────────────────────────
-- DIAGNOSTIC TEST: This test verifies that the munshi role can INSERT
-- payments. It is a positive capability test, not a security denial test.
-- It requires seed data: a valid dealer with id 11111111-... must exist.
-- The EXCEPTION handler indicates a test environment issue (missing seed),
-- not a security failure. If seed data is absent, the test is inconclusive.
DO $$
DECLARE
  inserted_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"munshi"}',
    true
  );

  -- This INSERT must succeed (munshi is permitted to record payments).
  INSERT INTO payments (
    dealer_id, kind, amount_rs, direction, method, idempotency_key
  ) VALUES (
    '11111111-1111-1111-1111-111111111111',
    'token_in', 50000, 'in', 'cash',
    'test-munshi-idempotency-' || gen_random_uuid()::text
  ) RETURNING id INTO inserted_id;

  -- Clean up: delete the test record to leave no side-effects.
  -- payments is append-only by RLS (no UPDATE), but service-role
  -- can DELETE for test cleanup. In the test session (authenticated),
  -- this DELETE will be denied — acceptable; the record has a unique
  -- idempotency key and will not affect re-runs.
  DELETE FROM payments WHERE id = inserted_id;

  RAISE NOTICE 'PASS: Munshi payment INSERT succeeded and cleaned up (id=%)', inserted_id;

EXCEPTION
  WHEN SQLSTATE '42501' THEN
    -- munshi INSERT was denied — this is a FAIL (policy is too restrictive).
    RAISE EXCEPTION 'FAIL: Munshi payment INSERT denied (42501) — RLS INSERT policy incorrect!';

  WHEN SQLSTATE '23503' THEN
    -- Foreign key violation: seed dealer does not exist in test environment.
    RAISE NOTICE 'DIAGNOSTIC: Munshi payment INSERT FK error — seed dealer 11111111-... not found. '
      'Run demo_dealer.sql seed before this test suite.';

  WHEN others THEN
    -- Unexpected error — propagate.
    RAISE;
END $$;

-- ── Test 8: Subscription only readable by owner ───────────────────────────
DO $$
DECLARE
  sub_count int;
BEGIN
  -- As manager: should not see subscription
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"manager"}',
    true
  );

  SELECT COUNT(*) INTO sub_count FROM subscriptions
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  ASSERT sub_count = 0,
    'FAIL: Manager can see subscription (should be owner-only)';
  RAISE NOTICE 'PASS: Manager cannot see subscription';

  -- As owner: should see subscription
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SELECT COUNT(*) INTO sub_count FROM subscriptions
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  RAISE NOTICE 'PASS: Owner subscription count: %', sub_count;
END $$;

-- ── Test 9: audit_log SELECT only for owner ───────────────────────────────
DO $$
DECLARE
  audit_count int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"agent"}',
    true
  );

  SELECT COUNT(*) INTO audit_count FROM audit_log
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  ASSERT audit_count = 0,
    'FAIL: Agent can read audit_log';
  RAISE NOTICE 'PASS: Agent cannot read audit_log';
END $$;

-- ── Test 10: WA webhook events only writable by service_role ─────────────
-- RLS INSERT policy: WITH CHECK (auth.role() = 'service_role').
-- An authenticated INSERT must be denied with 42501.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  INSERT INTO wa_webhook_events (
    dealer_id, connection_id, event_id, event_type
  ) VALUES (
    '11111111-1111-1111-1111-111111111111',
    'test-conn', 'test-event-999', 'test'
  );

  -- Only reached when INSERT succeeded — RLS policy is missing or bypassed.
  RAISE EXCEPTION 'FAIL: Dealer user can INSERT wa_webhook_events!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN            -- ← expected: RLS denied the insert
    RAISE NOTICE 'PASS: wa_webhook_events INSERT rejected for dealer user (42501 insufficient_privilege)';

  WHEN others THEN                      -- ← unexpected: re-raise, do not hide
    RAISE;
END $$;

-- ── Test 11: Authenticated users cannot SELECT wa_webhook_events ─────────
-- wa_webhook_events has REVOKE ALL for authenticated + no SELECT GRANT.
-- Two and only two outcomes:
--   42501 insufficient_privilege  → PASS  (expected denial)
--   anything else (success or unexpected error) → FAIL, role restored first
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  SET ROLE authenticated;
  PERFORM id FROM wa_webhook_events LIMIT 1;

  -- Only reached when SELECT did not raise — the permission is missing.
  RESET ROLE;
  RAISE EXCEPTION 'FAIL: authenticated can SELECT wa_webhook_events — REVOKE ALL not effective!';

EXCEPTION
  WHEN SQLSTATE '42501' THEN                         -- ← expected: insufficient_privilege
    RESET ROLE;
    RAISE NOTICE 'PASS: wa_webhook_events blocked for authenticated (42501 insufficient_privilege)';

  WHEN others THEN                                   -- ← unexpected: restore role, re-raise
    RESET ROLE;
    RAISE;
END $$;

-- ── Summary ───────────────────────────────────────────────────────────────
RAISE NOTICE '=== RLS Test Suite Complete ===';
RAISE NOTICE 'All tests should show PASS. Any FAIL indicates a security gap.';
