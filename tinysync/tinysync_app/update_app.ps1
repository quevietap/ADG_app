# TinySync App Update Script
# This script builds and updates the Flutter app on your connected device

Write-Host "Updating TinySync App on your phone..." -ForegroundColor Green
Write-Host "=" * 70

# Check if Flutter is installed
Write-Host "Checking Flutter installation..." -ForegroundColor Yellow
flutter --version
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Flutter is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Flutter from: https://flutter.dev/docs/get-started/install" -ForegroundColor Red
    exit 1
}

# Navigate to the correct app directory
Write-Host "Navigating to app directory..." -ForegroundColor Yellow
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

# Check for connected devices
Write-Host "Checking for connected devices..." -ForegroundColor Yellow
$devices = flutter devices
Write-Host $devices

# Check if any devices are connected
$androidDevice = $devices | Select-String "android"
if (-not $androidDevice) {
    Write-Host "ERROR: No Android device found!" -ForegroundColor Red
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "   1. Connect your phone via USB" -ForegroundColor White
    Write-Host "   2. Enable USB debugging on your phone" -ForegroundColor White
    Write-Host "   3. Run 'flutter devices' to verify connection" -ForegroundColor White
    exit 1
} else {
    Write-Host "SUCCESS: Android device detected!" -ForegroundColor Green
}

# Clean previous builds
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to clean project" -ForegroundColor Red
    exit 1
}

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to get dependencies" -ForegroundColor Red
    exit 1
}

# Build and install the app
Write-Host "Building and installing app..." -ForegroundColor Yellow
Write-Host "This may take a few minutes..." -ForegroundColor Cyan

# Try debug build first
Write-Host "Installing debug version..." -ForegroundColor Yellow
flutter install --debug
if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Debug version successfully installed!" -ForegroundColor Green
} else {
    Write-Host "WARNING: Debug build failed, trying release build..." -ForegroundColor Yellow
    flutter install --release
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Release version successfully installed!" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Failed to build and install app" -ForegroundColor Red
        Write-Host "Please check your device connection and try again" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "=" * 70
Write-Host "SUCCESS: TinySync App successfully updated on your phone!" -ForegroundColor Green
Write-Host ""
Write-Host "App Version: 1.0.2+2" -ForegroundColor Cyan
Write-Host "Features:" -ForegroundColor Yellow
Write-Host "   - Driver monitoring and performance tracking" -ForegroundColor White
Write-Host "   - Real-time dashboard" -ForegroundColor White
Write-Host "   - Profile management" -ForegroundColor White
Write-Host "   - Video playback support" -ForegroundColor White
Write-Host "   - Offline capability" -ForegroundColor White
Write-Host ""
Write-Host "The app is now updated and ready to use!" -ForegroundColor Green
