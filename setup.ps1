# Generates the missing Flutter platform files (Gradle wrapper, iOS Runner,
# icons, ...) around the code in this folder, then fetches packages.
# Existing files are NOT overwritten.
# Run from this folder:  powershell -ExecutionPolicy Bypass -File .\setup.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

flutter create --org com.berkan --project-name cooldown --platforms android,ios .
flutter pub get
flutter test

Write-Host ""
Write-Host "Done. Plug in your Android phone (USB debugging on) and run:  flutter run" -ForegroundColor Green
