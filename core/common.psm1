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

function Test-FilePattern {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Pattern
  )

  $match = Get-ChildItem -Path $Root -File -Filter $Pattern -ErrorAction SilentlyContinue | Select-Object -First 1
  return [bool]$match
}

function Test-ScrcpyRuntime {
  param([string]$RuntimeRoot = (Join-Path (Get-AppRoot) "runtime\scrcpy"))

  if (-not (Test-Path $RuntimeRoot)) {
    return [pscustomobject]@{
      Success = $false
      Root    = $RuntimeRoot
      Missing = @("runtime\scrcpy")
      Message = "Release package is incomplete: runtime\scrcpy directory is missing."
    }
  }

  $missing = @()
  foreach ($required in @("scrcpy.exe", "adb.exe", "AdbWinApi.dll", "AdbWinUsbApi.dll", "scrcpy-server")) {
    if (-not (Test-Path (Join-Path $RuntimeRoot $required))) {
      $missing += $required
    }
  }

  foreach ($pattern in @("SDL*.dll", "avcodec-*.dll", "avformat-*.dll", "avutil-*.dll", "swresample-*.dll")) {
    if (-not (Test-FilePattern -Root $RuntimeRoot -Pattern $pattern)) {
      $missing += $pattern
    }
  }

  if ($missing.Count -gt 0) {
    return [pscustomobject]@{
      Success = $false
      Root    = $RuntimeRoot
      Missing = $missing
      Message = "Release package is incomplete: runtime\scrcpy is missing required files: $($missing -join ', ')."
    }
  }

  return [pscustomobject]@{
    Success = $true
    Root    = $RuntimeRoot
    Missing = @()
    Message = "Bundled scrcpy runtime is complete."
  }
}

function Assert-ScrcpyRuntime {
  param([string]$RuntimeRoot = (Join-Path (Get-AppRoot) "runtime\scrcpy"))

  $result = Test-ScrcpyRuntime -RuntimeRoot $RuntimeRoot
  if (-not $result.Success) {
    throw $result.Message
  }
  return $result
}

function Get-ScrcpyPackageRoot {
  $result = Assert-ScrcpyRuntime
  return $result.Root
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
  Test-ScrcpyRuntime, Assert-ScrcpyRuntime, Get-AdbPath, Get-ScrcpyPath, Write-AppLog
