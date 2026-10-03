@echo off
cd /d "c:\Users\dell\Downloads\Property Management System"

set GIT="C:\Program Files\Git\cmd\git.exe"

echo === Initialising git ===
%GIT% init

echo === Setting identity ===
%GIT% config user.email "dev@munshi.app"
%GIT% config user.name "Munshi Dev"

echo === Creating .gitignore additions ===
echo .env.dev.local >> .gitignore
echo .env.staging.local >> .gitignore
echo .env.prod.local >> .gitignore

echo === Adding remote ===
%GIT% remote remove origin 2>nul
%GIT% remote add origin https://github.com/waseemabbsgujjarr-create/property_management_system.git

echo === Staging all files ===
%GIT% add .

echo === Committing ===
%GIT% commit -m "feat: Munshi Phase 1 complete - dealer OS foundation

- Flutter app scaffold (Android-first, offline-first, Urdu RTL)
- Complete Supabase schema with RLS on every table (migrations 001-005)
- Auth: phone OTP + voice OTP + SMS fallback (Twilio/local provider)
- JWT custom claims hook for tenant isolation
- Deal engine: state machine (inquiry>token>bayana>registry>closed)
- Money engine: append-only payments, BIGINT, idempotency, receipts
- Staff commission: earned/paid/pending with voice summary
- CNIC encryption: AES-256-CBC via FlutterSecureStorage
- Atomic onboarding: PL/pgSQL transaction via Edge Function
- Offline engine: Drift + sync queue + exponential backoff
- WhatsApp integration: own WA API adapter (not Meta-direct)
- WA credentials: pgp_sym_encrypt, never returned to client
- Webhook: HMAC-SHA256 verification + event idempotency
- Permission guards: PermissionService + RLS (3-layer enforcement)
- Repository boundary: no Supabase calls in screen widgets
- No-read UI: voice TTS/STT, BigActionButton 96dp, lac/crore money
- Design tokens: brand-900 green/gold, stage colors fixed
- Edge Functions: otp-send, voice-otp-call, wa-connect, wa-send,
  wa-webhook, wa-health-check, onboarding-create, send-staff-invite
- Architecture docs: ARCHITECTURE.md, DATABASE.md, SECURITY.md,
  SYNC-DESIGN.md, PERMISSIONS.md, WHATSAPP-INTEGRATION.md
- Audit docs: IMPLEMENTATION-AUDIT.md, PHASE-1-FINAL-AUDIT.md,
  PILOT-READINESS-AUDIT.md, BUILD-STATUS.md
- RLS isolation test suite (10 tests)
- Unit tests: money formatter, permissions, OTP, financial integrity,
  sync state, encryption

Phase 1 gate: YELLOW (code complete; Flutter + Supabase runtime
validation required on developer machine before GREEN)"

echo === Pushing to main ===
%GIT% branch -M main
%GIT% push -u origin main

echo === Done ===
