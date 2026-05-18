$ErrorActionPreference = "Stop"

function Get-AppRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-AppPaths {
  $root = Get-AppRoot
  $paths = [ordered]@{
    Root         = $root
    Core         = Join-Path $root "core"
    App          = Join-Path $root "app"
    Config       = Join-Path $root "config"
    Profiles     = Join-Path $root "profiles"
    Logs         = Join-Path $root "logs"
    State        = Join-Path $root "state"
    SettingsFile = Join-Path (Join-Path $root "config") "settings.json"
    ProfileFile  = Join-Path (Join-Path $root "profiles") "devices.json"
    EndpointFile = Join-Path (Join-Path $root "state") "last-endpoint.txt"
    IpFile       = Join-Path (Join-Path $root "state") "last-ip.txt"
  }

  foreach ($k in @("Config", "Profiles", "Logs", "State")) {
    if (-not (Test-Path $paths[$k])) {
      New-Item -Path $paths[$k] -ItemType Directory | Out-Null
    }
  }
  return $paths
}

function Read-JsonFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$DefaultValue
  )

  if (-not (Test-Path $Path)) {
    return $DefaultValue
  }

  $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
  if (-not $raw.Trim()) {
    return $DefaultValue
  }
  return ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Value
  )

  $json = $Value | ConvertTo-Json -Depth 8
  Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-ScrcpyPackageRoot {
  param(
    [switch]$AllowWingetInstall
  )

  $bundledRoot = Join-Path (Get-AppRoot) "runtime\scrcpy"
  $bundledScrcpy = Join-Path $bundledRoot "scrcpy.exe"
  $runtimeExists = Test-Path $bundledRoot

  if (Test-Path $bundledScrcpy) {
    return $bundledRoot
  }

  if (-not $runtimeExists) {
    throw "runtime\scrcpy directory is missing. This release package may be incomplete or the folder was deleted by mistake. Please restore runtime\scrcpy first. Advanced manual option: install Genymobile.scrcpy with winget."
  }

  if (-not $AllowWingetInstall) {
    throw "scrcpy.exe not found in runtime\scrcpy. Please verify runtime\scrcpy contains the full scrcpy Windows package. Advanced manual option: install Genymobile.scrcpy with winget."
  }

  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) {
    throw "scrcpy.exe not found in runtime\scrcpy, and winget is unavailable. Please restore runtime\scrcpy or manually install Genymobile.scrcpy."
  }

  try {
    & winget install -e --id Genymobile.scrcpy --accept-source-agreements --accept-package-agreements --silent | Out-Null
  }
  catch {
    throw "Failed to install Genymobile.scrcpy via winget. Please repair runtime\scrcpy manually. Error: $($_.Exception.Message)"
  }

  $packageRoot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory |
    Where-Object { $_.Name -like "Genymobile.scrcpy*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (-not $packageRoot) {
    throw "winget installation completed but scrcpy package path was not found. Please repair runtime\scrcpy manually."
  }

  return $packageRoot.FullName
}

function Get-AdbPath {
  $root = Get-ScrcpyPackageRoot
  $adb = Get-ChildItem $root -Recurse -File -Filter adb.exe | Select-Object -First 1 -ExpandProperty FullName
  if (-not $adb) {
    throw "adb.exe not found in scrcpy package."
  }
  return $adb
}

function Get-ScrcpyPath {
  $root = Get-ScrcpyPackageRoot
  $scrcpy = Get-ChildItem $root -Recurse -File -Filter scrcpy.exe | Select-Object -First 1 -ExpandProperty FullName
  if (-not $scrcpy) {
    throw "scrcpy.exe not found in scrcpy package."
  }
  return $scrcpy
}

function Write-AppLog {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
  )
  $paths = Get-AppPaths
  $logFile = Join-Path $paths.Logs ("app-{0}.log" -f (Get-Date -Format "yyyyMMdd"))
  $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
  Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Export-ModuleMember -Function `
  Get-AppRoot, Get-AppPaths, Read-JsonFile, Write-JsonFile, `
  Get-AdbPath, Get-ScrcpyPath, Write-AppLog
