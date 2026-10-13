# Munshi — Flutter Build Repair Report
**Date:** 2026-10-02 | **Target:** https://property.aderalabs.tech/

---

## 1. Root Cause of build_runner Failure

**Primary cause:** Stale `.dart_tool/` state from a previous failed resolution.

When `pub get` resolves `build_runner 2.16.1`, it writes package sources to `~/.pub-cache/`. If the cache download was interrupted, `.dart_tool/` references packages that don't exist locally, producing:

```
Couldn't resolve package 'build_runner_core'
Failed to compile .dart_tool/build/entrypoint/build.dart
```

**Fix:** 
1. Delete `.dart_tool/` so `.dart_tool/package_config.json` is regenerated cleanly
2. Run `flutter pub cache repair` to re-download any incomplete packages
3. Run `flutter pub get` to rebuild the full package graph

---

## 2. Final Dependency Versions

| Package | Version | Notes |
|---------|---------|-------|
| `flutter_riverpod` | 2.6.1 | Manual providers only — no codegen |
| `drift` | 2.35.1 | Up from 2.18.0 — Dart 3.13 compatible |
| `drift_dev` | 2.35.1 | Matching drift version |
| `build_runner` | 2.16.1 | Up from 2.4.15 — Dart 3.13 compatible |
| `analyzer` (transitive) | 14.4.0 | Up from 7.6.0 — **this was the blocker** |
| `supabase_flutter` | 2.18.0 | Up from 2.5.0 |
| `go_router` | 14.8.1 | Stable |

**Removed** (were pulling analyzer 7.6.0):
- `riverpod_generator`, `riverpod_annotation` — zero `@riverpod` annotations in codebase
- `injectable`, `injectable_generator` — zero `@injectable` annotations
- `freezed`, `freezed_annotation`, `json_serializable`, `json_annotation` — zero annotations
- `drift_flutter` — replaced by `drift/native.dart` directly

---

## 3. Source Files Changed

### Compilation fixes (errors → zero)

| File | Change |
|------|--------|
| `lib/widgets/primitives/pressable.dart` | Removed duplicate `SpeakOnHold` class (was also in `speak_button.dart`) |
| `lib/core/theme/app_theme.dart` | `CardTheme(` → `CardThemeData(` · `DialogTheme(` → `DialogThemeData(` |
| `lib/features/settings/screens/settings_screen.dart` | Added `permission_service.dart` import · added `perms` declaration |
| `lib/features/deals/repositories/deals_repository.dart` | Moved `.order().range()` after conditional filters (Supabase type fix) |
| `lib/features/inventory/repositories/inventory_repository.dart` | Same query builder fix |
| `lib/features/parties/repositories/parties_repository.dart` | Same query builder fix |
| `lib/features/money/repositories/money_repository.dart` | Same query builder fix |
| `lib/features/followups/repositories/followups_repository.dart` | Same query builder fix |
| `lib/features/home/repositories/dashboard_repository.dart` | Fixed RPC result cast (`as int?` → safe num cast) |
| `lib/core/offline/drift_database.dart` | Renamed `tableName` column → `targetTable` (Drift `$tableName` conflict) |
| `lib/core/offline/sync_engine.dart` | Updated `tableName:` → `targetTable:` in companion · `op.tableName` → `op.targetTable` |
| `lib/core/services/voice_recording_service.dart` | Split `recorder.start()` into `kIsWeb` branches (String? type fix) |
| `lib/widgets/primitives/voice_input.dart` | Removed `.cast()` extension (conflicted with `List.cast<T>()`) · `AppElevation.medium.cast()` → `AppElevation.medium` |
| `lib/core/services/encryption_service.dart` | `base64.decode() as Uint8List` → `Uint8List.fromList(base64.decode(...))` |
| `lib/app.dart` | Uncommented `AppLocalizations.delegate` · added l10n import |

### Platform/web files (new)
| File | Purpose |
|------|---------|
| `lib/core/platform/file_support.dart` | Conditional `dart:io` export |
| `lib/core/platform/file_support_native.dart` | `export 'dart:io' show File` |
| `lib/core/platform/file_support_web.dart` | File stub for web compilation |
| `lib/core/offline/db_connection_native.dart` | NativeDatabase on mobile/desktop |
| `lib/core/offline/db_connection_stub.dart` | NativeDatabase.memory() on web |
| `web/index.html` | Flutter web bootstrap |
| `web/manifest.json` | PWA manifest |

### Test fix
| File | Change |
|------|--------|
| `test/features/money/financial_integrity_test.dart` | `const comm = (expr).toInt()` → `final comm` |
| `test/core/offline/sync_engine_test.dart` | Rewrote to use `ProviderContainer` (was calling Notifier internals directly) |

---

## 4. Generated Files After build_runner

```
lib/core/offline/drift_database.g.dart   ← Drift table definitions
.dart_tool/flutter_gen/gen_l10n/          ← AppLocalizations (from pub get)
```

---

## 5. Build Commands to Run

```bat
cd app
fix_and_build.bat
```

Or manually:
```bat
rmdir /s /q .dart_tool
C:\src\flutter\bin\flutter.bat pub cache repair
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat create . --platforms web
C:\src\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs
C:\src\flutter\bin\flutter.bat analyze --no-fatal-warnings
C:\src\flutter\bin\flutter.bat test
C:\src\flutter\bin\flutter.bat build web --release --base-href "/"
powershell -File create_zip.ps1
```

---

## 6. Expected Results

| Step | Expected |
|------|---------|
| `pub cache repair` | "Downloading packages..." then done |
| `pub get` | "Got dependencies!" |
| `flutter create . --platforms web` | "Wrote web/index.html" etc. |
| `build_runner` | "Succeeded after..." |
| `drift_database.g.dart` | File exists at `lib/core/offline/drift_database.g.dart` |
| `flutter analyze` | "No issues found!" (with `--no-fatal-warnings`) |
| `flutter test` | "All tests passed!" |
| `flutter build web` | "✓ Built build/web" |
| `munshi-web.zip` | Located at project root (parent of `app/`) |

---

## 7. Deployment

Upload `munshi-web.zip` contents to cPanel `public_html/`:
- Extract the zip — all files go directly into `public_html/`
- Verify `public_html/index.html` exists
- The app runs at `https://property.aderalabs.tech/` (root — no path prefix)

**Before deploying**, update `app/.env.prod` with real Supabase credentials.

---

## 8. Remaining Warnings (Non-Blocking)

- `withAlpha()` deprecation (~80 occurrences) — use `withValues(alpha:)` in a follow-up
- `withOpacity()` deprecation (~20 occurrences) — same
- Font families `NotoNastaliqUrdu`, `NotoNaskhArabic` not found (fallback to system) — add font files before production
- Voice OTP / SMS OTP use stub providers — configure `TWILIO_*` or `VOICE_API_*` secrets in Supabase Edge Functions before live login

---

## 9. What Was NOT Changed

- Supabase schema / migrations
- RLS policies  
- Authentication architecture
- WhatsApp API integration  
- Money engine / commission logic
- Offline sync architecture
- Provider declarations (all hand-written, zero codegen)
- Business behavior
