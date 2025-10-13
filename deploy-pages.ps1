# Rebuild the Flutter web app with correct base path for GitHub Pages
flutter clean
flutter pub get
flutter build web --release --base-href "/thodw_app/"

# Refresh the docs/ folder with the new build
if (Test-Path docs) { Remove-Item docs -Recurse -Force }
New-Item -ItemType Directory -Path docs | Out-Null
Copy-Item -Recurse -Force build\web\* docs\
New-Item -ItemType File -Path docs\.nojekyll | Out-Null

# Commit and push the updated site
git add docs
git commit -m "Update GitHub Pages site"
git push

Write-Host "Done. Visit: https://Rickc2025.github.io/thodw_app (give it ~1 minute if first time)"