# Munshi — Dart 3.13 / Riverpod Compatibility Fix
**Date:** 2026-10-02

---

## Root Cause

`build_runner` failed with:

```
Missing implementation of visitDotShorthandPropertyAccess
SDK language version 3.13.0 is newer than analyzer language version 3.9.0
```

**Cause:** `riverpod_generator ^2.4.3` → `riverpod_analyzer_utils 0.5.x` → `analyzer 7.6.x`  
Analyzer 7.6.x does not understand Dart 3.13 syntax.

**Key finding:** `@riverpod` / `@Riverpod` annotations are used **zero times** in the codebase.  
`riverpod_generator`, `riverpod_annotation`, `injectable`, `injectable_generator`,  
`freezed`, `freezed_annotation`, `json_serializable`, `json_annotation` — all **unused**.

---

## Fix Applied

### 1. pubspec.yaml — removed unused dev dependencies

**Removed from dev_dependencies:**
- `riverpod_generator` (was `^2.4.3`) — unused, caused analyzer 7.6.x constraint
- `injectable_generator` (was `^2.4.3`) — unused
- `freezed` (was `^2.5.7`) — unused
- `json_serializable` (was `^6.8.0`) — unused

**Removed from dependencies:**
- `riverpod_annotation` (was `^2.3.5`) — unused
- `injectable` (was `^2.4.2`) — unused
- `freezed_annotation` (was `^2.4.4`) — unused
- `json_annotation` (was `^4.9.0`) — unused
- `drift_flutter` (was `^0.2.1`) — replaced by `drift/native.dart` directly
- `camera` — unused (image_picker covers all cases)
- `open_file` — replaced by url_launcher
- `lottie`, `dotted_border`, `excel`, `reactive_forms`, `flutter_vibrate`, `audio_waveforms` — all unused

**Updated versions (intentional from previous session):**
- `intl: ^0.20.3` (was `^0.19.0` — required by flutter_localizations)
- `share_plus: ^12.0.2` (was `^9.0.0` — conflicted with drift/web)

**Updated versions (Dart 3.13 compatible):**
- `drift: ^2.21.0` → resolved `2.35.1`
- `drift_dev: ^2.21.0` → resolved `2.35.1`
- `build_runner: ^2.4.15` → resolved `2.16.1`

### 2. New resolved analyzer version

- **Old:** `analyzer 7.6.0` (incompatible with Dart 3.13)
- **New:** `analyzer 14.4.0` (Dart 3.13 compatible — pulled in by `drift_dev 2.35.1`)

### 3. Web compatibility (dart:io guards)

Added platform-conditional File import to support `flutter build web`:

**New files:**
- `lib/core/platform/file_support.dart` — conditional export
- `lib/core/platform/file_support_native.dart` — `export 'dart:io' show File`
- `lib/core/platform/file_support_web.dart` — File stub class
- `lib/core/offline/db_connection_native.dart` — NativeDatabase for mobile
- `lib/core/offline/db_connection_stub.dart` — NativeDatabase.memory() for web

**Modified files (dart:io → platform stub):**
- `lib/core/offline/drift_database.dart`
- `lib/core/offline/sync_engine.dart`
- `lib/core/services/voice_recording_service.dart`
- `lib/widgets/primitives/photo_capture.dart`
- `lib/features/inventory/repositories/inventory_repository.dart`
- `lib/features/money/repositories/money_repository.dart`

### 4. Other fixes
- `lib/core/offline/sync_state.dart` — removed unused `flutter/material.dart` import
- `lib/core/services/encryption_service.dart` — fixed `as Uint8List` cast → `Uint8List.fromList()`
- `app/l10n.yaml` — moved from `lib/l10n/l10n.yaml` to project root (required by Flutter)
- `app/lib/app.dart` — uncommented `AppLocalizations.delegate`
- `app/lib/app.dart` — added generated l10n import
- `test/core/offline/sync_engine_test.dart` — rewrote to use `ProviderContainer`
- Asset directories created: `assets/images/`, `assets/icons/`

---

## Files Changed

| File | Change |
|------|--------|
| `pubspec.yaml` | Removed 11 unused deps; upgraded drift, build_runner |
| `lib/core/platform/file_support.dart` | NEW — conditional File export |
| `lib/core/platform/file_support_native.dart` | NEW — dart:io export for native |
| `lib/core/platform/file_support_web.dart` | NEW — File stub for web |
| `lib/core/offline/db_connection_native.dart` | NEW — NativeDatabase for native |
| `lib/core/offline/db_connection_stub.dart` | NEW — in-memory DB for web |
| `lib/core/offline/drift_database.dart` | Use conditional db connection import |
| `lib/core/offline/sync_engine.dart` | Replace dart:io with platform stub |
| `lib/core/offline/sync_state.dart` | Remove unused flutter/material.dart import |
| `lib/core/services/voice_recording_service.dart` | Replace dart:io; kIsWeb guard |
| `lib/core/services/encryption_service.dart` | Fix Uint8List cast |
| `lib/widgets/primitives/photo_capture.dart` | Replace dart:io; kIsWeb guard |
| `lib/features/inventory/repositories/inventory_repository.dart` | Replace dart:io |
| `lib/features/money/repositories/money_repository.dart` | Replace dart:io |
| `lib/app.dart` | Enable AppLocalizations; add l10n import |
| `l10n.yaml` | NEW at project root (was inside lib/l10n/) |
| `test/core/offline/sync_engine_test.dart` | Rewrite using ProviderContainer |

---

## Commands to Run

From `C:\Users\dell\Downloads\Property Management System\app\`:

```bat
:: Step 1 — Install dependencies (lockfile already resolved)
C:\src\flutter\bin\flutter.bat pub get

:: Step 2 — Generate Drift code (only drift_dev now — no riverpod_generator)
C:\src\flutter\bin\flutter.bat pub run build_runner build --delete-conflicting-outputs

:: Step 3 — Static analysis
C:\src\flutter\bin\flutter.bat analyze

:: Step 4 — Unit tests
C:\src\flutter\bin\flutter.bat test

:: Step 5 — Web release build
C:\src\flutter\bin\flutter.bat build web --release
```

Or run the PowerShell script:
```bat
powershell -ExecutionPolicy Bypass -File run_all.ps1
```

---

## Expected Results

| Step | Expected outcome |
|------|-----------------|
| `pub get` | Resolving 150+ deps; no version conflicts |
| `build_runner` | Generates only `drift_database.g.dart`; no riverpod_generator |
| `flutter analyze` | No errors (warnings for unused imports acceptable) |
| `flutter test` | 6 test files, ~59 tests, all passing |
| `flutter build web` | Build output in `build/web/`; no dart:io errors |

---

## What Was NOT Changed

- Supabase schema / migrations
- RLS policies
- Authentication architecture  
- WhatsApp API integration
- Money engine business logic
- Offline sync architecture
- Provider declarations (all hand-written, no codegen)
- Riverpod API usage (`Consumer*`, `Notifier`, `AsyncNotifier`, `Provider`, etc.)
