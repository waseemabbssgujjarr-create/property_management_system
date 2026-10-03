# BUILD STATUS — Munshi
**Last updated:** 2026-10-02

---

## Phase Overview

| Phase | Name | Status | Blockers |
|---|---|---|---|
| 1 | Foundation (scaffold, primitives, design system) | 🔄 In Progress | — |
| 2 | Auth + Tenancy | ⏳ Pending | Phase 1 |
| 3 | Inventory + Parties | ⏳ Pending | Phase 2 |
| 4 | Deal Engine | ⏳ Pending | Phase 3 |
| 5 | Money Engine | ⏳ Pending | Phase 4 |
| 6 | Home + Owner Experience | ⏳ Pending | Phase 5 |
| 7 | Offline Engine | ⏳ Pending | Phase 6 |
| 8 | Documents + Reports | ⏳ Pending | Phase 7 |
| 9 | WhatsApp Foundation | ⏳ Pending | Phase 8 |
| 10 | WhatsApp Automation | ⏳ Pending | Phase 9 |
| 11 | Demand Matching + Sharing | ⏳ Pending | Phase 10 |
| 12 | Team + Network | ⏳ Pending | Phase 11 |
| 13 | Billing | ⏳ Pending | Phase 12 |
| 14 | Platform Admin | ⏳ Pending | Phase 13 |
| 15 | Owner Web Console | ⏳ Pending | Phase 14 |
| 16 | Public Website | ⏳ Pending | Phase 15 |
| 17 | Production Hardening | ⏳ Pending | Phase 16 |

---

## Phase 1 — Foundation — ✅ AUDIT COMPLETE

| Feature | Status | Notes |
|---------|--------|-------|
| Project scaffold | ✅ | Flutter 3.x, Material 3 |
| Design tokens | ✅ | Colors, typography, spacing |
| Localization (ur/en, RTL) | ✅ | Full ARB files |
| No-read primitives | ✅ | Pressable, SpeakButton (fixed), VoiceInput (fixed), NumberPad (fixed), etc. |
| DB migration v1 | ✅ | Full schema + RLS + triggers |
| DB migration v2 | ✅ | RPC functions |
| DB migration v3 | ✅ | RLS fixes, JWT hook, audit_log policy |
| Auth (OTP + Voice OTP UI) | ✅ | Wired; voice call is stub — P1 |
| Splash screen (auth check) | ✅ FIXED | Now reads auth state and routes correctly |
| GoRouter auth guard | ✅ FIXED | `redirect:` callback wired |
| Onboarding | ✅ | Direct Supabase — needs repository (P1) |
| Session provider | ✅ FIXED | Import moved to correct position |
| Permission service | ✅ | All 30+ permissions tested |
| Tenancy repository | ✅ | |
| Home screen (Aaj ka Hisaab) | ✅ | Commission hero, 3 buttons, stage strip |
| Inventory screen | ✅ | Photo grid, status badges |
| Parties screen | ✅ FIXED | Call button now launches dialer |
| Deal engine | ✅ | State machine, events, splits |
| NayaDeal wizard | ✅ FIXED | Steps now wired; creates buyer party |
| Money engine | ✅ FIXED | Append-only reversal |
| Paisa Aya/Gaya | ✅ | 20-second flows |
| Staff screen | ✅ FIXED | Voice pattern fixed |
| Follow-ups | ✅ FIXED | Call button now launches dialer |
| Search | ✅ | Voice + text |
| Notifications | ✅ | |
| Drift offline DB | ✅ FIXED | NativeDatabase path fixed |
| Sync engine | ✅ FIXED | `dart:io` import moved to top-level |
| Sync status UI | ✅ | Pulsing indicator + detail sheet |
| Settings | ✅ | Mode, voice, language, sign out |

## Phase 2 Gate: YELLOW

P1 items required before pilot onboarding:
- [ ] Register JWT custom claims hook in Supabase Dashboard
- [ ] Integrate real OTP delivery (WhatsApp template + SMS fallback)
- [ ] Set META_APP_SECRET in Edge Function secrets
- [ ] Create wa_enrollments table migration
- [ ] Create send-staff-invite Edge Function
- [ ] Add CNIC encryption in party model

---

## Kill Criteria (per roadmap)

- [ ] <3 paid pilots → do not proceed to Phase 2
- [ ] Trial-to-paid <30% after 20 trials → fix onboarding
- [ ] Pro upgrade <20% of base after Phase 2 → revisit automation
- [ ] Literacy acceptance fails with 2+ pilot owners → redesign, don't ship
- [ ] Any financial invariant fails → block release

---

## Literacy Acceptance Test — RELEASE BLOCKER

Status: ⏳ Not yet testable (Phase 1 incomplete)

Requirements (must pass before Phase 1 ships):
- [ ] Add a deal without reading
- [ ] Record token payment without reading
- [ ] Hear commission via speaker
- [ ] Complete follow-up without reading
- [ ] 5 dealers tested, max 1 failure
