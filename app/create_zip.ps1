# Munshi — Create deployment zip from build/web contents
# Run after: flutter build web --release
# Output: ../munshi-web.zip (parent of app/ directory)

$appDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$webDir  = Join-Path $appDir "build\web"
$zipPath = Join-Path (Split-Path -Parent $appDir) "munshi-web.zip"

if (-not (Test-Path $webDir)) {
    Write-Error "build\web not found. Run flutter build web --release first."
    exit 1
}

if (-not (Test-Path (Join-Path $webDir "index.html"))) {
    Write-Error "build\web\index.html not found. Build may have failed."
    exit 1
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Write-Host "Zipping $webDir -> $zipPath ..."
Compress-Archive -Path "$webDir\*" -DestinationPath $zipPath -Force

$size = (Get-Item $zipPath).Length / 1MB
Write-Host "Created: $zipPath ($([math]::Round($size,1)) MB)"

# Verify index.html is inside zip
Add-Type -Assembly System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
$hasIndex = $zip.Entries | Where-Object { $_.Name -eq 'index.html' }
$zip.Dispose()

if ($hasIndex) {
    Write-Host "Verified: index.html present in zip"
    Write-Host ""
    Write-Host "Deploy instructions for property.aderalabs.tech:"
    Write-Host "  1. In cPanel File Manager, navigate to public_html/"
    Write-Host "  2. Upload munshi-web.zip"
    Write-Host "  3. Extract it (all files go directly into public_html/)"
    Write-Host "  4. Verify public_html/index.html exists"
    Write-Host "  5. Test: https://property.aderalabs.tech/"
} else {
    Write-Error "index.html not found in zip — something went wrong"
    exit 1
}
