$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'common.psm1')
Import-Module (Join-Path $PSScriptRoot 'adb.psm1')

function New-ConnectionResult {
  param([string]$Status, $Device, [string]$Address, [string]$Identity, [string]$Detail, [string]$HardwareSerial)
  [pscustomobject]@{
    Status = $Status
    Device = $Device
    Address = $Address
    Identity = $Identity
    HardwareSerial = $HardwareSerial
    Detail = $Detail
  }
}

function Test-WifiIdentity {
  param($Device, [string]$Identity)
  return ($Identity -and $Device.Kind -eq 'wifi' -and
    $Device.Serial.TrimEnd('.') -ceq "$Identity._adb-tls-connect._tcp")
}

function Get-HardwareSerial {
  param($Device, [System.Threading.CancellationToken]$Token)
  $r = Invoke-Adb -Arguments @('-s', $Device.Serial, 'shell', 'getprop', 'ro.serialno') -Token $Token -TimeoutMs 2500
  if ($r.ExitCode -eq 0 -and $r.Output -cmatch '^[A-Za-z0-9_.-]+$' -and $r.Output -ne 'unknown') {
    return $r.Output
  }
}

function Resolve-WifiDevice {
  param(
    [string]$Identity,
    [string]$Address,
    [string]$HardwareSerial,
    [switch]$ExplicitAddress,
    [switch]$WaitForDiscovery,
    [System.Threading.CancellationToken]$Token = [System.Threading.CancellationToken]::None
  )

  $endpoint = ConvertTo-NetworkEndpoint $Address
  if ($ExplicitAddress -and -not $endpoint) { return (New-ConnectionResult 'invalid-address') }
  $deadline = [DateTime]::UtcNow.AddSeconds(5)
  do {
    $devices = @(Get-AdbDevices -Token $Token)
    $candidates = if ($ExplicitAddress) { @() } else { @($devices | Where-Object { Test-WifiIdentity $_ $Identity }) }
    $candidates = @($candidates | Where-Object { $_ })
    if ($candidates.Count -eq 1 -and $candidates[0].State -in @('unauthorized', 'authorizing')) {
      if ($candidates[0].State -eq 'unauthorized') { return (New-ConnectionResult 'pairing-required' -Identity $Identity) }
    }
    if ($candidates.Count -eq 1 -and $candidates[0].State -eq 'device') {
      $serial = Get-HardwareSerial -Device $candidates[0] -Token $Token
      if ($HardwareSerial -and $serial -cne $HardwareSerial) { return (New-ConnectionResult 'device-mismatch') }
      return (New-ConnectionResult 'connected' -Device $candidates[0] -Address $endpoint -Identity $Identity -HardwareSerial $serial)
    }

    $destination = $null
    if ($ExplicitAddress) {
      $destination = $endpoint
    }
    elseif ($Identity) {
      $discovered = @(Get-AdbWifiServices -Token $Token | Where-Object { $_.Id -ceq $Identity } |
          Select-Object -ExpandProperty Address -Unique)
      if ($discovered.Count -eq 1) { $destination = $discovered[0] }
    }
    if ($destination) {
      $detail = ''
      $match = @($devices | Where-Object { $_.Kind -eq 'wifi' -and $_.Serial -ceq $destination })
      if ($match.Count -ne 1 -or $match[0].State -ne 'device') {
        $connection = Invoke-Adb -Arguments @('connect', $destination) -Token $Token
        $detail = ($connection.Output + ' ' + $connection.Error).Trim()
        if ($detail -match 'failed to authenticate|authentication failed|not authenticated|unauthorized') {
          return (New-ConnectionResult 'pairing-required' -Identity $Identity -Detail $detail)
        }
        $devices = @(Get-AdbDevices -Token $Token)
        $match = @($devices | Where-Object { $_.Kind -eq 'wifi' -and $_.Serial -ceq $destination -and $_.State -eq 'device' })
        if ($match.Count -eq 0 -and -not $ExplicitAddress) {
          $match = @($devices | Where-Object { (Test-WifiIdentity $_ $Identity) -and $_.State -eq 'device' })
        }
      }
      if ($match.Count -eq 1 -and $match[0].State -eq 'device') {
        $serial = Get-HardwareSerial -Device $match[0] -Token $Token
        if ($HardwareSerial -and $serial -cne $HardwareSerial) { return (New-ConnectionResult 'device-mismatch') }
        return (New-ConnectionResult 'connected' -Device $match[0] -Address $destination -Identity $Identity -HardwareSerial $serial)
      }
      if ($ExplicitAddress) { return (New-ConnectionResult 'network-unreachable' -Detail $detail) }
    }

    if (-not $WaitForDiscovery -or [DateTime]::UtcNow -ge $deadline) { break }
    if ($Token.WaitHandle.WaitOne(400)) { $Token.ThrowIfCancellationRequested() }
  } while ($true)
  return (New-ConnectionResult 'address-needed' -Identity $Identity)
}

function Get-UsbDevices {
  param([System.Threading.CancellationToken]$Token)
  $devices = @(Get-AdbDevices -Token $Token)
  $devices | Where-Object { $_.Kind -eq 'usb' }
  # ADB's libusb backend may omit the bus path. Ask ADB to identify a sole USB transport.
  if ($devices.Kind -notcontains 'usb' -and $devices.Kind -contains 'unknown') {
    $only = Invoke-Adb -Arguments @('-d', 'get-serialno') -Token $Token
    if ($only.ExitCode -eq 0) {
      foreach ($device in ($devices | Where-Object { $_.Kind -eq 'unknown' -and $_.Serial -ceq $only.Output })) {
        $device.Kind = 'usb'
        $device
      }
    }
  }
}

function Resolve-UsbDevice {
  param([string]$Serial, [System.Threading.CancellationToken]$Token, [int]$AuthorizationSeconds = 25)
  $devices = @(Get-UsbDevices -Token $Token)
  if ($Serial) { $devices = @($devices | Where-Object { $_.Serial -ceq $Serial }) }
  if ($devices.Count -eq 0) { return (New-ConnectionResult 'usb-missing') }
  if ($devices.Count -gt 1) {
    return [pscustomobject]@{ Status = 'choose-usb'; Devices = $devices }
  }

  $device = $devices[0]
  $deadline = [DateTime]::UtcNow.AddSeconds($AuthorizationSeconds)
  while ($device.State -in @('unauthorized', 'authorizing', 'connecting') -and [DateTime]::UtcNow -lt $deadline) {
    if ($Token.WaitHandle.WaitOne(450)) { $Token.ThrowIfCancellationRequested() }
    $device = Get-UsbDevices -Token $Token | Where-Object { $_.Serial -ceq $devices[0].Serial } | Select-Object -First 1
    if (-not $device) { return (New-ConnectionResult 'usb-missing' -Device $devices[0]) }
  }
  if ($device.State -eq 'device') { return (New-ConnectionResult 'connected' -Device $device) }
  if ($device.State -in @('unauthorized', 'authorizing')) { return (New-ConnectionResult 'usb-authorization' -Device $device) }
  return (New-ConnectionResult 'usb-offline' -Device $device)
}

function Get-SelectedDevice {
  param($Device, [string]$HardwareSerial, [System.Threading.CancellationToken]$Token)
  $available = if ($Device.Kind -eq 'usb') { Get-UsbDevices -Token $Token } else { Get-AdbDevices -Token $Token }
  $devices = @($available | Where-Object { $_.Serial -ceq $Device.Serial -and $_.State -eq 'device' -and $_.Kind -eq $Device.Kind })
  if ($devices.Count -ne 1) { return }
  if ($HardwareSerial -and (Get-HardwareSerial -Device $devices[0] -Token $Token) -cne $HardwareSerial) { return }
  return $devices[0]
}

function Start-ScrcpyControl {
  param(
    [Parameter(Mandatory)]$Device,
    [string]$HardwareSerial,
    [string]$Bitrate = '6M',
    [int]$MaxFps = 30,
    [int]$MaxSize = 1280,
    [hashtable]$Options = @{},
    [System.Threading.CancellationToken]$Token = [System.Threading.CancellationToken]::None
  )
  $Token.ThrowIfCancellationRequested()
  if ($Device.Serial -notmatch '^[A-Za-z0-9_.:%\[\]-]+$' -or $Bitrate -notmatch '^[1-9][0-9]{0,8}[KM]?$') {
    return [pscustomobject]@{ Status = 'control-failed'; Detail = 'Invalid device serial or video bitrate.' }
  }
  $selected = Get-SelectedDevice -Device $Device -HardwareSerial $HardwareSerial -Token $Token
  if (-not $selected) {
    return [pscustomobject]@{ Status = 'control-failed'; Detail = 'The selected ADB device is no longer ready or could not be verified.' }
  }
  $Token.ThrowIfCancellationRequested()
  $paths = Get-AppPaths
  $logId = [Guid]::NewGuid().ToString('N')
  $outLog = Join-Path $paths.Logs "scrcpy-$logId.out.log"
  $errLog = Join-Path $paths.Logs "scrcpy-$logId.err.log"
  $arguments = @('--serial', $Device.Serial, '--video-bit-rate', $Bitrate, '--max-fps', $MaxFps,
    '--max-size', $MaxSize)
  $flags = [ordered]@{
    noAudio = '--no-audio'; turnScreenOff = '--turn-screen-off'; stayAwake = '--stay-awake'
    alwaysOnTop = '--always-on-top'; fullscreen = '--fullscreen'; showTouches = '--show-touches'
  }
  foreach ($key in $flags.Keys) {
    if ($Options[$key]) { $arguments += $flags[$key] }
  }
  $scrcpy = Get-ScrcpyPath
  $process = Start-Process -FilePath $scrcpy -WorkingDirectory (Split-Path $scrcpy) -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog
  try {
    if ($Token.WaitHandle.WaitOne(900)) { $Token.ThrowIfCancellationRequested() }
    if ($process.HasExited) {
      $detail = Get-Content -LiteralPath $errLog -Raw
      $exitCode = $process.ExitCode
      $process.Dispose()
      if (-not $detail) { $detail = "scrcpy exited (code $exitCode)." }
      return [pscustomobject]@{ Status = 'control-failed'; Detail = $detail }
    }
    return [pscustomobject]@{ Status = 'controlling'; Device = $Device; Process = $process; ErrorLog = $errLog }
  }
  catch {
    if (-not $process.HasExited) { $process.Kill() }
    $process.Dispose()
    throw
  }
}

function Invoke-PhoneAction {
  param($Device, [string]$HardwareSerial, [int]$KeyCode, [System.Threading.CancellationToken]$Token)

  $selected = Get-SelectedDevice -Device $Device -HardwareSerial $HardwareSerial -Token $Token
  if (-not $selected) { return [pscustomobject]@{ Status = 'action-failed'; Detail = 'The selected device is no longer available.' } }

  if ($KeyCode -in @(3, 4, 24, 25, 26, 187)) {
    $result = Invoke-Adb -Arguments @('-s', $selected.Serial, 'shell', 'input', 'keyevent', [string]$KeyCode) -Token $Token
    if ($result.ExitCode -ne 0) { return [pscustomobject]@{ Status = 'action-failed'; Detail = $result.Error } }
    return [pscustomobject]@{ Status = 'action-complete' }
  }
  if ($KeyCode -ne -1) { return [pscustomobject]@{ Status = 'action-failed'; Detail = 'Unknown phone action.' } }

  $paths = Get-AppPaths
  $name = 'screenshot-{0}-{1}.png' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [Guid]::NewGuid().ToString('N').Substring(0, 8)
  $destination = Join-Path $paths.Logs $name
  $temporary = "$destination.tmp"
  try {
    $result = Invoke-Adb -Arguments @('-s', $selected.Serial, 'exec-out', 'screencap', '-p') -OutputPath $temporary -TimeoutMs 8000 -Token $Token
    if ($result.ExitCode -ne 0) { return [pscustomobject]@{ Status = 'action-failed'; Detail = $result.Error } }
    $stream = [IO.File]::OpenRead($temporary)
    try {
      $header = New-Object byte[] 8
      $count = $stream.Read($header, 0, $header.Length)
    } finally { $stream.Dispose() }
    if ($count -ne 8 -or [BitConverter]::ToString($header) -ne '89-50-4E-47-0D-0A-1A-0A') {
      return [pscustomobject]@{ Status = 'action-failed'; Detail = 'The phone did not return a valid PNG screenshot.' }
    }
    $Token.ThrowIfCancellationRequested()
    [IO.File]::Move($temporary, $destination)
    return [pscustomobject]@{ Status = 'action-complete'; Path = $destination; Detail = "Saved screenshot to $destination" }
  } finally {
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
  }
}

Export-ModuleMember -Function Resolve-WifiDevice, Resolve-UsbDevice, Start-ScrcpyControl, Invoke-PhoneAction
