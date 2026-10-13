# Munshi — Full validation script
# Run from: C:\Users\dell\Downloads\Property Management System\app
# Usage:    powershell -ExecutionPolicy Bypass -File run_all.ps1

$ErrorActionPreference = "Continue"
$fl = "C:\src\flutter\bin\flutter.bat"
$dart = "C:\src\flutter\bin\dart.bat"
$out = ".\validation_results.txt"

"=" * 60 | Out-File $out
"MUNSHI Dart 3.13 Validation — $(Get-Date)" | Out-File $out -Append
"=" * 60 | Out-File $out -Append
"" | Out-File $out -Append

function Run($label, $cmd) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    "[$label]" | Out-File $out -Append
    $result = & $cmd[0] $cmd[1..($cmd.Length-1)] 2>&1
    $result | Out-File $out -Append
    $result | Write-Host
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        "RESULT: $label = PASS" | Out-File $out -Append
        Write-Host "PASS" -ForegroundColor Green
    } else {
        "RESULT: $label = FAIL (exit $exit)" | Out-File $out -Append
        Write-Host "FAIL (exit $exit)" -ForegroundColor Red
    }
    "" | Out-File $out -Append
    return $exit
}

# 1. Version
Run "flutter version" @($fl, "--version")

# 2. pub get
$r = Run "pub get" @($fl, "pub", "get")
if ($r -ne 0) { Write-Host "pub get failed — aborting"; exit 1 }

# 3. build_runner
Run "build_runner" @($fl, "pub", "run", "build_runner", "build", "--delete-conflicting-outputs")

# 4. analyze
Run "flutter analyze" @($fl, "analyze")

# 5. test
Run "flutter test" @($fl, "test")

# 6. build web
Run "flutter build web --release" @($fl, "build", "web", "--release")

"=" * 60 | Out-File $out -Append
"Done. Full log: $((Resolve-Path $out).Path)" | Out-File $out -Append

Write-Host "`nResults saved to: $out"
Get-Content $out | Select-String "RESULT:"
