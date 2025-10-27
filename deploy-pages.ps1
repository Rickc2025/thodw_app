# Robust GitHub Pages deploy for Flutter Web to docs/
# - Verifies build output exists before touching docs
# - Copies contents of build/web into a temp folder, then atomically swaps into docs
# - Adds .nojekyll
# - Commits and pushes

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }

$baseHref = "/thodw_app/"
$root     = Get-Location
$src      = Join-Path $root "build\web"
$dst      = Join-Path $root "docs"
$tmp      = Join-Path $root "docs_tmp"

Info "Building Flutter Web (base-href $baseHref, force HTML via dart-define)"
flutter build web --release --base-href $baseHref --dart-define=FLUTTER_WEB_USE_SKIA=false
if ($LASTEXITCODE -ne 0) { throw "Flutter build failed" }

if (-not (Test-Path (Join-Path $src "index.html"))) {
  throw "Build output missing: $src\index.html. Aborting to avoid wiping docs."
}

# Prepare temp copy
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null

Info "Copying build to temp folder"
# Use Robocopy for reliable deep copies on Windows
robocopy $src $tmp /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) { throw "Robocopy failed with exit code $LASTEXITCODE" }

# Atomically swap into docs
Info "Swapping temp into docs"
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Rename-Item $tmp $dst

# Ensure .nojekyll exists at docs root
New-Item -ItemType File -Path (Join-Path $dst ".nojekyll") -Force | Out-Null

# Disable service worker for maximum Safari/iPad compatibility
if (Test-Path (Join-Path $dst "flutter_service_worker.js")) {
  Remove-Item (Join-Path $dst "flutter_service_worker.js") -Force
}
$bootstrap = (Join-Path $dst "flutter_bootstrap.js")
if (Test-Path $bootstrap) {
  $content = Get-Content -Raw $bootstrap
  $content = $content -replace 'serviceWorkerSettings:\s*\{[\s\S]*?\}', 'serviceWorkerSettings: null'
  Set-Content -Path $bootstrap -Value $content -NoNewline
}

# Sanity checks
if (-not (Test-Path (Join-Path $dst "index.html"))) {
  throw "docs\index.html missing after swap. Aborting."
}

Info "Git commit and push"
git add -A docs
git commit -m ("Deploy Pages: " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
git pull --rebase origin main
git push

Info "Done. If the browser shows an old build, do a hard refresh (Ctrl+F5) or clear the service worker cache."