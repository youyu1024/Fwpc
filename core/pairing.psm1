$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'adb.psm1')

function Invoke-DevicePairing {
  param(
    [string]$PairEndpoint,
    [string]$PairCode,
    [System.Threading.CancellationToken]$Token = [System.Threading.CancellationToken]::None
  )

  $address = ConvertTo-NetworkEndpoint $PairEndpoint
  if (-not $address) { return [pscustomobject]@{ Status = 'invalid-address' } }
  if ($PairCode -notmatch '^[0-9]{6}$') { return [pscustomobject]@{ Status = 'invalid-code' } }

  $result = Invoke-Adb -Arguments @('pair', $address) -InputLine $PairCode -Token $Token -TimeoutMs 12000
  if ($result.ExitCode -eq 0 -and $result.Output -match 'Successfully paired to ') {
    $identity = if ($result.Output -cmatch '\[guid=([A-Za-z0-9_.-]+)\]') { $Matches[1] } else { '' }
    return [pscustomobject]@{ Status = 'paired'; Identity = $identity }
  }
  # Keep the one-time code out of the process command line and diagnostic output.
  $detail = ($result.Output + ' ' + $result.Error).Trim().Replace($PairCode, '[redacted]')
  $status = if ($detail -match 'refused|unable to connect|failed to connect|unreachable|timed out|No route') {
    'pair-unreachable'
  } else { 'pair-failed' }
  return [pscustomobject]@{ Status = $status; Detail = $detail }
}

Export-ModuleMember -Function Invoke-DevicePairing
