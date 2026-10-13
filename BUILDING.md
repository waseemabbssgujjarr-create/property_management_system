# Munshi — Build Instructions
**Target URL:** https://property.aderalabs.tech/  
**Flutter:** 3.47.6 | **Dart:** 3.13.x

---

## Quick Start (Recommended)

Double-click `app\fix_and_build.bat` — it runs all 9 steps automatically and produces `munshi-web.zip`.

---

## Manual Steps

From `C:\Users\dell\Downloads\Property Management System\app\`:

### 1. Clean stale state
```bat
rmdir /s /q .dart_tool
rmdir /s /q build
```

### 2. Repair pub cache (fixes build_runner_core missing)
```bat
C:\src\flutter\bin\flutter.bat pub cache repair
```

### 3. Get dependencies (regenerates .dart_tool + l10n)
```bat
C:\src\flutter\bin\flutter.bat pub get
```

### 4. Configure web platform
```bat
C:\src\flutter\bin\flutter.bat create . --platforms web
```
This adds `web/` icons, favicon, and service worker config.

### 5. Generate Drift code
```bat
C:\src\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs
```
Generates: `lib/core/offline/drift_database.g.dart`

### 6. Analyze (must have 0 errors)
```bat
C:\src\flutter\bin\flutter.bat analyze --no-fatal-warnings
```

### 7. Test
```bat
C:\src\flutter\bin\flutter.bat test
```

### 8. Build web release
```bat
C:\src\flutter\bin\flutter.bat build web --release --base-href "/"
```
Output: `build\web\`

### 9. Create deployment zip
```powershell
powershell -File create_zip.ps1
```
Output: `..\munshi-web.zip`

---

## What Was Fixed (Dart 3.13 Compatibility)

| Issue | Fix |
|-------|-----|
| `build_runner_core` missing | `pub cache repair` + clean `.dart_tool` |
| `riverpod_generator` analyzer 7.6 conflict | Removed — no `@riverpod` annotations exist |
| `CardTheme(` deprecated | → `CardThemeData(` |
| `DialogTheme(` deprecated | → `DialogThemeData(` |
| `SpeakOnHold` declared twice | Removed from `pressable.dart`; kept in `speak_button.dart` |
| `settings_screen.dart` `perms` undefined | Added `PermissionService` import + declaration |
| Supabase query `.range()` before filters | Moved filters before `.range()` in all repositories |
| Drift `tableName` column conflicts with `$tableName` | Renamed to `targetTable` in `SyncOperations` |
| `voice_recording.start()` `String?` type error | Split into `kIsWeb` branches with correct types |
| `voice_input.dart` `.cast()` extension conflict | Removed; use `AppElevation.medium` directly |
| `dart:io` on web | Platform-conditional stub via `file_support.dart` |
| `const comm = (expr).toInt()` not const | Removed `const` |
| `base64.decode() as Uint8List` cast | → `Uint8List.fromList(base64.decode(...))` |
| Financial test `const` expression | Changed to `final` |
| Web platform not configured | `flutter create . --platforms web` |

---

## Deploy to cPanel

1. Upload `munshi-web.zip` to your cPanel
2. In **File Manager**, navigate to `public_html/`
3. Upload and **Extract** the zip (files go directly into `public_html/`)
4. Ensure `public_html/index.html` exists
5. Visit https://property.aderalabs.tech/ — should show Munshi

**No path prefix needed** — the app is at the domain root.

---

## Environment Variables (Web)

The web build reads Supabase config from `.env.prod` (bundled as a Flutter asset).  
Before deploying, update `.env.prod` with your real Supabase URL and anon key:

```
SUPABASE_URL=https://your-prod-project.supabase.co
SUPABASE_ANON_KEY=your-prod-anon-key
```

**Never** put in `.env.prod`:
- `service_role` key
- DB password  
- `WA_API_KEY`
- `app.wa_credential_key`
- Any server-side secret
