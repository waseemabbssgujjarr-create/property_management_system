-- ============================================================
-- MUNSHI — RLS Fixes & JWT Custom Claims Hook
-- Version: 1.1 | Date: 2026-10-02
-- Fixes identified in Phase 1 audit:
--   1. dealers table was missing RLS
--   2. JWT custom claims hook needed for auth.dealer_id() and auth.current_role()
--   3. Add is_reversed() helper function for payments
-- ============================================================

-- ── 1. Enable RLS on dealers table (was missing) ─────────────────────────
ALTER TABLE dealers ENABLE ROW LEVEL SECURITY;

-- Dealers can only read/update their own record
CREATE POLICY "dealers_self_select" ON dealers FOR SELECT
  USING (id = auth.dealer_id());

CREATE POLICY "dealers_self_update" ON dealers FOR UPDATE
  USING (id = auth.dealer_id())
  WITH CHECK (id = auth.dealer_id());

-- INSERT is allowed for onboarding (before dealer_id claim is set)
-- Only service role or authenticated user with matching phone can insert
CREATE POLICY "dealers_insert_onboarding" ON dealers FOR INSERT
  WITH CHECK (
    phone = (SELECT phone FROM auth.users WHERE id = auth.uid() LIMIT 1)
    OR auth.role() = 'service_role'
  );

-- ── 2. JWT Custom Claims Hook ─────────────────────────────────────────────
-- This hook fires after every JWT is minted by Supabase Auth.
-- It injects dealer_id, user_role, and office_id into the JWT claims.
-- Required for auth.dealer_id() and auth.current_role() to work in RLS.
--
-- SETUP REQUIRED: Register this function as a "Custom Access Token" hook
-- in Supabase Dashboard → Authentication → Hooks.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claims jsonb;
  user_phone text;
  user_record record;
BEGIN
  claims := event->'claims';

  -- Get the authenticated user's phone from Supabase auth
  user_phone := (SELECT phone FROM auth.users WHERE id = (event->>'user_id')::uuid LIMIT 1);

  IF user_phone IS NOT NULL THEN
    -- Look up the user's dealer context
    SELECT
      u.id         AS user_id,
      u.dealer_id,
      u.role       AS user_role,
      u.office_id
    INTO user_record
    FROM public.users u
    WHERE u.phone = user_phone
      AND u.active = true
    LIMIT 1;

    IF FOUND THEN
      claims := jsonb_set(claims, '{dealer_id}',   to_jsonb(user_record.dealer_id::text));
      claims := jsonb_set(claims, '{user_id}',     to_jsonb(user_record.user_id::text));
      claims := jsonb_set(claims, '{user_role}',   to_jsonb(user_record.user_role));
      claims := jsonb_set(claims, '{office_id}',   COALESCE(to_jsonb(user_record.office_id::text), 'null'::jsonb));
    END IF;
  END IF;

  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;

-- Grant execute to supabase_auth_admin (required for hook to work)
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM authenticated, anon, public;

-- ── 3. Helper: check if a payment has been reversed ────────────────────────
-- Use this instead of the broken reversed_by_id UPDATE approach.
CREATE OR REPLACE FUNCTION is_payment_reversed(p_payment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM payments
    WHERE reversal_of_id = p_payment_id
  );
$$;

-- ── 4. Add missing index for reversal lookup ──────────────────────────────
CREATE INDEX IF NOT EXISTS idx_payments_reversal_of ON payments (reversal_of_id)
  WHERE reversal_of_id IS NOT NULL;

-- ── 5. Tighten audit_log INSERT policy ────────────────────────────────────
-- The existing `WITH CHECK (true)` allows anyone to insert audit records.
-- Restrict to service_role only (Edge Functions write audit, not clients).
DROP POLICY IF EXISTS "audit_insert" ON audit_log;
CREATE POLICY "audit_insert" ON audit_log FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- ── 6. WhatsApp webhook signature: never skip in production ───────────────
-- Enforced in code; documented here for audit trail.
-- See: supabase/functions/whatsapp-webhook/index.ts
-- The verifySignature() function returns true when APP_SECRET is missing.
-- Production deployment MUST set META_APP_SECRET in Edge Function secrets.
-- Command: supabase secrets set META_APP_SECRET=<your_secret>

COMMENT ON TABLE dealers IS
  'Multi-tenant root. RLS enforced. wa_token_encrypted must never be decrypted client-side.';

COMMENT ON TABLE payments IS
  'APPEND-ONLY. No UPDATE or DELETE policies exist. Use reversal rows for corrections. Check is_payment_reversed() to detect reversed payments.';

-- ── Atomic onboarding DB function ────────────────────────────────────────
-- Called by onboarding-create Edge Function (service role).
-- Wraps dealer + user creation in a transaction.
CREATE OR REPLACE FUNCTION create_dealer_and_owner(
  p_phone       text,
  p_agency_name text,
  p_city        text,
  p_areas       text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_dealer_id uuid;
  v_user_id   uuid;
BEGIN
  -- Insert dealer (idempotent via ON CONFLICT)
  INSERT INTO dealers (name, phone, city, areas, ui_mode, voice_enabled, language, plan, status)
  VALUES (p_agency_name, p_phone, p_city, p_areas, 'simple', true, 'ur', 'starter', 'trial')
  ON CONFLICT (phone) DO UPDATE SET name = EXCLUDED.name
  RETURNING id INTO v_dealer_id;

  -- Insert owner user (idempotent via ON CONFLICT)
  INSERT INTO users (dealer_id, phone, name, role, active)
  VALUES (v_dealer_id, p_phone, p_agency_name, 'owner', true)
  ON CONFLICT (phone) DO UPDATE SET dealer_id = EXCLUDED.dealer_id, active = true
  RETURNING id INTO v_user_id;

  RETURN jsonb_build_object('dealer_id', v_dealer_id, 'user_id', v_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION create_dealer_and_owner TO service_role;
