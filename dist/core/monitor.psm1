$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "common.psm1")
Import-Module (Join-Path $PSScriptRoot "control.psm1")

function Get-ConnectionStatus {
  param([string]$Endpoint)
  if (-not $Endpoint) {
    $Endpoint = Get-SavedEndpoint
  }
  if (-not $Endpoint) {
    return [pscustomobject]@{
      Status   = "disconnected"
      Endpoint = $null
      Message  = "No saved endpoint."
    }
  }

  if (Test-EndpointOnline -Endpoint $Endpoint) {
    return [pscustomobject]@{
      Status   = "connected"
      Endpoint = $Endpoint
      Message  = "Device online."
    }
  }

  $reconnect = Invoke-DeviceConnection -PreferredEndpoint $Endpoint
  if ($reconnect.Success) {
    Write-AppLog -Message "Auto reconnected: $($reconnect.Endpoint)"
    return [pscustomobject]@{
      Status   = "connected"
      Endpoint = $reconnect.Endpoint
      Message  = "Reconnected."
    }
  }

  return [pscustomobject]@{
    Status   = "pairing-required"
    Endpoint = $Endpoint
    Message  = $reconnect.Message
  }
}

Export-ModuleMember -Function Get-ConnectionStatus
