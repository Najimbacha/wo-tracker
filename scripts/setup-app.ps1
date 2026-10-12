# Builds the work order tracker on a Windows PC.
#
#   Run from the project folder in PowerShell:
#     powershell -ExecutionPolicy Bypass -File scripts\setup-app.ps1            # tests + Windows app
#     powershell -ExecutionPolicy Bypass -File scripts\setup-app.ps1 -Android   # also the Android APK
#     powershell -ExecutionPolicy Bypass -File scripts\setup-app.ps1 -Installer # also the Windows installer
#
# Needs (all free): Flutter (stable), Visual Studio 2022 Build Tools with
# "Desktop development with C++", and for -Android the Android SDK (Android Studio).
# For -Installer: Inno Setup 6 (https://jrsoftware.org/isinfo.php).
param([switch]$Android, [switch]$Installer, [switch]$SkipTests)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'app'
Set-Location $app

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Run($exe, [string[]]$argList) {
  & $exe @argList
  if ($LASTEXITCODE -ne 0) { throw "$exe $($argList -join ' ') failed (exit $LASTEXITCODE)" }
}

Step 'Checking Flutter'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is not installed or not on PATH. Install it from https://docs.flutter.dev/get-started/install/windows and open a new PowerShell window.'
}
Run flutter @('--version')

# Platform folders (windows/, android/) are generated, not kept in the project.
# flutter create never overwrites files that already exist (lib/, pubspec.yaml, tests).
Step 'Creating platform folders (first run only)'
$platforms = @('windows')
if ($Android) { $platforms += 'android' }
$missing = $platforms | Where-Object { -not (Test-Path (Join-Path $app $_)) }
if ($missing) {
  Run flutter @('create', '--platforms', ($missing -join ','), '--org', 'com.najimbacha', '--project-name', 'wo_tracker', '.')
}
# flutter create adds a counter-app test that doesn't apply here.
$sample = Join-Path $app 'test\widget_test.dart'
if ((Test-Path $sample) -and (Select-String -Path $sample -Pattern 'MyApp' -Quiet)) { Remove-Item $sample }

if (Test-Path (Join-Path $app 'android')) {
  Step 'Android: internet permission and app name'
  $manifest = Join-Path $app 'android\app\src\main\AndroidManifest.xml'
  $xml = Get-Content $manifest -Raw
  if ($xml -notmatch 'android.permission.INTERNET') {
    $xml = $xml -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"android.permission.INTERNET`"/>"
  }
  $xml = $xml -replace 'android:label="[^"]*"', 'android:label="WO Tracker"'
  Set-Content -Path $manifest -Value $xml -Encoding UTF8
}

if (Test-Path (Join-Path $app 'windows')) {
  Step 'Windows: window title'
  $main = Join-Path $app 'windows\runner\main.cpp'
  (Get-Content $main -Raw) -replace 'L"wo_tracker"', 'L"WO Tracker"' | Set-Content -Path $main -Encoding UTF8
}

Step 'Getting packages'
Run flutter @('pub', 'get')

Step 'Checking the code'
Run flutter @('analyze', '--no-fatal-infos', '--no-fatal-warnings')

if (-not $SkipTests) {
  Step 'Running tests (rules, reports, Excel, Arabic, ids, upload errors)'
  Run flutter @('test')
}

Step 'Building the Windows app'
Run flutter @('build', 'windows', '--release')
$winOut = Join-Path $app 'build\windows\x64\runner\Release'
Write-Host "Windows app: $winOut\wo_tracker.exe" -ForegroundColor Green

if ($Android) {
  Step 'Building the Android APK'
  Run flutter @('build', 'apk', '--release')
  Write-Host "APK: $app\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
}

if ($Installer) {
  Step 'Building the Windows installer'
  $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $iscc) { throw 'Inno Setup 6 is not installed (free: https://jrsoftware.org/isinfo.php).' }
  $version = (Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
  Run $iscc @("/DAppVersion=$version", "/DSourceDir=$winOut", (Join-Path $root 'scripts\installer.iss'))
  Write-Host "Installer: $root\build\WO-Tracker-Setup-$version.exe" -ForegroundColor Green
}

Step 'Done'
