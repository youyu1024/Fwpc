$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'common.psm1')

function Invoke-Adb {
  param(
    [Parameter(Mandatory)][string[]]$Arguments,
    [System.Threading.CancellationToken]$Token = [System.Threading.CancellationToken]::None,
    [int]$TimeoutMs = 5000,
    [string]$InputLine,
    [string]$OutputPath
  )

  $Token.ThrowIfCancellationRequested()
  # Callers pass individual protocol tokens, never a shell command.
  foreach ($argument in $Arguments) {
    if ($argument -notmatch '^[A-Za-z0-9_.:%\[\]-]+$') { throw 'Invalid ADB argument.' }
  }
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = Get-AdbPath
  $info.Arguments = $Arguments -join ' '
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputLine')
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $info
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $targetStream = $null
  try {
    [void]$process.Start()
    if ($OutputPath) {
      $targetStream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
      $output = $process.StandardOutput.BaseStream.CopyToAsync($targetStream)
    } else {
      $output = $process.StandardOutput.ReadToEndAsync()
    }
    $errors = $process.StandardError.ReadToEndAsync()
    if ($info.RedirectStandardInput) {
      $process.StandardInput.WriteLine($InputLine)
      $process.StandardInput.Close()
    }
    while (-not ($process.WaitForExit(50) -and $output.IsCompleted -and $errors.IsCompleted)) {
      $Token.ThrowIfCancellationRequested()
      if ($watch.ElapsedMilliseconds -ge $TimeoutMs) {
        throw [System.TimeoutException]::new('ADB request timed out.')
      }
      if ($process.HasExited) { [void]$Token.WaitHandle.WaitOne(50) }
    }
    $Token.ThrowIfCancellationRequested()
    $text = if ($OutputPath) { [void]$output.GetAwaiter().GetResult(); '' }
      else { $output.GetAwaiter().GetResult().Trim() }
    [pscustomobject]@{
      ExitCode = $process.ExitCode
      Output   = $text
      Error    = $errors.GetAwaiter().GetResult().Trim()
    }
  }
  finally {
    try { if (-not $process.HasExited) { $process.Kill() } } catch [System.InvalidOperationException] {}
    if ($targetStream) { $targetStream.Dispose() }
    $process.Dispose()
  }
}

function ConvertTo-NetworkEndpoint {
  param([string]$Address)
  if ($Address -notmatch '^(?:\[(?<host>[A-Fa-f0-9:.%]+)\]|(?<host>[0-9.]+)):(?<port>[0-9]{1,5})$') { return }
  $addressPart = $Matches.host
  $port = [int]$Matches.port
  if ($port -lt 1 -or $port -gt 65535) { return }
  $ip = $null
  if (-not [System.Net.IPAddress]::TryParse($addressPart, [ref]$ip)) { return }
  if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
    return "[$ip]:$port"
  }
  if ($addressPart -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$') { return }
  return ('{0}:{1}' -f $ip, $port)
}

function Get-AdbDevices {
  param([System.Threading.CancellationToken]$Token = [System.Threading.CancellationToken]::None)
  $result = Invoke-Adb -Arguments @('devices', '-l') -Token $Token
  if ($result.ExitCode -ne 0) { throw ('Unable to list ADB devices. ' + $result.Error) }
  foreach ($line in ($result.Output -split '\r?\n')) {
    if ($line -notmatch '^(?<serial>[A-Za-z0-9_.:%\[\]-]+)\s+(?<state>device|offline|unauthorized|authorizing|connecting|recovery|sideload|bootloader|no permissions)(?<details>\s.*)?$') { continue }
    $serial = $Matches.serial
    $state = $Matches.state
    $details = $Matches.details
    $kind = if ($details -match '(?:^|\s)usb:\S+') { 'usb' }
      elseif ($serial -match '^emulator-\d+$') { 'emulator' }
      elseif ($serial -match ':' -or $serial -match '\._adb-tls-connect\._tcp\.?$') { 'wifi' }
      else { 'unknown' }
    $model = if ($details -match '(?:^|\s)model:(\S+)') { $Matches[1].Replace('_', ' ') } else { '' }
    [pscustomobject]@{ Serial = $serial; State = $state; Kind = $kind; Model = $model }
  }
}

function Get-AdbWifiServices {
  param([System.Threading.CancellationToken]$Token = [System.Threading.CancellationToken]::None)
  $result = Invoke-Adb -Arguments @('mdns', 'services') -Token $Token -TimeoutMs 2500
  if ($result.ExitCode -ne 0) { return }
  foreach ($line in ($result.Output -split '\r?\n')) {
    if ($line -notmatch '^\s*(?<name>[A-Za-z0-9_.-]+)\s+_adb-tls-connect\._tcp\.?\s+(?<endpoint>\S+)\s*$') { continue }
    $name = $Matches.name.TrimEnd('.')
    $address = ConvertTo-NetworkEndpoint $Matches.endpoint
    if (-not $address) { continue }
    [pscustomobject]@{ Id = $name; Address = $address }
  }
}

Export-ModuleMember -Function Invoke-Adb, ConvertTo-NetworkEndpoint, Get-AdbDevices, Get-AdbWifiServices
