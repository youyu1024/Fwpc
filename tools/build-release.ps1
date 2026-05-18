param(
  [string]$Version = "1.0.0",
  [string]$RuntimeIdentifier = "win-x64",
  [string]$ReleaseOutputDir = "dist",
  [switch]$AutoProvisionRuntime
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $root "app\wifi-phone-control-gui.ps1"
$dist = Join-Path $root "dist"
$target = Join-Path $dist "WiFiPhoneControl.exe"
$runtimeScrcpy = Join-Path $root "runtime\scrcpy"
$releaseConfigPath = Join-Path $root "config\release.json"

$requiredRuntimeFiles = @(
  "scrcpy.exe",
  "adb.exe",
  "AdbWinApi.dll",
  "AdbWinUsbApi.dll",
  "SDL2.dll"
)

if (Test-Path $releaseConfigPath) {
  $releaseConfig = Get-Content -Path $releaseConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
  if (-not $PSBoundParameters.ContainsKey("Version") -and $releaseConfig.version) {
    $Version = [string]$releaseConfig.version
  }
  if (-not $PSBoundParameters.ContainsKey("RuntimeIdentifier") -and $releaseConfig.runtimeIdentifier) {
    $RuntimeIdentifier = [string]$releaseConfig.runtimeIdentifier
  }
  if ($releaseConfig.requiredRuntimeFiles -and $releaseConfig.requiredRuntimeFiles.Count -gt 0) {
    $requiredRuntimeFiles = @($releaseConfig.requiredRuntimeFiles | ForEach-Object { [string]$_ })
  }
}

function Get-MissingRuntimeFiles {
  param(
    [Parameter(Mandatory = $true)][string]$RuntimeFolder,
    [Parameter(Mandatory = $true)][string[]]$RequiredFiles
  )
  $missing = @()
  foreach ($file in $RequiredFiles) {
    if (-not (Test-Path (Join-Path $RuntimeFolder $file))) {
      $missing += $file
    }
  }
  return $missing
}

function Get-ReleaseAsset {
  param([Parameter(Mandatory = $true)]$Assets)
  $preferred = $Assets |
    Where-Object { $_.name -match "win64" -and $_.name -match "\.zip$" } |
    Select-Object -First 1
  if ($preferred) { return $preferred }
  return $Assets | Where-Object { $_.name -match "\.zip$" } | Select-Object -First 1
}

function Provision-RuntimeFromGithub {
  param([Parameter(Mandatory = $true)][string]$DestinationFolder)

  $tempRoot = Join-Path $env:TEMP ("wfpc-runtime-{0}" -f [guid]::NewGuid().ToString("N"))
  $archivePath = $null
  $extractPath = $null

  try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $extractPath = Join-Path $tempRoot "extract"
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

    Write-Host "Fetching latest scrcpy release metadata from GitHub..." -ForegroundColor Cyan
    $releaseMeta = Invoke-RestMethod -Uri "https://api.github.com/repos/Genymobile/scrcpy/releases/latest" -Headers @{ "User-Agent" = "WiFiPhoneControl" }
    $asset = Get-ReleaseAsset -Assets $releaseMeta.assets
    if (-not $asset) {
      throw "Unable to find a Windows zip asset in latest scrcpy release."
    }

    $archivePath = Join-Path $tempRoot $asset.name
    Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -UseBasicParsing
    Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force

    $scrcpyExe = Get-ChildItem -Path $extractPath -Recurse -File -Filter "scrcpy.exe" | Select-Object -First 1
    if (-not $scrcpyExe) {
      throw "Downloaded scrcpy asset does not contain scrcpy.exe."
    }
    $sourceFolder = $scrcpyExe.Directory.FullName

    if (Test-Path $DestinationFolder) {
      Remove-Item -Path $DestinationFolder -Recurse -Force
    }
    New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceFolder "*") -Destination $DestinationFolder -Recurse -Force
    Write-Host "Runtime provisioned: $DestinationFolder" -ForegroundColor Green
  }
  finally {
    if ($tempRoot -and (Test-Path $tempRoot)) {
      Remove-Item -Path $tempRoot -Recurse -Force
    }
  }
}

if (-not (Test-Path $source)) {
  throw "Source file not found: $source"
}

$missingRuntimeFiles = Get-MissingRuntimeFiles -RuntimeFolder $runtimeScrcpy -RequiredFiles $requiredRuntimeFiles
if ($missingRuntimeFiles.Count -gt 0) {
  if (-not $AutoProvisionRuntime) {
    $missingText = $missingRuntimeFiles -join ", "
    throw "runtime\scrcpy is incomplete. Missing: $missingText. Restore full runtime\scrcpy or use package-release.cmd (auto-provision mode)."
  }
  Provision-RuntimeFromGithub -DestinationFolder $runtimeScrcpy
  $missingRuntimeFiles = Get-MissingRuntimeFiles -RuntimeFolder $runtimeScrcpy -RequiredFiles $requiredRuntimeFiles
  if ($missingRuntimeFiles.Count -gt 0) {
    throw "runtime\scrcpy is still incomplete after auto-provision. Missing: $($missingRuntimeFiles -join ', ')"
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

foreach ($requiredDistPath in @(
    "WiFiPhoneControl.exe",
    "core\common.psm1",
    "config\settings.json",
    "profiles\devices.json",
    "runtime\scrcpy\scrcpy.exe",
    "runtime\scrcpy\adb.exe"
  )) {
  if (-not (Test-Path (Join-Path $dist $requiredDistPath))) {
    throw "dist is incomplete, missing: $requiredDistPath"
  }
}

$packageName = "WiFiPhoneControl-v$Version-$RuntimeIdentifier.zip"
$releaseRoot = if ([System.IO.Path]::IsPathRooted($ReleaseOutputDir)) { $ReleaseOutputDir } else { Join-Path $root $ReleaseOutputDir }
$packagePath = Join-Path $releaseRoot $packageName
$tempPackageRoot = Join-Path $dist "_release-package"

if (-not (Test-Path $releaseRoot)) {
  New-Item -Path $releaseRoot -ItemType Directory | Out-Null
}
if (Test-Path $tempPackageRoot) {
  Remove-Item -Path $tempPackageRoot -Recurse -Force
}
New-Item -Path $tempPackageRoot -ItemType Directory | Out-Null

Copy-Item -Path $target -Destination (Join-Path $tempPackageRoot "WiFiPhoneControl.exe") -Force
foreach ($folder in @("core", "config", "profiles", "runtime")) {
  Copy-Item -Path (Join-Path $dist $folder) -Destination (Join-Path $tempPackageRoot $folder) -Recurse -Force
}

if (Test-Path $packagePath) {
  Remove-Item -Path $packagePath -Force
}
Compress-Archive -Path (Join-Path $tempPackageRoot "*") -DestinationPath $packagePath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
try {
  $zipEntries = $zip.Entries | ForEach-Object { $_.FullName }
  foreach ($requiredEntry in @(
      "WiFiPhoneControl.exe",
      "core/common.psm1",
      "config/settings.json",
      "profiles/devices.json",
      "runtime/scrcpy/scrcpy.exe",
      "runtime/scrcpy/adb.exe",
      "runtime/scrcpy/AdbWinApi.dll",
      "runtime/scrcpy/AdbWinUsbApi.dll"
    )) {
    if (-not ($zipEntries -contains $requiredEntry)) {
      throw "Release ZIP validation failed, missing: $requiredEntry"
    }
  }
}
finally {
  $zip.Dispose()
}

Remove-Item -Path $tempPackageRoot -Recurse -Force

Write-Host "Build complete: $target" -ForegroundColor Green
Write-Host "Release package: $packagePath" -ForegroundColor Green
