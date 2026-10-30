# Takes a local backup of WO Tracker on this computer: the whole data folder (database,
# settings and photos) into one .zip that Settings > "Restore from a backup" can read back.
#
# Run it by hand, or schedule it (Task Scheduler) to run daily, weekly or monthly:
#
#   powershell -ExecutionPolicy Bypass -File scripts\local-backup.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\local-backup.ps1 -OutDir "D:\Backups" -Keep 12
#
# Windows Task Scheduler > Create Basic Task > Daily/Weekly/Monthly > Start a program:
#   Program:   powershell.exe
#   Arguments: -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\path\to\scripts\local-backup.ps1"
#
# Nothing here talks to the network. The zip is written beside itself first and only moved into
# place when complete, so an interrupted run never leaves a half-written backup.
param(
  [string]$DataDir = '',
  [string]$OutDir = '',
  [int]$Keep = 30
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Find-DataDir {
  $cands = @(
    (Join-Path $env:APPDATA 'com.najimbacha\wo_tracker'),
    (Join-Path $PSScriptRoot '..\app\build\windows\x64\runner\Release\wo_tracker_data'),
    (Join-Path $PSScriptRoot '..\app\build\windows\x64\runner\Profile\wo_tracker_data')
  )
  $hit = $cands |
    Where-Object { Test-Path (Join-Path $_ 'wo_tracker.db') } |
    Sort-Object { (Get-Item (Join-Path $_ 'wo_tracker.db')).LastWriteTime } -Descending |
    Select-Object -First 1
  return $hit
}

if (-not $DataDir) { $DataDir = Find-DataDir }
if (-not $DataDir -or -not (Test-Path (Join-Path $DataDir 'wo_tracker.db'))) {
  throw "No WO Tracker data found. Pass -DataDir with the folder that holds wo_tracker.db."
}
if (-not $OutDir) { $OutDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WO-Tracker-Backups' }

$DataDir = (Resolve-Path $DataDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = (Get-Date).ToString('yyyy-MM-dd')
$out = Join-Path $OutDir "wo-tracker-backup-$stamp.zip"
$tmp = "$out.part"
if (Test-Path $tmp) { Remove-Item $tmp -Force }

$db = Get-Item (Join-Path $DataDir 'wo_tracker.db')
$wal = Join-Path $DataDir 'wo_tracker.db-wal'
$prefs = Join-Path $DataDir 'shared_preferences.json'
$photoDir = Join-Path $DataDir 'photos'
$photos = @()
if (Test-Path $photoDir) { $photos = @(Get-ChildItem $photoDir -Recurse -File -Force) }

# While the app is open, SQLite holds the database file open, so a plain copy fails with
# "used by another process". Read with shared access instead: that is what backup tools do and
# it succeeds whether or not the app is running. (The app's own "Back up now" is still the
# only copy taken with the database properly closed.)
function Copy-Shared([string]$Src, [string]$Dest) {
  $in = [System.IO.File]::Open($Src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try {
    $out = [System.IO.File]::Create($Dest)
    try { $in.CopyTo($out) } finally { $out.Dispose() }
  } finally {
    $in.Dispose()
  }
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("wo-backup-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
  Copy-Shared $db.FullName (Join-Path $stage 'wo_tracker.db')
  # Writes not yet merged into the .db file live in the -wal; copy it too when it has content.
  $hasWal = $false
  if ((Test-Path $wal) -and ((Get-Item $wal).Length -gt 0)) {
    Copy-Shared $wal (Join-Path $stage 'wo_tracker.db-wal')
    $hasWal = $true
  }
  $hasPrefs = $false
  if (Test-Path $prefs) {
    Copy-Shared $prefs (Join-Path $stage 'shared_preferences.json')
    $hasPrefs = $true
  }

  # The same description the app writes, so Settings > Restore accepts this file.
  $manifest = [ordered]@{
    magic     = 'wo-tracker-local-backup'
    format    = 1
    createdAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    orders    = $null
    photos    = $photos.Count
    dbBytes   = $db.Length
  } | ConvertTo-Json

  $zip = [System.IO.Compression.ZipFile]::Open($tmp, 'Create')
  try {
    $entry = $zip.CreateEntry('backup.json')
    $sw = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    try { $sw.Write($manifest) } finally { $sw.Dispose() }

    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $stage 'wo_tracker.db'), 'wo_tracker.db', 'Optimal') | Out-Null
    if ($hasWal) {
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $stage 'wo_tracker.db-wal'), 'wo_tracker.db-wal', 'Optimal') | Out-Null
    }
    if ($hasPrefs) {
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $stage 'shared_preferences.json'), 'shared_preferences.json', 'Optimal') | Out-Null
    }
    foreach ($p in $photos) {
      $rel = $p.FullName.Substring($DataDir.Length + 1).Replace('\', '/')
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $p.FullName, $rel, 'Optimal') | Out-Null
    }
  } finally {
    $zip.Dispose()
  }
} finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path $out) { Remove-Item $out -Force }
Move-Item $tmp $out -Force

# Keep only the newest $Keep backups, so a daily task does not fill the disk.
$old = Get-ChildItem $OutDir -Filter 'wo-tracker-backup-*.zip' -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -Skip $Keep
foreach ($f in $old) { Remove-Item $f.FullName -Force }

$zipInfo = Get-Item $out
"Backup written: $($zipInfo.FullName)"
"  from:   $DataDir"
"  size:   {0:N0} KB" -f ($zipInfo.Length / 1KB)
"  photos: $($photos.Count)"
"  kept:   $((Get-ChildItem $OutDir -Filter 'wo-tracker-backup-*.zip' -File).Count) file(s) in $OutDir"
