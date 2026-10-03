# IMPLEMENTATION AUDIT — Munshi
**Date:** 2026-10-02 | **Auditor:** Kiro AI

---

## 1. Repository State

**Current state:** Empty workspace. No prior implementation exists.

This means:
- No architecture to preserve or migrate
- No database migrations to audit
- No existing code to conflict with
- Full greenfield build — follow master build guide precisely

---

## 2. What Exists

| Category | Status |
|---|---|
| Flutter app | ❌ Does not exist |
| Supabase project | ❌ Not configured |
| Database migrations | ❌ None |
| Authentication | ❌ None |
| Design system | ❌ None |
| Localization | ❌ None |
| Offline engine | ❌ None |
| WhatsApp integration | ❌ None |
| Tests | ❌ None |
| CI/CD | ❌ None |
| Environment config | ❌ None |
| Documentation | ✅ Spec docs provided (01–05.md) |

---

## 3. Architecture Risks (Greenfield)

### 3.1 Database Risks
- Multi-tenant RLS must be correct from day one — retrofitting RLS on a live database is dangerous
- Money stored as float would cause rounding errors at scale — **must use BIGINT rupees**
- Receipt sequence counters must be concurrency-safe (use Postgres sequences or advisory locks)
- Stage transitions must be enforced at DB level, not just app level
- commission_splits sum=100% must be a DB trigger, not just UI validation

### 3.2 Security Risks
- Supabase anon key must never reach production with a public bucket for private docs
- Voice notes and CNICs are sensitive PII — private buckets + signed URLs mandatory from day 1
- Meta WhatsApp tokens must be stored encrypted (pgcrypto/Vault), never in plaintext
- Service-role key must never be bundled in the Flutter app

### 3.3 Offline Risks
- Drift local DB schema must match Supabase schema shape exactly to avoid sync conflicts
- Idempotency keys must be generated client-side before any network call
- Money operations that arrive out of order must not produce incorrect balances
- Photo/audio attachment sync needs a separate queue from record sync

### 3.4 UX Risks
- Simple/Detail mode state must be persisted — if app restarts in Detail mode for an owner who can't read, it's broken
- TTS and STT must degrade gracefully — voice failure cannot block core flows
- RTL layout bugs are common in Flutter with mixed content — requires dedicated Urdu audit pass

---

## 4. What Is Incomplete

Everything. This is a full build from scratch.

---

## 5. Recommended Implementation Order

1. Architecture docs (this file + companions)
2. Flutter scaffold + design system + primitives
3. Supabase DB migration
4. Auth + tenancy + RLS
5. Home screen (Simple Mode — the demo screen)
6. Inventory + Parties
7. Deal engine
8. Money engine
9. Follow-ups + Notifications + Search
10. Offline engine (Drift + sync queue)
11. Documents + Reports
12. WhatsApp foundation + automation
13. Billing + admin
14. Web console + marketing site
15. Production hardening

---

## 6. Missing Tests

All tests are missing. Per the build guide, test suites must cover:
- Money formatting (unit)
- Commission calculations (unit, property-based)
- Split sum invariant (unit + DB trigger)
- Stage machine transitions (unit)
- RLS tenant isolation (integration)
- Offline sync idempotency (integration)
- Literacy acceptance test (manual, release blocker)
- Financial integrity (property-based)
- Security boundary tests (integration)

---

## 7. Decisions Made in This Audit

| Decision | Rationale |
|---|---|
| Flutter 3.x, Material 3 | Specified in build guide; best RTL support |
| Drift + SQLite for offline | Specified; type-safe, excellent Flutter integration |
| Supabase (Postgres + Auth + Edge + Storage) | Specified; fastest path to RLS + realtime |
| BIGINT rupees everywhere | Financial integrity; no floats |
| Feature flags from day 1 | WhatsApp, demand matching, circles are Phase 2/3 |
| Soft deletes on business records | Dealer trust; never destroy data |
| Append-only financial records | Audit trail; corrections via reversal/adjustment |
| Private buckets for voice/CNIC/docs | PII security from day 1 |
