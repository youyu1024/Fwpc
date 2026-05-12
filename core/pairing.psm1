$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "common.psm1")

function Get-MdnsConnectEndpoints {
  param([Parameter(Mandatory = $true)][string]$AdbPath)

  $lines = & "$AdbPath" mdns services 2>$null
  if (-not $lines) { return @() }

  $eps = @()
  foreach ($line in $lines) {
    if ($line -match "_adb-tls-connect\._tcp\s+(\d+\.\d+\.\d+\.\d+:\d+)") {
      $eps += $matches[1]
    }
  }
  return $eps | Select-Object -Unique
}

function Invoke-DevicePairing {
  param(
    [Parameter(Mandatory = $true)][string]$PairEndpoint,
    [Parameter(Mandatory = $true)][string]$PairCode,
    [string]$ConnectEndpoint
  )

  $adb = Get-AdbPath
  $paths = Get-AppPaths

  $pairOutput = & "$adb" pair $PairEndpoint $PairCode 2>&1
  $pairText = ($pairOutput | Out-String).Trim()
  Write-AppLog -Message "adb pair => $pairText"
  if ($pairText -notmatch "Successfully paired") {
    return [pscustomobject]@{
      Success = $false
      Message = $pairText
    }
  }

  if (-not $ConnectEndpoint) {
    $mdnsEndpoints = Get-MdnsConnectEndpoints -AdbPath $adb
    $pairIp = $PairEndpoint.Split(":")[0]
    $preferred = $mdnsEndpoints | Where-Object { $_ -like "${pairIp}:*" } | Select-Object -First 1
    if ($preferred) { $ConnectEndpoint = $preferred }
    elseif ($mdnsEndpoints.Count -gt 0) { $ConnectEndpoint = $mdnsEndpoints[0] }
  }

  if (-not $ConnectEndpoint) {
    return [pscustomobject]@{
      Success = $false
      Message = "Paired, but connect endpoint is missing."
    }
  }

  $connectOutput = & "$adb" connect $ConnectEndpoint 2>&1
  $connectText = ($connectOutput | Out-String).Trim()
  Write-AppLog -Message "adb connect $ConnectEndpoint => $connectText"
  if ($connectText -notmatch "connected to|already connected") {
    return [pscustomobject]@{
      Success = $false
      Message = $connectText
    }
  }

  Set-Content -Path $paths.EndpointFile -Value $ConnectEndpoint -Encoding ASCII
  if ($ConnectEndpoint -match "^(\d+\.\d+\.\d+\.\d+):\d+$") {
    Set-Content -Path $paths.IpFile -Value $matches[1] -Encoding ASCII
  }

  return [pscustomobject]@{
    Success         = $true
    ConnectEndpoint = $ConnectEndpoint
    Message         = $connectText
  }
}

Export-ModuleMember -Function Get-MdnsConnectEndpoints, Invoke-DevicePairing
