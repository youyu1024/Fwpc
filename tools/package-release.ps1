$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseConfigPath = Join-Path $root "config\release.json"

$version = "1.0.0"
$runtimeIdentifier = "win-x64"

if (Test-Path $releaseConfigPath) {
  $releaseConfig = Get-Content -Path $releaseConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
  if ($releaseConfig.version) {
    $version = [string]$releaseConfig.version
  }
  if ($releaseConfig.runtimeIdentifier) {
    $runtimeIdentifier = [string]$releaseConfig.runtimeIdentifier
  }
}

& (Join-Path $PSScriptRoot "build-release.ps1") `
  -Version $version `
  -RuntimeIdentifier $runtimeIdentifier `
  -ReleaseOutputDir "release" `
  -AutoProvisionRuntime
