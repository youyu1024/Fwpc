$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $root "app\wifi-phone-control-gui.ps1"
$dist = Join-Path $root "dist"
$target = Join-Path $dist "WiFiPhoneControl.exe"
$runtimeScrcpy = Join-Path $root "runtime\scrcpy"
$packageName = "WiFiPhoneControl-v1.0.0-win-x64.zip"
$packagePath = Join-Path $dist $packageName

if (-not (Test-Path $source)) {
  throw "Source file not found: $source"
}
if (-not (Test-Path $runtimeScrcpy)) {
  throw "Missing runtime folder: $runtimeScrcpy. Please place the full official scrcpy Windows release in runtime\\scrcpy\\ first."
}
if (-not (Test-Path (Join-Path $runtimeScrcpy "scrcpy.exe"))) {
  throw "runtime\\scrcpy\\scrcpy.exe is required."
}
if (-not (Test-Path (Join-Path $runtimeScrcpy "adb.exe"))) {
  throw "runtime\\scrcpy\\adb.exe is required."
}
foreach ($adbDll in @("AdbWinApi.dll", "AdbWinUsbApi.dll")) {
  if (-not (Test-Path (Join-Path $runtimeScrcpy $adbDll))) {
    throw "runtime\\scrcpy\\$adbDll is required."
  }
}

if (-not (Test-Path $dist)) {
  New-Item -Path $dist -ItemType Directory | Out-Null
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
  Write-Host "Installing ps2exe module..." -ForegroundColor Cyan
  Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe -Force

Invoke-ps2exe `
  -inputFile $source `
  -outputFile $target `
  -noConsole `
  -title "Wi-Fi Pair & Phone Control" `
  -company "Local Build" `
  -product "WiFiPhoneControl"

foreach ($folder in @("core", "config", "profiles", "runtime")) {
  $src = Join-Path $root $folder
  $dst = Join-Path $dist $folder
  if (-not (Test-Path $src)) { continue }
  if (Test-Path $dst) {
    Remove-Item -Path $dst -Recurse -Force
  }
  Copy-Item -Path $src -Destination $dst -Recurse -Force
}

$tempPackageRoot = Join-Path $dist "_release-package"
if (Test-Path $tempPackageRoot) {
  Remove-Item -Path $tempPackageRoot -Recurse -Force
}
New-Item -Path $tempPackageRoot -ItemType Directory | Out-Null

Copy-Item -Path $target -Destination (Join-Path $tempPackageRoot "WiFiPhoneControl.exe") -Force
foreach ($folder in @("core", "config", "profiles", "runtime\scrcpy")) {
  $src = Join-Path $dist $folder
  $dst = Join-Path $tempPackageRoot $folder
  New-Item -Path (Split-Path -Parent $dst) -ItemType Directory -Force | Out-Null
  Copy-Item -Path $src -Destination $dst -Recurse -Force
}

if (Test-Path $packagePath) {
  Remove-Item -Path $packagePath -Force
}
Compress-Archive -Path (Join-Path $tempPackageRoot "*") -DestinationPath $packagePath -CompressionLevel Optimal

$zipEntries = [System.IO.Compression.ZipFile]::OpenRead($packagePath).Entries | ForEach-Object { $_.FullName }
foreach ($requiredEntry in @(
  "runtime/scrcpy/scrcpy.exe",
  "runtime/scrcpy/adb.exe",
  "runtime/scrcpy/AdbWinApi.dll",
  "runtime/scrcpy/AdbWinUsbApi.dll"
)) {
  if (-not ($zipEntries -contains $requiredEntry)) {
    throw "Release ZIP validation failed, missing: $requiredEntry"
  }
}

Remove-Item -Path $tempPackageRoot -Recurse -Force

Write-Host "Build complete: $target" -ForegroundColor Green
Write-Host "Release package: $packagePath" -ForegroundColor Green
