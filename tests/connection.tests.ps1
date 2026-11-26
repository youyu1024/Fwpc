$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cache = Join-Path $root '.cache'
$fixture = Join-Path $cache ("connection-test-" + [Guid]::NewGuid().ToString('N'))
$runtime = Join-Path $fixture 'runtime\scrcpy'
$originalFixture = $env:FWPC_MOCK_ADB

function Use-Responses([hashtable]$Responses) {
  $Responses | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixture 'responses.json') -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $fixture 'calls.txt') -Value ''
}

function Assert-Equal($Actual, $Expected, [string]$Context) {
  if ($Actual -cne $Expected) { throw "$Context expected [$Expected], received [$Actual]." }
}

function Assert-NoCalls([string]$Pattern, [string]$Context) {
  if (Select-String -LiteralPath (Join-Path $fixture 'calls.txt') -Pattern $Pattern) { throw $Context }
}

function Device-List([string[]]$Devices = @()) {
  return (@('List of devices attached') + $Devices) -join [Environment]::NewLine
}

try {
  New-Item -ItemType Directory -Path $runtime -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $root 'core') -Destination $fixture -Recurse
  $env:FWPC_MOCK_ADB = $fixture
  Add-Type -Path (Join-Path $PSScriptRoot 'mock-adb.cs') -ReferencedAssemblies @('System.Web.Extensions.dll') -OutputAssembly (Join-Path $runtime 'adb.exe') -OutputType ConsoleApplication
  Copy-Item -LiteralPath (Join-Path $runtime 'adb.exe') -Destination (Join-Path $runtime 'scrcpy.exe')
  foreach ($file in @('AdbWinApi.dll', 'AdbWinUsbApi.dll', 'scrcpy-server', 'SDL3.dll',
      'avcodec-test.dll', 'avformat-test.dll', 'avutil-test.dll', 'swresample-test.dll')) {
    New-Item -ItemType File -Path (Join-Path $runtime $file) | Out-Null
  }

  Import-Module (Join-Path $fixture 'core\adb.psm1')
  Import-Module (Join-Path $fixture 'core\pairing.psm1')
  Import-Module (Join-Path $fixture 'core\control.psm1')
  Import-Module (Join-Path $fixture 'core\monitor.psm1')
  $none = [System.Threading.CancellationToken]::None
  $target = 'adb-target'
  $service = "$target._adb-tls-connect._tcp"
  $paired = '10.0.0.5:31700'
  $wifi = '10.0.0.5:37100'
  $next = '10.0.0.5:37101'
  $other = '10.0.0.6:37100'
  $serviceType = '_adb-tls-connect._tcp'
  $empty = Device-List
  $otherOnline = Device-List @("$other device model:Other_Phone")
  $targetOnline = Device-List @("$service device model:Test_Phone", "$other device model:Other_Phone")
  $usbConnected = Device-List @('usb-one device usb:1-2 model:USB_Phone', 'emulator-5554 device model:Emulator', "$service device model:WiFi_Phone")

  Use-Responses @{
    "pair $paired" = @(@{ input = '012345'; output = "Enter pairing code: Successfully paired to $paired [guid=$target]" })
  }
  Assert-Equal (Invoke-DevicePairing -PairEndpoint $paired -PairCode '123').Status 'invalid-code' 'Code validation'
  Assert-Equal (Invoke-DevicePairing -PairEndpoint '10.0.0.5:65536' -PairCode '012345').Status 'invalid-address' 'Port validation'
  Assert-Equal (Invoke-DevicePairing -PairEndpoint $paired -PairCode '012345').Identity $target 'Separate pairing identity'
  Assert-NoCalls '012345|^connect' 'Pairing leaked the code or attempted connection.'
  Assert-Equal (ConvertTo-NetworkEndpoint '[fe80::1]:1234') '[fe80::1]:1234' 'IPv6 address'

  Use-Responses @{
    "pair $paired" = @(@{ input = '111111'; output = 'Wrong pairing code 111111'; exit = 1 })
  }
  $failure = Invoke-DevicePairing -PairEndpoint $paired -PairCode '111111'
  Assert-Equal $failure.Status 'pair-failed' 'Expired or incorrect code'
  if ($failure.Detail -match '111111') { throw 'A failed pairing revealed the code.' }

  Use-Responses @{
    'devices -l' = @(@{ output = $otherOnline })
    'mdns services' = @(@{ output = "adb-other $serviceType $other" })
  }
  Assert-Equal (Resolve-WifiDevice -Identity $target).Status 'address-needed' 'Unrelated discovery'
  Assert-NoCalls '^connect' 'Unrelated discovery attempted to connect to another phone.'

  Use-Responses @{
    'devices -l' = @(@{ output = $otherOnline }, @{ output = $targetOnline })
    'mdns services' = @(@{ output = "adb-other $serviceType $other" })
    "-s $service shell getprop ro.serialno" = @(@{ output = 'phone-id' })
  }
  Assert-Equal (Resolve-WifiDevice -Identity $target -WaitForDiscovery).Device.Serial $service 'Delayed auto-discovery'
  Assert-NoCalls '^connect' 'An already-connected service was unnecessarily reconnected.'

  Use-Responses @{
    'devices -l' = @(@{ output = $empty }, @{ output = (Device-List @("$next device model:Test_Phone")) })
    'mdns services' = @(@{ output = "$target $serviceType $next" })
    "connect $next" = @(@{ output = "connected to $next" })
    "-s $next shell getprop ro.serialno" = @(@{ output = 'phone-id' })
  }
  $changed = Get-ConnectionStatus -Identity $target -Address $wifi -HardwareSerial 'phone-id' -Token $none
  Assert-Equal $changed.Status 'connected' 'Port change reconnect'
  Assert-Equal $changed.Address $next 'Fresh port selected'
  Assert-NoCalls "^connect $([regex]::Escape($wifi))$" 'Reconnection tried the stale port.'

  Use-Responses @{
    'devices -l' = @(@{ output = $empty }, @{ output = (Device-List @("$wifi device model:Test_Phone")) })
    "connect $wifi" = @(@{ output = "already connected to $wifi" })
    "-s $wifi shell getprop ro.serialno" = @(@{ output = 'phone-id' })
  }
  $manual = Resolve-WifiDevice -Identity $target -Address $wifi -ExplicitAddress
  Assert-Equal $manual.Status 'connected' 'Manual connection without discovery'
  Assert-Equal $manual.HardwareSerial 'phone-id' 'Remember selected phone'
  Assert-NoCalls '^pair |^mdns ' 'Manual connection restarted pairing or depended on discovery.'

  Use-Responses @{
    'devices -l' = @(@{ output = (Device-List @("$wifi device model:Wrong_Phone")) })
    "-s $wifi shell getprop ro.serialno" = @(@{ output = 'different-phone' })
  }
  Assert-Equal (Resolve-WifiDevice -Identity $target -Address $wifi -HardwareSerial 'phone-id' -ExplicitAddress).Status 'device-mismatch' 'Replacement at saved address'

  Use-Responses @{
    'devices -l' = @(@{ output = $empty })
    "connect $wifi" = @(@{ output = "failed to connect to $wifi" })
  }
  Assert-Equal (Resolve-WifiDevice -Address $wifi -ExplicitAddress).Status 'network-unreachable' 'Unreachable network'

  Use-Responses @{
    'devices -l' = @(@{ output = (Device-List @("$service unauthorized")) })
  }
  Assert-Equal (Resolve-WifiDevice -Identity $target).Status 'pairing-required' 'Revoked authorization'

  Use-Responses @{
    'devices -l' = @(@{ output = (Device-List @(
          'usb-one unauthorized usb:1-2', 'usb-two offline usb:1-3', 'emulator-5554 device', "$service device")) })
  }
  $choices = Resolve-UsbDevice -Token $none
  Assert-Equal $choices.Status 'choose-usb' 'USB picker'
  Assert-Equal ($choices.Devices.Serial -join ',') 'usb-one,usb-two' 'Transport discrimination'
  Assert-Equal (Resolve-UsbDevice -Serial 'usb-two' -Token $none).Status 'usb-offline' 'Offline USB'

  Use-Responses @{
    'devices -l' = @(@{ output = (Device-List @('usb-one unauthorized usb:1-2')) }, @{ output = $usbConnected })
  }
  $usb = Resolve-UsbDevice -Token $none
  Assert-Equal $usb.Status 'connected' 'USB authorization to ready'
  Assert-Equal $usb.Device.Serial 'usb-one' 'USB identity after authorization'
  $control = Start-ScrcpyControl -Device $usb.Device -Options @{ stayAwake = $true; noAudio = $true } -Token $none
  try {
    Assert-Equal $control.Status 'controlling' 'USB control launch'
    if (-not (Select-String -LiteralPath (Join-Path $fixture 'calls.txt') -Pattern '^--serial usb-one .*--no-audio --stay-awake')) {
      throw 'scrcpy was not given the selected USB serial.'
    }
    Assert-NoCalls '^tcpip|^connect|^pair' 'USB control invoked a wireless command.'
    if (Test-Path -LiteralPath (Join-Path $fixture 'state\last-endpoint.txt')) { throw 'USB control saved a Wi-Fi address.' }
  }
  finally {
    if ($control.Process) {
      if (-not $control.Process.HasExited) { $control.Process.Kill(); $control.Process.WaitForExit() }
      $control.Process.Dispose()
    }
  }

  $png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XkYQAAAAASUVORK5CYII='
  Use-Responses @{
    'devices -l' = @(@{ output = $usbConnected })
    '-s usb-one shell input keyevent 4' = @(@{})
    '-s usb-one exec-out screencap -p' = @(@{ bytes = $png })
  }
  Assert-Equal (Invoke-PhoneAction -Device $usb.Device -KeyCode 4 -Token $none).Status 'action-complete' 'USB key target'
  $screenshot = Invoke-PhoneAction -Device $usb.Device -KeyCode -1 -Token $none
  Assert-Equal $screenshot.Status 'action-complete' 'USB screenshot'
  Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($screenshot.Path))) $png 'Screenshot binary integrity'
  Assert-NoCalls 'shell.*screencap|^pull|^rm' 'Screenshot wrote temporary files on the phone.'
  Use-Responses @{ 'devices -l' = @(@{ output = $targetOnline }) }
  Assert-Equal (Resolve-UsbDevice -Serial 'usb-one' -Token $none -AuthorizationSeconds 0).Status 'usb-missing' 'Unplugged USB'

  Use-Responses @{ 'devices -l' = @(@{ delayMs = 4000 }) }
  $cancel = New-Object Threading.CancellationTokenSource
  try {
    $cancel.CancelAfter(220)
    try {
      Invoke-Adb -Arguments @('devices', '-l') -Token $cancel.Token
      throw 'Expected cancellation.'
    }
    catch {
      if ($_.Exception.GetBaseException() -isnot [System.OperationCanceledException]) { throw }
    }
  }
  finally { $cancel.Dispose() }
  try {
    Invoke-Adb -Arguments @('devices', '-l') -TimeoutMs 220
    throw 'Expected timeout.'
  }
  catch {
    if ($_.Exception.GetBaseException() -isnot [System.TimeoutException]) { throw }
  }
  'Connection regression checks passed.'
}
finally {
  $env:FWPC_MOCK_ADB = $originalFixture
  if (Test-Path -LiteralPath $fixture) {
    $resolvedFixture = (Resolve-Path -LiteralPath $fixture).ProviderPath
    $fixtureItem = Get-Item -LiteralPath $resolvedFixture -Force
    if ($resolvedFixture -eq [IO.Path]::GetFullPath($fixture) -and
        -not ($fixtureItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
  }
}
