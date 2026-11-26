param(
  [string]$AppVersion = "1.1.0",
  [string]$ScrcpyVersion = "4.0",
  [string]$ScrcpySha256 = "75dbeb5b00e6f64292f26f70900ae55ca397786bdfb0b9bbeb481a0549047457"
)

$ErrorActionPreference = "Stop"
$windowsModules = Join-Path $PSHOME 'Modules'
$env:PSModulePath = $windowsModules + [IO.Path]::PathSeparator + $env:PSModulePath

Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $root "app\wifi-phone-control-gui.ps1"

$release = Join-Path $root "release"

$cache = Join-Path $root ".cache"
$downloadCache = Join-Path $cache "downloads"
$scrcpyAssetName = "scrcpy-win64-v$ScrcpyVersion.zip"
$scrcpyUrl = "https://github.com/Genymobile/scrcpy/releases/download/v$ScrcpyVersion/$scrcpyAssetName"
$scrcpyZip = Join-Path $downloadCache $scrcpyAssetName

$packageName = "WiFiPhoneControl-v$AppVersion-win-x64.zip"
$packagePath = Join-Path $release $packageName
$buildRoot = Join-Path $cache ("build-" + [Guid]::NewGuid().ToString('N'))
$scrcpyExtractRoot = Join-Path $buildRoot "runtime"
$tempPackageRoot = Join-Path $buildRoot "package"
$target = Join-Path $tempPackageRoot "WiFiPhoneControl.exe"
$stagedZip = Join-Path $buildRoot $packageName

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path $Path)) {
    New-Item -Path $Path -ItemType Directory | Out-Null
  }
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

Ensure-Directory -Path $tempPackageRoot
Ensure-Directory -Path $release
Ensure-Directory -Path $downloadCache

if (-not (Test-Path $scrcpyZip)) {
  Write-Host "Downloading $scrcpyAssetName..." -ForegroundColor Cyan
  Invoke-WebRequest -Uri $scrcpyUrl -OutFile $scrcpyZip -UseBasicParsing
}

Assert-Sha256 -Path $scrcpyZip -Expected $ScrcpySha256
Ensure-Directory -Path $scrcpyExtractRoot
Expand-Archive -Path $scrcpyZip -DestinationPath $scrcpyExtractRoot -Force
$scrcpyPackageRoot = Get-ScrcpyExtractedRoot -ExtractRoot $scrcpyExtractRoot
Assert-RuntimeComplete -RuntimeRoot $scrcpyPackageRoot

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
  $modernModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
  if (Test-Path -LiteralPath (Join-Path $modernModules 'ps2exe')) {
    $env:PSModulePath += [IO.Path]::PathSeparator + $modernModules
  }
}
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
  Write-Host "Installing ps2exe module..." -ForegroundColor Cyan
  if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap | Out-Null
  }
  Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe -Force

Invoke-ps2exe `
  -inputFile $source `
  -outputFile $target `
  -noConsole `
  -x64 `
  -STA `
  -DPIAware `
  -title "Fwpc Phone Control" `
  -company "Local Build" `
  -product "WiFiPhoneControl" `
  -version $AppVersion



foreach ($folder in @("core", "config", "profiles", "docs")) {
  Copy-Item -Path (Join-Path $root $folder) -Destination (Join-Path $tempPackageRoot $folder) -Recurse -Force
}
foreach ($file in @("QUICKSTART.txt", "LICENSE")) {
  Copy-Item -Path (Join-Path $root $file) -Destination (Join-Path $tempPackageRoot $file) -Force
}

$runtimeTarget = Join-Path $tempPackageRoot "runtime\scrcpy"
Ensure-Directory -Path $runtimeTarget
Copy-Item -Path (Join-Path $scrcpyPackageRoot "*") -Destination $runtimeTarget -Recurse -Force
Assert-RuntimeComplete -RuntimeRoot $runtimeTarget

Compress-Archive -Path (Join-Path $tempPackageRoot "*") -DestinationPath $stagedZip -CompressionLevel Optimal

$zip = [System.IO.Compression.ZipFile]::OpenRead($stagedZip)
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
  "core/adb.psm1",
  "core/pairing.psm1",
  "core/control.psm1",
  "core/monitor.psm1",
  "docs/release-acceptance.md",
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

if ([IO.File]::Exists($packagePath)) { [IO.File]::Replace($stagedZip, $packagePath, [NullString]::Value) }
else { [IO.File]::Move($stagedZip, $packagePath) }

$resolvedBuild = (Resolve-Path -LiteralPath $buildRoot).ProviderPath
$expectedBuild = [IO.Path]::GetFullPath($buildRoot)
$item = Get-Item -LiteralPath $resolvedBuild -Force
if ($resolvedBuild -ne $expectedBuild -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  throw "Unexpected release staging directory: $resolvedBuild"
}
Remove-Item -LiteralPath $resolvedBuild -Recurse -Force

Write-Host "Release package: $packagePath" -ForegroundColor Green
