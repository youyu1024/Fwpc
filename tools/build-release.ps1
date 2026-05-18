param(
  [string]$AppVersion = "1.0.0",
  [string]$ScrcpyVersion = "4.0",
  [string]$ScrcpySha256 = "75dbeb5b00e6f64292f26f70900ae55ca397786bdfb0b9bbeb481a0549047457"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $root "app\wifi-phone-control-gui.ps1"
$dist = Join-Path $root "dist"
$release = Join-Path $root "release"
$target = Join-Path $dist "WiFiPhoneControl.exe"
$cache = Join-Path $root ".cache"
$downloadCache = Join-Path $cache "downloads"
$scrcpyAssetName = "scrcpy-win64-v$ScrcpyVersion.zip"
$scrcpyUrl = "https://github.com/Genymobile/scrcpy/releases/download/v$ScrcpyVersion/$scrcpyAssetName"
$scrcpyZip = Join-Path $downloadCache $scrcpyAssetName
$scrcpyExtractRoot = Join-Path $cache "scrcpy-v$ScrcpyVersion"
$packageName = "WiFiPhoneControl-v$AppVersion-win-x64.zip"
$packagePath = Join-Path $release $packageName
$tempPackageRoot = Join-Path $dist "_release-package"

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path $Path)) {
    New-Item -Path $Path -ItemType Directory | Out-Null
  }
}

function Reset-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (Test-Path $Path) {
    Remove-Item -Path $Path -Recurse -Force
  }
  New-Item -Path $Path -ItemType Directory | Out-Null
}

function Assert-Sha256 {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Expected
  )

  $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected.ToLowerInvariant()) {
    throw "SHA256 mismatch for $Path. Expected $Expected, got $actual."
  }
}

function Assert-RuntimeComplete {
  param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

  if (-not (Test-Path $RuntimeRoot)) {
    throw "Runtime folder missing: $RuntimeRoot"
  }

  foreach ($required in @("scrcpy.exe", "adb.exe", "AdbWinApi.dll", "AdbWinUsbApi.dll", "scrcpy-server")) {
    if (-not (Test-Path (Join-Path $RuntimeRoot $required))) {
      throw "Runtime validation failed, missing: runtime\scrcpy\$required"
    }
  }

  foreach ($pattern in @("SDL*.dll", "avcodec-*.dll", "avformat-*.dll", "avutil-*.dll", "swresample-*.dll")) {
    $match = Get-ChildItem -Path $RuntimeRoot -File -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $match) {
      throw "Runtime validation failed, missing file matching: runtime\scrcpy\$pattern"
    }
  }
}

function Get-ScrcpyExtractedRoot {
  param([Parameter(Mandatory = $true)][string]$ExtractRoot)

  $scrcpyExe = Get-ChildItem -Path $ExtractRoot -Recurse -File -Filter "scrcpy.exe" | Select-Object -First 1
  if (-not $scrcpyExe) {
    throw "scrcpy.exe was not found after extracting $scrcpyAssetName."
  }
  return $scrcpyExe.Directory.FullName
}

function Assert-ZipEntry {
  param(
    [Parameter(Mandatory = $true)][string[]]$Entries,
    [Parameter(Mandatory = $true)][string]$Pattern
  )

  $normalized = $Pattern.Replace("\", "/")
  if (-not ($Entries | ForEach-Object { $_.Replace("\", "/") } | Where-Object { $_ -like $normalized } | Select-Object -First 1)) {
    throw "Release ZIP validation failed, missing: $normalized"
  }
}

if (-not (Test-Path $source)) {
  throw "Source file not found: $source"
}

Ensure-Directory -Path $dist
Ensure-Directory -Path $release
Ensure-Directory -Path $downloadCache

if (-not (Test-Path $scrcpyZip)) {
  Write-Host "Downloading $scrcpyAssetName..." -ForegroundColor Cyan
  Invoke-WebRequest -Uri $scrcpyUrl -OutFile $scrcpyZip -UseBasicParsing
}

Assert-Sha256 -Path $scrcpyZip -Expected $ScrcpySha256
Reset-Directory -Path $scrcpyExtractRoot
Expand-Archive -Path $scrcpyZip -DestinationPath $scrcpyExtractRoot -Force
$scrcpyPackageRoot = Get-ScrcpyExtractedRoot -ExtractRoot $scrcpyExtractRoot
Assert-RuntimeComplete -RuntimeRoot $scrcpyPackageRoot

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
  Write-Host "Installing ps2exe module..." -ForegroundColor Cyan
  Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe -Force

Invoke-ps2exe `
  -inputFile $source `
  -outputFile $target `
  -noConsole `
  -title "Wi-Fi Phone Control" `
  -company "Local Build" `
  -product "WiFiPhoneControl" `
  -version $AppVersion

Reset-Directory -Path $tempPackageRoot

Copy-Item -Path $target -Destination (Join-Path $tempPackageRoot "WiFiPhoneControl.exe") -Force
foreach ($folder in @("core", "config", "profiles")) {
  Copy-Item -Path (Join-Path $root $folder) -Destination (Join-Path $tempPackageRoot $folder) -Recurse -Force
}
foreach ($file in @("QUICKSTART.txt", "LICENSE")) {
  Copy-Item -Path (Join-Path $root $file) -Destination (Join-Path $tempPackageRoot $file) -Force
}

$runtimeTarget = Join-Path $tempPackageRoot "runtime\scrcpy"
Ensure-Directory -Path $runtimeTarget
Copy-Item -Path (Join-Path $scrcpyPackageRoot "*") -Destination $runtimeTarget -Recurse -Force
Assert-RuntimeComplete -RuntimeRoot $runtimeTarget

if (Test-Path $packagePath) {
  Remove-Item -Path $packagePath -Force
}
Compress-Archive -Path (Join-Path $tempPackageRoot "*") -DestinationPath $packagePath -CompressionLevel Optimal

$zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
try {
  $zipEntries = $zip.Entries | ForEach-Object { $_.FullName }
}
finally {
  $zip.Dispose()
}

foreach ($requiredEntry in @(
  "WiFiPhoneControl.exe",
  "QUICKSTART.txt",
  "LICENSE",
  "core/common.psm1",
  "config/settings.json",
  "profiles/devices.json",
  "runtime/scrcpy/scrcpy.exe",
  "runtime/scrcpy/adb.exe",
  "runtime/scrcpy/AdbWinApi.dll",
  "runtime/scrcpy/AdbWinUsbApi.dll",
  "runtime/scrcpy/scrcpy-server",
  "runtime/scrcpy/SDL*.dll",
  "runtime/scrcpy/avcodec-*.dll",
  "runtime/scrcpy/avformat-*.dll",
  "runtime/scrcpy/avutil-*.dll",
  "runtime/scrcpy/swresample-*.dll"
)) {
  Assert-ZipEntry -Entries $zipEntries -Pattern $requiredEntry
}

Remove-Item -Path $tempPackageRoot -Recurse -Force

Write-Host "Build complete: $target" -ForegroundColor Green
Write-Host "Release package: $packagePath" -ForegroundColor Green
