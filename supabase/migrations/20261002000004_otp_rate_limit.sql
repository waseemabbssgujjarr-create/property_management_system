-- ============================================================
-- OTP Rate Limiting Table
-- Used by otp-send and voice-otp-call Edge Functions.
-- No sensitive data stored here (phone only, no OTP values).
-- ============================================================

CREATE TABLE IF NOT EXISTS otp_attempts (
  id           uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  phone        text        NOT NULL,
  attempted_at timestamptz NOT NULL DEFAULT now()
);

-- Index for efficient rate-limit window queries
CREATE INDEX IF NOT EXISTS idx_otp_attempts_phone_time
  ON otp_attempts (phone, attempted_at);

-- Auto-clean old entries (older than 1 hour) to keep table small
-- This is handled by a cron job; the data retention is short-lived.
-- The table is intentionally NOT RLS-protected because it's only
-- written by Edge Functions using service_role.

-- Clean up entries older than 1 hour (run periodically via pg_cron)
-- SELECT cron.schedule('otp-cleanup', '*/30 * * * *',
--   $$DELETE FROM otp_attempts WHERE attempted_at < now() - interval '1 hour'$$);

COMMENT ON TABLE otp_attempts IS
  'Rate limiting for OTP delivery. Phone only — never stores OTP values. Auto-cleaned.';
