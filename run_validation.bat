@echo off
setlocal enabledelayedexpansion

set FLUTTER=C:\src\flutter\bin\flutter.bat
set APP_DIR=%~dp0app
set RESULTS=%~dp0validation_results.txt

echo ============================================================ > "%RESULTS%"
echo MUNSHI Dart 3.13 Compatibility Validation >> "%RESULTS%"
echo Run date: %DATE% %TIME% >> "%RESULTS%"
echo ============================================================ >> "%RESULTS%"
echo. >> "%RESULTS%"

cd /d "%APP_DIR%"

:: ── 1. Flutter version ──────────────────────────────────────────────────────
echo [1/6] flutter --version
echo [1/6] flutter --version >> "%RESULTS%"
"%FLUTTER%" --version >> "%RESULTS%" 2>&1
echo. >> "%RESULTS%"

:: ── 2. pub get ───────────────────────────────────────────────────────────────
echo [2/6] flutter pub get
echo [2/6] flutter pub get >> "%RESULTS%"
"%FLUTTER%" pub get >> "%RESULTS%" 2>&1
if errorlevel 1 (
    echo FAIL: pub get failed - see %RESULTS% for details
    echo RESULT: pub get = FAIL >> "%RESULTS%"
    goto :end
)
echo RESULT: pub get = PASS >> "%RESULTS%"
echo. >> "%RESULTS%"

:: ── 3. build_runner (Drift codegen only) ────────────────────────────────────
echo [3/6] dart run build_runner build
echo [3/6] dart run build_runner build >> "%RESULTS%"
"%FLUTTER%" pub run build_runner build --delete-conflicting-outputs >> "%RESULTS%" 2>&1
if errorlevel 1 (
    echo FAIL: build_runner failed
    echo RESULT: build_runner = FAIL >> "%RESULTS%"
    goto :analyze
)
echo RESULT: build_runner = PASS >> "%RESULTS%"
echo. >> "%RESULTS%"

:: ── 4. flutter analyze ───────────────────────────────────────────────────────
:analyze
echo [4/6] flutter analyze
echo [4/6] flutter analyze >> "%RESULTS%"
"%FLUTTER%" analyze >> "%RESULTS%" 2>&1
if errorlevel 1 (
    echo FAIL: flutter analyze found issues
    echo RESULT: flutter analyze = FAIL >> "%RESULTS%"
) else (
    echo RESULT: flutter analyze = PASS >> "%RESULTS%"
)
echo. >> "%RESULTS%"

:: ── 5. flutter test ──────────────────────────────────────────────────────────
echo [5/6] flutter test
echo [5/6] flutter test >> "%RESULTS%"
"%FLUTTER%" test >> "%RESULTS%" 2>&1
if errorlevel 1 (
    echo FAIL: flutter test
    echo RESULT: flutter test = FAIL >> "%RESULTS%"
) else (
    echo RESULT: flutter test = PASS >> "%RESULTS%"
)
echo. >> "%RESULTS%"

:: ── 6. flutter build web ─────────────────────────────────────────────────────
echo [6/6] flutter build web --release
echo [6/6] flutter build web --release >> "%RESULTS%"
"%FLUTTER%" build web --release >> "%RESULTS%" 2>&1
if errorlevel 1 (
    echo FAIL: flutter build web
    echo RESULT: flutter build web = FAIL >> "%RESULTS%"
) else (
    echo RESULT: flutter build web = PASS >> "%RESULTS%"
)

:end
echo. >> "%RESULTS%"
echo ============================================================ >> "%RESULTS%"
echo Validation complete. See full results above. >> "%RESULTS%"
echo ============================================================ >> "%RESULTS%"

echo.
echo Done. Results saved to: %RESULTS%
echo.
type "%RESULTS%"
