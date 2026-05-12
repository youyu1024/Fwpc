$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $root "app\wifi-phone-control-gui.ps1"
$dist = Join-Path $root "dist"
$target = Join-Path $dist "WiFiPhoneControl.exe"

if (-not (Test-Path $source)) {
  throw "Source file not found: $source"
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

Write-Host "Build complete: $target" -ForegroundColor Green
