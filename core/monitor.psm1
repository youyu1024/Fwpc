$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'control.psm1')

function Get-ConnectionStatus {
  param(
    [string]$Identity,
    [string]$Address,
    [string]$HardwareSerial,
    [System.Threading.CancellationToken]$Token
  )
  if (-not $Identity) { return [pscustomobject]@{ Status = 'address-needed' } }
  Resolve-WifiDevice -Identity $Identity -Address $Address -HardwareSerial $HardwareSerial -Token $Token
}

Export-ModuleMember -Function Get-ConnectionStatus
