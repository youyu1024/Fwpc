$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "common.psm1")

function Get-UsbDeviceSerial {
  $adb = Get-AdbPath
  return (& "$adb" devices | Select-String -Pattern "^[^:\s]+\s+device$" |
    Where-Object { $_.Line -notmatch ":" } |
    ForEach-Object { ($_ -split "\s+")[0] } |
    Select-Object -First 1)
}

function Get-DeviceWifiIpFromUsb {
  param([Parameter(Mandatory = $true)][string]$UsbSerial)

  $adb = Get-AdbPath
  $targetIp = (& "$adb" -s $UsbSerial shell ip -f inet addr show wlan0 |
    Select-String -Pattern "inet\s+(\d+\.\d+\.\d+\.\d+)" |
    ForEach-Object { $_.Matches[0].Groups[1].Value } |
    Select-Object -First 1)

  if (-not $targetIp) {
    $targetIp = (& "$adb" -s $UsbSerial shell ip route |
      Select-String -Pattern "src\s+(\d+\.\d+\.\d+\.\d+)" |
      ForEach-Object { $_.Matches[0].Groups[1].Value } |
      Select-Object -First 1)
  }
  return $targetIp
}

function Initialize-UsbTcpipMode {
  $paths = Get-AppPaths
  $adb = Get-AdbPath
  $usbSerial = Get-UsbDeviceSerial
  if (-not $usbSerial) { return $null }

  $targetIp = Get-DeviceWifiIpFromUsb -UsbSerial $usbSerial
  if (-not $targetIp) { return $null }

  & "$adb" -s $usbSerial tcpip 5555 | Out-Null
  Start-Sleep -Seconds 1
  $endpoint = "$targetIp`:5555"
  Set-Content -Path $paths.IpFile -Value $targetIp -Encoding ASCII
  Set-Content -Path $paths.EndpointFile -Value $endpoint -Encoding ASCII
  Write-AppLog -Message "USB tcpip enabled for $endpoint"
  return $endpoint
}

function Get-SavedEndpoint {
  $paths = Get-AppPaths
  if (Test-Path $paths.EndpointFile) {
    $e = (Get-Content $paths.EndpointFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($e) { return $e }
  }

  if (Test-Path $paths.IpFile) {
    $ip = (Get-Content $paths.IpFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($ip) { return "$ip`:5555" }
  }
  return $null
}

function Test-EndpointOnline {
  param([Parameter(Mandatory = $true)][string]$Endpoint)
  $adb = Get-AdbPath
  $devices = & "$adb" devices
  $online = ($devices | Select-String -SimpleMatch "$Endpoint`tdevice")
  return [bool]$online
}

function Connect-DeviceEndpoint {
  param([Parameter(Mandatory = $true)][string]$Endpoint)
  $paths = Get-AppPaths
  $adb = Get-AdbPath
  $connectOutput = & "$adb" connect $Endpoint 2>&1
  $connectText = ($connectOutput | Out-String).Trim()
  Write-AppLog -Message "adb connect $Endpoint => $connectText"
  if ($connectText -match "connected to|already connected") {
    Set-Content -Path $paths.EndpointFile -Value $Endpoint -Encoding ASCII
    if ($Endpoint -match "^(\d+\.\d+\.\d+\.\d+):\d+$") {
      Set-Content -Path $paths.IpFile -Value $matches[1] -Encoding ASCII
    }
    return [pscustomobject]@{ Success = $true; Message = $connectText }
  }
  return [pscustomobject]@{ Success = $false; Message = $connectText }
}

function Invoke-DeviceConnection {
  param([string]$PreferredEndpoint)

  $endpoint = $PreferredEndpoint
  if (-not $endpoint) { $endpoint = Initialize-UsbTcpipMode }
  if (-not $endpoint) { $endpoint = Get-SavedEndpoint }
  if (-not $endpoint) {
    return [pscustomobject]@{ Success = $false; Endpoint = $null; Message = "No endpoint found." }
  }

  if (Test-EndpointOnline -Endpoint $endpoint) {
    return [pscustomobject]@{ Success = $true; Endpoint = $endpoint; Message = "Already online." }
  }

  $result = Connect-DeviceEndpoint -Endpoint $endpoint
  if ($result.Success -and (Test-EndpointOnline -Endpoint $endpoint)) {
    return [pscustomobject]@{ Success = $true; Endpoint = $endpoint; Message = $result.Message }
  }
  return [pscustomobject]@{ Success = $false; Endpoint = $endpoint; Message = $result.Message }
}

function Start-ScrcpyControl {
  param(
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [string]$Bitrate = "6M",
    [int]$MaxFps = 30,
    [int]$MaxSize = 1280
  )

  $paths = Get-AppPaths
  $scrcpy = Get-ScrcpyPath
  $outLog = Join-Path $paths.Logs "scrcpy-out.log"
  $errLog = Join-Path $paths.Logs "scrcpy-err.log"
  $argList = @(
    "--serial", $Endpoint,
    "--window-title", "Android-$Endpoint",
    "--video-bit-rate", $Bitrate,
    "--max-fps", $MaxFps,
    "--max-size", $MaxSize,
    "--no-audio"
  )
  Write-AppLog -Message "scrcpy launch for $Endpoint"
  $proc = Start-Process -FilePath $scrcpy -ArgumentList $argList -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
  Start-Sleep -Milliseconds 1200
  if ($proc.HasExited) {
    $err = ""
    if (Test-Path $errLog) {
      $err = (Get-Content -Path $errLog -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if (-not $err -and (Test-Path $outLog)) {
      $err = (Get-Content -Path $outLog -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if (-not $err) {
      $err = "scrcpy exited immediately (ExitCode=$($proc.ExitCode))."
    }
    Write-AppLog -Message "scrcpy failed: $err" -Level "ERROR"
    return [pscustomobject]@{
      Success = $false
      Message = $err
      Process = $null
    }
  }

  return [pscustomobject]@{
    Success = $true
    Message = "scrcpy started (PID=$($proc.Id))."
    Process = $proc
  }
}

Export-ModuleMember -Function `
  Get-UsbDeviceSerial, Get-DeviceWifiIpFromUsb, Initialize-UsbTcpipMode, `
  Get-SavedEndpoint, Test-EndpointOnline, Connect-DeviceEndpoint, `
  Invoke-DeviceConnection, Start-ScrcpyControl
