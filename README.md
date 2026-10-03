# Munshi — The Digital Munshi
**Property Dealer Operating System for Pakistan**

> "Parhne ki zaroorat nahi — yeh bol kar batata hai ke aap ka kitna paisa banta hai."  
> (No reading needed — it tells you aloud how much money you've made.)

---

## What is Munshi?

Munshi is a **mobile-first, offline-first, Urdu-voice-first** operating system for Pakistani property dealers (DHA/Bahria-type markets). It replaces the paper *bahi khata*, Excel sheet, and WhatsApp memory with one app the owner checks daily — by **looking and listening, not reading**.

**Target:** 2–10 person dealerships · Rs 4,000–9,000/mo · Phase 1 MVP → $1,000 MRR

---

## Key Differentiators

| Gap | Munshi | All competitors |
|-----|--------|----------------|
| No-read UI (voice + icons + photos) | ✅ | ❌ |
| WhatsApp Day 1/3/7 automation | ✅ (Phase 2) | ❌ |
| Native offline-first Android + Urdu script | ✅ | ❌ |
| Staff commission earned vs paid (hearable) | ✅ | ❌ |
| Dealer-native: token/bayana/registry pipeline | ✅ | ❌ |

---

## Tech Stack

| Layer | Tech |
|-------|------|
| Mobile app | Flutter 3.x (Android-first) |
| Local DB | Drift + SQLite (offline-first) |
| Backend | Supabase (Postgres + Auth + Edge Functions + Storage) |
| State | Riverpod 2 |
| Routing | GoRouter |
| Voice | flutter_tts (ur-PK) + speech_to_text |
| WhatsApp | Meta Cloud API (Phase 2) |

---

## Project Structure

```
munshi/
├── app/                    Flutter application
│   ├── lib/
│   │   ├── core/           Config, theme, routing, services, offline engine
│   │   ├── features/       auth, home, deals, inventory, parties, money, ...
│   │   ├── widgets/        Reusable UI: primitives, deal, money, shared
│   │   └── shell/          Bottom nav shell
│   └── test/               Unit + integration tests
├── supabase/
│   ├── migrations/         SQL migrations (schema + RPC functions)
│   ├── functions/          Edge Functions (Deno/TypeScript)
│   └── seed/               Demo dealer data
├── ARCHITECTURE.md         System architecture
├── DATABASE.md             Schema design + invariants
├── SECURITY.md             Security model + RLS
├── SYNC-DESIGN.md          Offline sync design
└── PERMISSIONS.md          RBAC permission matrix
```

---

## Getting Started

### Prerequisites

- Flutter 3.19+ (`flutter doctor`)
- Dart 3.3+
- Supabase CLI (`npm install -g supabase`)
- Node.js 18+ (for Edge Functions)

### 1. Clone and install

```bash
cd app
flutter pub get
```

### 2. Configure environment

```bash
cp .env.dev .env.dev.local
# Edit .env.dev.local with your Supabase URL and anon key
```

### 3. Start local Supabase

```bash
supabase start
supabase db push
supabase db seed --seed-file supabase/seed/demo_dealer.sql
```

### 4. Run the app

```bash
# Development
flutter run -t lib/main_dev.dart

# With demo dealer pre-seeded — use OTP: 123456
# Phone: +923001234567
```

---

## Build Flavors

| Flavor | Entry point | Environment |
|--------|------------|-------------|
| dev | `main_dev.dart` | Local Supabase, all features on |
| staging | `main_staging.dart` | Staging Supabase, seeded data |
| prod | `main.dart` | Production, restricted feature flags |

---

## Running Tests

```bash
# Unit tests
flutter test

# Specific test file
flutter test test/core/utils/money_formatter_test.dart
flutter test test/features/money/financial_integrity_test.dart
flutter test test/core/services/permission_service_test.dart
```

---

## Literacy Acceptance Test (Release Blocker)

Before any Phase 1 release, a user who **cannot comfortably read** must complete:
1. Add a deal — without reading any instruction
2. Record token payment — using only icons and number pad
3. Hear commission via the 🔊 button
4. Complete a follow-up — swipe or tap

**2+ failures = redesign, don't ship.**

---

## Architecture Documents

| Document | Contents |
|----------|----------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System overview, Flutter structure, tech decisions |
| [DATABASE.md](DATABASE.md) | Full schema, invariants, indexes, triggers |
| [SECURITY.md](SECURITY.md) | RLS policies, secrets, threat model |
| [SYNC-DESIGN.md](SYNC-DESIGN.md) | Offline-first sync architecture |
| [PERMISSIONS.md](PERMISSIONS.md) | Role-based permission matrix |
| [BUILD-STATUS.md](BUILD-STATUS.md) | Phase progress, feature status |
| [IMPLEMENTATION-AUDIT.md](IMPLEMENTATION-AUDIT.md) | Architectural decisions and risks |

---

## Phase Roadmap

| Phase | Status | Description |
|-------|--------|-------------|
| 1 — Foundation | ✅ Built | Scaffold, auth, home, inventory, parties, deals, money, followups, offline |
| 2 — WhatsApp | 🔲 Next | Day 1/3/7 automation, inbox-lite, demand matching |
| 3 — Network | 🔲 Later | Dealer circles, documents, billing, admin |
| 4 — Web | 🔲 Later | Marketing site (Next.js), owner console |

---

## Financial Invariants (Never Violate)

- `amount_rs >= 0` (enforced at DB and app layer)
- `deal_splits.pct` sums to **exactly 100%** per deal (DB trigger)
- Payments are **INSERT-ONLY** — no UPDATE or DELETE ever
- Receipt numbers are sequential per dealer per year (concurrency-safe)
- Stage transitions are **forward-only** (state machine enforced at repo layer)
- Financial conflicts surface visibly — never silently resolved

---

## Key Commands

```bash
# Generate Drift code
flutter pub run build_runner build --delete-conflicting-outputs

# Format
dart format lib/

# Analyze
flutter analyze

# Deploy Edge Functions (staging)
supabase functions deploy --project-ref YOUR_PROJECT_ID
```

---

*Built for Pakistan's property dealers. Hear your money. Don't read it.*

---

## Phase 1 Audit (2026-10-02)

See [PHASE-1-FINAL-AUDIT.md](PHASE-1-FINAL-AUDIT.md) for full findings.

**Phase 2 Gate: YELLOW** — all P0 compilation blockers fixed. P1 setup items required before pilot onboarding.

### Critical setup steps before first run

1. **Register JWT Claims Hook** in Supabase Dashboard → Authentication → Hooks  
   Function: `public.custom_access_token_hook` (defined in migration 003)

2. **Generate Drift code:**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Apply all migrations:**
   ```bash
   supabase db push
   ```

4. **Set Edge Function secrets:**
   ```bash
   supabase secrets set META_APP_SECRET=<value>
   supabase secrets set META_WA_TOKEN=<value>
   supabase secrets set META_PHONE_NUMBER_ID=<value>
   ```
