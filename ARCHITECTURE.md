# ARCHITECTURE — Munshi
**Version:** 1.0 | **Date:** 2026-10-02

---

## 1. System Overview

Munshi is a **multi-tenant SaaS property dealer operating system** for Pakistani brokerage firms.

```
┌─────────────────────────────────────────────────────────┐
│                     MUNSHI PLATFORM                      │
├───────────────┬──────────────┬──────────────────────────┤
│  Flutter App  │  Owner Web   │   Next.js Marketing      │
│  (Android/    │  Console     │   Site                   │
│   iOS)        │  (Flutter    │   (Phase 16)             │
│               │   Web)       │                          │
└───────┬───────┴──────┬───────┴──────────────────────────┘
        │              │
        ▼              ▼
┌───────────────────────────────────────────────────────────┐
│                    SUPABASE BACKEND                        │
│                                                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  │
│  │ Postgres │  │   Auth   │  │ Realtime │  │ Storage │  │
│  │   + RLS  │  │ Phone OTP│  │          │  │ Buckets │  │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘  │
│                                                           │
│  ┌───────────────────────────────────────────────────┐   │
│  │             EDGE FUNCTIONS                        │   │
│  │  otp-send │ whatsapp-webhook │ sequence-runner    │   │
│  │  tts-render │ sharecard-render │ match-engine     │   │
│  │  invoice-runner │ reminder-runner │ export-csv    │   │
│  └───────────────────────────────────────────────────┘   │
└──────────────────────────────────────┬────────────────────┘
                                       │
                              ┌────────▼────────┐
                              │  Meta WhatsApp   │
                              │  Cloud API       │
                              │  (Phase 9+)      │
                              └─────────────────┘
```

---

## 2. Surfaces

| Surface | Tech | Priority | Notes |
|---|---|---|---|
| Dealer mobile app | Flutter 3.x | P0 | Android-first; offline-first |
| Owner web console | Flutter Web | P3 | Desktop layout reusing widgets |
| Marketing site | Next.js App Router | P4 | SSR, Urdu-first, SEO |
| Share cards / brochures | Edge Function + canvas | P2 | 1080×1350, <3s render |

---

## 3. Flutter App Architecture

**Pattern:** Feature-first folder structure with clean architecture layers.

```
lib/
├── core/
│   ├── config/           # Environment, feature flags, app config
│   ├── theme/            # Design tokens, colors, typography, spacing
│   ├── router/           # GoRouter routes + guards
│   ├── di/               # Dependency injection (get_it + injectable)
│   ├── utils/            # MoneyFmt, DateFmt, permissions, validators
│   ├── services/         # TTS, STT, voice recording, camera, file
│   ├── network/          # Supabase client, API base, error handling
│   ├── offline/          # Drift DB, sync queue, idempotency engine
│   ├── state/            # App-level state: mode (simple/detail), locale
│   └── errors/           # Domain errors, error mapper, error UX
│
├── features/
│   ├── auth/             # OTP, onboarding, session
│   ├── tenancy/          # Org, office, roles, staff invite
│   ├── home/             # Aaj ka hisaab, dashboard
│   ├── inventory/        # Properties, photos
│   ├── parties/          # Buyers, sellers, investors
│   ├── deals/            # Pipeline, state machine, events
│   ├── money/            # Payments, receipts, commission, splits
│   ├── followups/        # Follow-up engine
│   ├── staff/            # Staff management, commission earned/paid
│   ├── documents/        # Document vault
│   ├── search/           # Global search + voice search
│   ├── notifications/    # Notification center
│   ├── whatsapp/         # Phase 2: WA connect, inbox, sequences
│   ├── matching/         # Phase 2: demand matching
│   ├── reports/          # Phase 2: P&L, source ROI, performance
│   ├── billing/          # Phase 3: subscription, invoices
│   ├── import/           # Excel import wizard
│   ├── settings/         # Language, mode, voice, subscription
│   └── admin/            # Platform admin (separate flavor)
│
├── widgets/
│   ├── primitives/       # Pressable, SpeakButton, VoiceInput, NumberPad
│   │                     # PhotoCapture, MethodChips, MoneyDisplay
│   ├── deal/             # StageStrip, DealCard, TokenToggle
│   ├── party/            # PartyCard, ContactButtons
│   ├── money/            # ReceiptCard, SplitStepper, MoneyInput
│   ├── followup/         # FollowUpCard, SwipeActions
│   ├── layout/           # BottomNavShell, AppScaffold, Sheets
│   └── shared/           # Skeletons, EmptyStates, ErrorStates, Toasts
│
├── l10n/                 # ARB files: app_ur.arb, app_en.arb
├── gen/                  # Generated: l10n, assets, icons
└── main_*.dart           # main_dev.dart, main_staging.dart, main_prod.dart
```

---

## 4. State Management

**Choice:** Riverpod 2.x (AsyncNotifier pattern)

Rationale:
- Compile-safe, no BuildContext required in service layer
- Excellent offline-first integration (state persists with Drift)
- Provider scoping supports multi-tenant isolation per session

Pattern per feature:
```
repository (data access) → notifier (business logic) → consumer (UI)
```

---

## 5. Routing

**Choice:** GoRouter with shell routes.

Guards:
- `authGuard` — redirect unauthenticated users to OTP
- `onboardingGuard` — redirect incomplete profiles to onboarding
- `modeGuard` — deep links resolve to appropriate Simple/Detail screen
- `roleGuard` — block routes based on user role + permissions

---

## 6. Environment Configuration

Three flavors:
```
dev     — local Supabase, verbose logs, all feature flags on
staging — Supabase staging project, seeded demo data
prod    — Supabase prod, restricted logs, feature flags as config
```

Configuration loaded from `.env.*` files (never committed) and Supabase `app_config` table for runtime values.

---

## 7. Dependency Injection

Using `get_it` + `injectable` for compile-time safe DI.

Key singletons:
- `SupabaseClient`
- `DriftLocalDb`
- `SyncEngine`
- `TTSService`
- `STTService`
- `FeatureFlagService`
- `MoneyFormatter`
- `AppConfig`

---

## 8. Key Architectural Decisions

| Decision | Chosen | Alternative | Reason |
|---|---|---|---|
| State | Riverpod 2 | Bloc/Provider | Compile-safe, DI-friendly |
| Routing | GoRouter | auto_route | Shell routes, deep links, guards |
| Local DB | Drift | Hive/Isar | Type-safe SQL, Supabase schema alignment |
| DI | get_it + injectable | manual | Clean, testable, code-gen |
| Forms | reactive_forms | flutter_form_builder | Better validation composition |
| Images | flutter_image_compress + cached_network_image | — | Compression + cache |
| Camera | image_picker + camera | — | Both needed |
| Audio | record + just_audio | — | Record input, play output |
| TTS | flutter_tts | — | Platform ur-PK voice |
| STT | speech_to_text | — | On-device, offline capable |

---

## 9. Monorepo Structure

```
munshi/                    ← root
├── app/                   ← Flutter app (primary surface)
├── supabase/              ← All Supabase config, migrations, functions
│   ├── migrations/        ← SQL migration files
│   ├── functions/         ← Edge Functions (Deno/TypeScript)
│   └── seed/              ← Demo dealer seed data
├── web/                   ← Next.js marketing site (Phase 16)
├── shared/                ← Shared constants, types (TypeScript)
├── docs/                  ← Architecture docs (this file + siblings)
└── scripts/               ← Dev scripts, migration runners
```
