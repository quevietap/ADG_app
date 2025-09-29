# Check if emulator is running
$emulatorProcess = Get-Process "qemu-system-x86_64" -ErrorAction SilentlyContinue

if ($null -eq $emulatorProcess) {
    Write-Host "Starting Android emulator..."
    Start-Process "flutter" -ArgumentList "emulators --launch Medium_Phone_API_36.0" -NoNewWindow
    # Wait for emulator to start
    Start-Sleep -Seconds 30
}

# Run the Flutter app
Write-Host "Running ADG Tiny Sync on Android..."
flutter run -d android 