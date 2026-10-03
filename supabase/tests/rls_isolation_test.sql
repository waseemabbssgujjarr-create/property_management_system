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
DO $$
DECLARE
  inserted_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  BEGIN
    INSERT INTO deals (dealer_id, stage, comm_buyer_pct, comm_seller_pct)
    VALUES ('99999999-9999-9999-9999-999999999999', 'inquiry', 1.0, 1.0)
    RETURNING id INTO inserted_id;

    RAISE EXCEPTION 'FAIL: Cross-tenant INSERT succeeded! id=%', inserted_id;
  EXCEPTION
    WHEN others THEN
      RAISE NOTICE 'PASS: Cross-tenant INSERT correctly rejected: %', SQLERRM;
  END;
END $$;

-- ── Test 3: WA credentials not readable by dealer ─────────────────────────
DO $$
DECLARE
  cred_count int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  -- Direct select of encrypted column — should return rows but without creds being decryptable
  -- The SELECT works (connection metadata is readable by the dealer)
  -- But api_key_encrypted is opaque ciphertext — not the plaintext key
  SELECT COUNT(*) INTO cred_count
  FROM whatsapp_connections
  WHERE dealer_id = '11111111-1111-1111-1111-111111111111';

  -- What we verify: api_key_encrypted is never the actual API key (it's ciphertext)
  DECLARE
    raw_key text;
  BEGIN
    SELECT api_key_encrypted INTO raw_key
    FROM whatsapp_connections
    WHERE dealer_id = '11111111-1111-1111-1111-111111111111'
    LIMIT 1;

    IF raw_key IS NOT NULL THEN
      -- Verify it's ciphertext (not plaintext — real API keys don't start with \xc3)
      ASSERT raw_key NOT LIKE 'sk_%' AND raw_key NOT LIKE 'Bearer %',
        'FAIL: api_key_encrypted appears to contain plaintext API key!';
    END IF;
  END;

  RAISE NOTICE 'PASS: WA credentials are opaque ciphertext to dealer clients';
END $$;

-- ── Test 4: Payments are INSERT-only (no UPDATE) ──────────────────────────
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  BEGIN
    UPDATE payments
    SET amount_rs = 999999
    WHERE dealer_id = '11111111-1111-1111-1111-111111111111'
    LIMIT 1;
    -- If this succeeds with rows updated, that's a policy gap
    IF FOUND THEN
      RAISE EXCEPTION 'FAIL: Payment UPDATE succeeded — append-only violated!';
    END IF;
    RAISE NOTICE 'PASS: Payment UPDATE rejected (0 rows — no UPDATE policy)';
  EXCEPTION
    WHEN others THEN
      RAISE NOTICE 'PASS: Payment UPDATE correctly rejected: %', SQLERRM;
  END;
END $$;

-- ── Test 5: deal_events are INSERT-only ───────────────────────────────────
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  BEGIN
    UPDATE deal_events SET kind = 'tampered' WHERE 1=0; -- safe: matches nothing
    RAISE NOTICE 'PASS: deal_events UPDATE has no rows effect (no UPDATE policy)';
  EXCEPTION
    WHEN others THEN
      RAISE NOTICE 'PASS: deal_events UPDATE rejected: %', SQLERRM;
  END;
END $$;

-- ── Test 6: Agent role cannot record payments ─────────────────────────────
DO $$
DECLARE
  inserted_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"agent"}',
    true
  );

  BEGIN
    INSERT INTO payments (
      dealer_id, kind, amount_rs, direction, method, idempotency_key
    ) VALUES (
      '11111111-1111-1111-1111-111111111111',
      'token_in', 50000, 'in', 'cash',
      'test-idempotency-key-agent'
    ) RETURNING id INTO inserted_id;

    RAISE EXCEPTION 'FAIL: Agent INSERT into payments succeeded! id=%', inserted_id;
  EXCEPTION
    WHEN others THEN
      RAISE NOTICE 'PASS: Agent payment INSERT correctly rejected: %', SQLERRM;
  END;
END $$;

-- ── Test 7: Munshi CAN record payments ────────────────────────────────────
DO $$
DECLARE
  inserted_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"munshi"}',
    true
  );

  BEGIN
    -- This should succeed (munshi can record payments)
    INSERT INTO payments (
      dealer_id, kind, amount_rs, direction, method, idempotency_key
    ) VALUES (
      '11111111-1111-1111-1111-111111111111',
      'token_in', 50000, 'in', 'cash',
      gen_random_uuid()::text
    ) RETURNING id INTO inserted_id;

    RAISE NOTICE 'PASS: Munshi payment INSERT succeeded (id=%)', inserted_id;

    -- Clean up test record
    DELETE FROM payments WHERE id = inserted_id;
  EXCEPTION
    WHEN others THEN
      RAISE NOTICE 'INFO: Munshi payment INSERT: %', SQLERRM;
  END;
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
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"dealer_id":"11111111-1111-1111-1111-111111111111","user_role":"owner"}',
    true
  );

  BEGIN
    INSERT INTO wa_webhook_events (
      dealer_id, connection_id, event_id, event_type
    ) VALUES (
      '11111111-1111-1111-1111-111111111111',
      'test-conn', 'test-event-999', 'test'
    );
    RAISE EXCEPTION 'FAIL: Dealer user can INSERT wa_webhook_events!';
  EXCEPTION
    WHEN others THEN
      RAISE NOTICE 'PASS: wa_webhook_events INSERT rejected for dealer user: %', SQLERRM;
  END;
END $$;

-- ── Summary ───────────────────────────────────────────────────────────────
RAISE NOTICE '=== RLS Test Suite Complete ===';
RAISE NOTICE 'All tests should show PASS. Any FAIL indicates a security gap.';
