@echo off
:: MUNSHI — Create deployment preparation branch and commit
:: Run this from the repo root:
::   cd "C:\Users\dell\Downloads\Property Management System"
::   git_deploy_branch.bat

set GIT="C:\Program Files\Git\cmd\git.exe"
set BRANCH=deployment-prep/vps-almalinux

echo === MUNSHI Git Deployment Branch ===
echo.

:: Check current status
%GIT% status --short
echo.

:: Create branch
%GIT% checkout -b %BRANCH% 2>nul || %GIT% checkout %BRANCH%
echo Branch: %BRANCH%

:: Stage deployment artifacts
%GIT% add deploy/vps/README.md
%GIT% add deploy/vps/nginx.conf.example
%GIT% add deploy/vps/deploy.sh
%GIT% add deploy/vps/health-check.sh
%GIT% add deploy/vps/rollback.md
%GIT% add deploy/vps/environment.example

:: Stage documentation
%GIT% add BUILDING.md
%GIT% add BUILD-REPAIR-REPORT.md
%GIT% add DART313-COMPATIBILITY.md
%GIT% add PILOT-READINESS-AUDIT.md

:: Stage app source fixes
%GIT% add app/pubspec.yaml
%GIT% add app/pubspec.lock
%GIT% add app/l10n.yaml
%GIT% add app/web/index.html
%GIT% add app/web/manifest.json
%GIT% add app/fix_and_build.bat
%GIT% add app/create_zip.ps1
%GIT% add app/.gitignore

:: Source fixes
%GIT% add app/lib/app.dart
%GIT% add app/lib/core/theme/app_theme.dart
%GIT% add app/lib/core/offline/drift_database.dart
%GIT% add app/lib/core/offline/sync_engine.dart
%GIT% add app/lib/core/offline/sync_state.dart
%GIT% add app/lib/core/offline/db_connection_native.dart
%GIT% add app/lib/core/offline/db_connection_stub.dart
%GIT% add app/lib/core/platform/file_support.dart
%GIT% add app/lib/core/platform/file_support_native.dart
%GIT% add app/lib/core/platform/file_support_web.dart
%GIT% add app/lib/core/services/voice_recording_service.dart
%GIT% add app/lib/core/services/encryption_service.dart
%GIT% add app/lib/core/router/app_router.dart
%GIT% add app/lib/widgets/primitives/pressable.dart
%GIT% add app/lib/widgets/primitives/voice_input.dart
%GIT% add app/lib/features/settings/screens/settings_screen.dart
%GIT% add app/lib/features/deals/repositories/deals_repository.dart
%GIT% add app/lib/features/inventory/repositories/inventory_repository.dart
%GIT% add app/lib/features/parties/repositories/parties_repository.dart
%GIT% add app/lib/features/money/repositories/money_repository.dart
%GIT% add app/lib/features/followups/repositories/followups_repository.dart
%GIT% add app/lib/features/home/repositories/dashboard_repository.dart
%GIT% add app/test/features/money/financial_integrity_test.dart
%GIT% add app/test/core/offline/sync_engine_test.dart

:: Asset directories (placeholders)
%GIT% add app/assets/

:: Commit
%GIT% commit -m "deploy: VPS deployment preparation for property.aderalabs.tech

Changes:
- Add deploy/vps/ deployment artifacts:
  - deploy.sh (build + symlink + nginx reload)
  - nginx.conf.example (SPA routing, TLS, gzip, security headers)
  - health-check.sh (9-point post-deploy verification)
  - rollback.md (symlink rollback procedure)
  - environment.example (public values only — no secrets)
  - README.md (complete VPS setup guide)

- Fix Dart 3.13 / analyzer 14.4.0 compatibility:
  - Remove riverpod_generator/annotation (zero @riverpod annotations)
  - Remove injectable/freezed/json_serializable (all unused)
  - Remove drift_flutter (use drift/native.dart directly)
  - Drift SyncOperations: tableName column -> targetTable
  - CardTheme/DialogTheme -> CardThemeData/DialogThemeData
  - Remove duplicate SpeakOnHold from pressable.dart
  - Fix Supabase query builder: .range() after conditional filters
  - Fix dart:io for web: platform-conditional file_support.dart
  - Fix voice_recording_service.dart kIsWeb branching
  - Fix encryption_service.dart Uint8List casts
  - Fix financial_integrity_test.dart const expression

- Documentation:
  - BUILDING.md: Windows build instructions
  - BUILD-REPAIR-REPORT.md: what changed and why
  - DART313-COMPATIBILITY.md: compatibility fix log
  - PILOT-READINESS-AUDIT.md: full audit with PASS/FAIL/NOT TESTED

Platform: AlmaLinux 9.8 / Nginx / Flutter web static hosting
Domain: https://property.aderalabs.tech
Gate: YELLOW (code complete; VPS execution required for GREEN)"

echo.
echo Committed to branch: %BRANCH%
echo.
echo Next steps:
echo   1. Review the commit: git log --oneline -5
echo   2. When ready: git push -u origin %BRANCH%
echo   3. DO NOT merge to main until PILOT-READINESS-AUDIT.md shows GREEN
