@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

::  MUNSHI — Complete repair + build script
::  Run from:  C:\Users\dell\Downloads\Property Management System\app\
::  Double-click or:  cmd /c fix_and_build.bat

set "FL=C:\src\flutter\bin\flutter.bat"
set "DART=C:\src\flutter\bin\dart.bat"
set "APP=%~dp0"
set "ROOT=%APP%.."
set "LOG=%APP%build_log.txt"
set "PASS_COUNT=0"
set "FAIL_STEP="

if not exist "%FL%" (
    echo ERROR: Flutter not found at %FL%
    echo        Edit FL= variable in this script to your flutter.bat path.
    pause
    exit /b 1
)

cd /d "%APP%"
echo Working dir: %CD%
echo Flutter:     %FL%
echo.

echo ============================================================ > "%LOG%"
echo MUNSHI Build Log — %DATE% %TIME% >> "%LOG%"
echo Flutter: %FL% >> "%LOG%"
echo ============================================================ >> "%LOG%"

:: ══════════════════════════════════════════════════════════════
:: STEP 1 — Clean stale artifacts
:: ══════════════════════════════════════════════════════════════
call :header "1/9" "Clean stale artifacts"
if exist ".dart_tool" (
    rmdir /s /q ".dart_tool" 2>>"%LOG%"
    echo     Removed .dart_tool
)
if exist "build" (
    rmdir /s /q "build" 2>>"%LOG%"
    echo     Removed build/
)
call :pass "Clean"

:: ══════════════════════════════════════════════════════════════
:: STEP 2 — Repair pub cache  (fixes build_runner_core missing)
:: ══════════════════════════════════════════════════════════════
call :header "2/9" "Repair pub cache"
"%FL%" pub cache repair >> "%LOG%" 2>&1
:: Non-fatal — cache repair may warn about some packages
call :pass "Pub cache repair"

:: ══════════════════════════════════════════════════════════════
:: STEP 3 — flutter pub get
:: ══════════════════════════════════════════════════════════════
call :header "3/9" "flutter pub get"
"%FL%" pub get >> "%LOG%" 2>&1
if errorlevel 1 (
    call :fail "pub get"
    goto :showlog
)
call :pass "pub get"

:: ══════════════════════════════════════════════════════════════
:: STEP 4 — Configure Flutter web platform
::          flutter create overwrites web/ with correct icons/favicon
::          --platforms web won't touch lib/ or test/ files
:: ══════════════════════════════════════════════════════════════
call :header "4/9" "Configure web platform"
"%FL%" create . --platforms web >> "%LOG%" 2>&1
if not exist "web\index.html" (
    call :fail "web platform (web\index.html missing)"
    goto :showlog
)
call :pass "Web platform"

:: ══════════════════════════════════════════════════════════════
:: STEP 5 — Generate Drift code  (build_runner)
:: ══════════════════════════════════════════════════════════════
call :header "5/9" "dart run build_runner build"
"%DART%" run build_runner build --delete-conflicting-outputs >> "%LOG%" 2>&1
if errorlevel 1 (
    call :fail "build_runner"
    goto :showlog
)
if not exist "lib\core\offline\drift_database.g.dart" (
    echo     ERROR: drift_database.g.dart not generated >> "%LOG%"
    call :fail "build_runner (drift_database.g.dart missing)"
    goto :showlog
)
call :pass "build_runner + drift_database.g.dart"

:: ══════════════════════════════════════════════════════════════
:: STEP 6 — flutter analyze
::          --no-fatal-warnings: deprecation warnings don't block
:: ══════════════════════════════════════════════════════════════
call :header "6/9" "flutter analyze"
"%FL%" analyze --no-fatal-warnings >> "%LOG%" 2>&1
if errorlevel 1 (
    call :fail "flutter analyze (errors found)"
    goto :showlog
)
call :pass "flutter analyze"

:: ══════════════════════════════════════════════════════════════
:: STEP 7 — flutter test
:: ══════════════════════════════════════════════════════════════
call :header "7/9" "flutter test"
"%FL%" test >> "%LOG%" 2>&1
if errorlevel 1 (
    call :fail "flutter test"
    goto :showlog
)
call :pass "flutter test"

:: ══════════════════════════════════════════════════════════════
:: STEP 8 — flutter build web --release
::          base-href "/" = root of property.aderalabs.tech
:: ══════════════════════════════════════════════════════════════
call :header "8/9" "flutter build web --release"
"%FL%" build web --release --base-href "/" >> "%LOG%" 2>&1
if errorlevel 1 (
    call :fail "flutter build web"
    goto :showlog
)
if not exist "build\web\index.html" (
    echo     ERROR: build\web\index.html not found >> "%LOG%"
    call :fail "flutter build web (no output)"
    goto :showlog
)
call :pass "flutter build web"

:: ══════════════════════════════════════════════════════════════
:: STEP 9 — Package for cPanel deployment
::          Zip CONTENTS of build/web/ (not the folder itself)
:: ══════════════════════════════════════════════════════════════
call :header "9/9" "Create munshi-web.zip"
if exist "%ROOT%\munshi-web.zip" del /f "%ROOT%\munshi-web.zip"
powershell -NoProfile -NonInteractive -Command ^
  "Compress-Archive -Path 'build\web\*' -DestinationPath '%ROOT%\munshi-web.zip' -Force" >> "%LOG%" 2>&1
if errorlevel 1 (
    call :fail "Create zip"
    goto :showlog
)
call :pass "munshi-web.zip"

:: ══════════════════════════════════════════════════════════════
:: FINAL REPORT
:: ══════════════════════════════════════════════════════════════
echo.
echo ============================================================
echo   ALL %PASS_COUNT% STEPS PASSED
echo ============================================================
echo.
echo   Web build : %APP%build\web\
echo   Deploy zip: %ROOT%\munshi-web.zip
echo.
echo   Deploy to cPanel at property.aderalabs.tech:
echo     1. Extract munshi-web.zip into public_html/
echo     2. Verify public_html/index.html exists
echo     3. Point domain to public_html/
echo.
echo   Full log  : %LOG%
echo ============================================================
echo.
echo Build complete. >> "%LOG%"
goto :end

:showlog
echo.
echo ============================================================
echo   BUILD FAILED at step: %FAIL_STEP%
echo   See full log: %LOG%
echo ============================================================
echo.
echo --- Last 50 lines of log ---
powershell -NoProfile -Command "Get-Content '%LOG%' -Tail 50"
exit /b 1

:header
echo.
echo [%~1] %~2
echo. >> "%LOG%"
echo [%~1] %~2 >> "%LOG%"
exit /b 0

:pass
set /a PASS_COUNT+=1
echo     PASS: %~1
echo     PASS: %~1 >> "%LOG%"
exit /b 0

:fail
set "FAIL_STEP=%~1"
echo     FAIL: %~1
echo     FAIL: %~1 >> "%LOG%"
exit /b 0

:end
endlocal
