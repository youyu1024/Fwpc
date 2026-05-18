$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch {}

function Resolve-AppRoot {
  $candidates = @()

  if ($PSScriptRoot) {
    $candidates += (Join-Path $PSScriptRoot "..")
  }

  $exePath = [Environment]::GetCommandLineArgs()[0]
  if ($exePath) {
    $candidates += (Split-Path -Parent $exePath)
  }

  $candidates += (Get-Location).Path

  foreach ($candidate in $candidates) {
    if (-not $candidate) { continue }
    $resolved = $null
    try { $resolved = (Resolve-Path $candidate -ErrorAction Stop).Path } catch { continue }
    if (Test-Path (Join-Path $resolved "core\common.psm1")) {
      return $resolved
    }
  }

  throw "Cannot locate app root. core\common.psm1 not found."
}

$appRoot = Resolve-AppRoot
Set-Location $appRoot

Import-Module (Join-Path $appRoot "core\common.psm1")
Import-Module (Join-Path $appRoot "core\pairing.psm1")
Import-Module (Join-Path $appRoot "core\control.psm1")
Import-Module (Join-Path $appRoot "core\monitor.psm1")

$paths = Get-AppPaths

$i18n = @{
  "zh-CN" = @{
    app_title = "Wi-Fi 手机控制台"
    top_title = "Android Wi-Fi 控制中心"
    language = "语言"
    theme = "主题"
    profile = "设备配置"
    profile_name = "配置名"
    save_profile = "保存配置"
    delete_profile = "删除配置"
    status = "状态"
    endpoint = "连接端点"
    monitor = "启用自动重连监控"
    tab_pair = "配对"
    tab_control = "控制"
    tab_settings = "设置"
    tab_logs = "日志"
    tab_about = "关于"
    pair_endpoint = "配对端点 (IP:PORT)"
    pair_code = "配对码 (6位)"
    connect_endpoint = "连接端点"
    btn_pair = "配对并连接"
    btn_connect = "确保已连接"
    btn_control = "启动控制 (scrcpy)"
    bitrate = "码率"
    fps = "帧率"
    max_size = "最大分辨率"
    monitor_interval = "监控间隔(秒)"
    save_settings = "保存设置"
    clear_logs = "清空面板"
    open_logs = "打开日志目录"
    about_text = "用于 Android 设备 Wi-Fi 配对、自动重连与 scrcpy 控制。"
    msg_profile_saved = "配置已保存"
    msg_profile_deleted = "配置已删除"
    msg_settings_saved = "设置已保存"
    msg_input_required = "请填写配对端点和配对码。"
    msg_pairing = "正在配对设备..."
    msg_connecting = "正在确保连接..."
    msg_cannot_delete_default = "默认配置 default 不可删除。"
    state_connected = "已连接"
    state_reconnecting = "重连中"
    state_disconnected = "未连接"
    state_pairing_required = "需要重新配对"
    msg_runtime_missing = "缺少运行时：未找到 runtime\scrcpy。请检查 release 包是否完整，或确认该目录未被误删。"
    msg_runtime_fix_guide = "修复指引：请检查并恢复路径 runtime\scrcpy（需包含 scrcpy.exe 与 adb.exe）。高级用户可手动执行 winget install Genymobile.scrcpy。"
  }
  "en-US" = @{
    app_title = "Wi-Fi Phone Control"
    top_title = "Android Wi-Fi Control Center"
    language = "Language"
    theme = "Theme"
    profile = "Profile"
    profile_name = "Profile Name"
    save_profile = "Save Profile"
    delete_profile = "Delete Profile"
    status = "Status"
    endpoint = "Endpoint"
    monitor = "Enable auto reconnect monitor"
    tab_pair = "Pairing"
    tab_control = "Control"
    tab_settings = "Settings"
    tab_logs = "Logs"
    tab_about = "About"
    pair_endpoint = "Pair Endpoint (IP:PORT)"
    pair_code = "Pair Code (6-digit)"
    connect_endpoint = "Connect Endpoint"
    btn_pair = "Pair & Connect"
    btn_connect = "Ensure Connected"
    btn_control = "Start Control (scrcpy)"
    bitrate = "Bitrate"
    fps = "FPS"
    max_size = "Max Size"
    monitor_interval = "Monitor Interval (sec)"
    save_settings = "Save Settings"
    clear_logs = "Clear Panel"
    open_logs = "Open Log Folder"
    about_text = "Android Wi-Fi pairing, auto reconnect, and scrcpy control."
    msg_profile_saved = "Profile saved"
    msg_profile_deleted = "Profile deleted"
    msg_settings_saved = "Settings saved"
    msg_input_required = "Pair endpoint and pair code are required."
    msg_pairing = "Pairing device..."
    msg_connecting = "Ensuring connectivity..."
    msg_cannot_delete_default = "Default profile cannot be deleted."
    state_connected = "Connected"
    state_reconnecting = "Reconnecting"
    state_disconnected = "Disconnected"
    state_pairing_required = "Pairing Required"
    msg_runtime_missing = "Runtime missing: runtime\scrcpy was not found. Check whether the release package is incomplete or the folder was deleted."
    msg_runtime_fix_guide = "Fix guide: restore runtime\scrcpy (must include scrcpy.exe and adb.exe). Advanced users may run winget install Genymobile.scrcpy manually."
  }
}

function Get-DefaultSettings {
  return [pscustomobject]@{
    monitorIntervalSec = 8
    bitrate            = "6M"
    maxFps             = 30
    maxSize            = 1280
    language           = "zh-CN"
    theme              = "dark"
  }
}

function Normalize-Settings {
  param([Parameter(Mandatory = $true)]$RawSettings)
  $default = Get-DefaultSettings
  foreach ($p in $default.PSObject.Properties.Name) {
    if (-not $RawSettings.PSObject.Properties[$p]) {
      $RawSettings | Add-Member -NotePropertyName $p -NotePropertyValue $default.$p
    }
  }
  return $RawSettings
}

$settings = Normalize-Settings -RawSettings (Read-JsonFile -Path $paths.SettingsFile -DefaultValue (Get-DefaultSettings))
$profiles = Read-JsonFile -Path $paths.ProfileFile -DefaultValue ([pscustomobject]@{
    defaultProfile = "default"
    items          = @([pscustomobject]@{ name = "default"; endpoint = "" })
  })

if (-not $profiles.items -or $profiles.items.Count -eq 0) {
  $profiles.items = @([pscustomobject]@{ name = "default"; endpoint = "" })
  $profiles.defaultProfile = "default"
}
if ($settings.language -notin @("zh-CN", "en-US")) { $settings.language = "zh-CN" }
if ($settings.theme -notin @("dark", "light")) { $settings.theme = "dark" }

function T {
  param([Parameter(Mandatory = $true)][string]$Key)
  return $i18n[$script:settings.language][$Key]
}

function Save-Settings { Write-JsonFile -Path $paths.SettingsFile -Value $script:settings }
function Save-Profiles { Write-JsonFile -Path $paths.ProfileFile -Value $script:profiles }
function Find-ProfileByName { param([string]$Name) return $script:profiles.items | Where-Object { $_.name -eq $Name } | Select-Object -First 1 }

function Refresh-ProfileCombo {
  param([string]$PreferredName)
  $current = $PreferredName
  $cmbProfile.Items.Clear()
  foreach ($item in $profiles.items) { [void]$cmbProfile.Items.Add($item.name) }
  if ($cmbProfile.Items.Count -eq 0) { [void]$cmbProfile.Items.Add("default") }
  if (-not $current -or -not ($cmbProfile.Items -contains $current)) { $current = [string]$profiles.defaultProfile }
  if (-not $current -or -not ($cmbProfile.Items -contains $current)) { $current = [string]$cmbProfile.Items[0] }
  $cmbProfile.SelectedItem = $current
}

function Append-Log {
  param([string]$Message, [string]$Level = "INFO")
  $line = "{0}  [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
  $txtLog.AppendText($line + [Environment]::NewLine)
  Write-AppLog -Message $Message -Level $Level
}

function Get-LocalizedState {
  param([string]$Raw)
  switch ($Raw) {
    "connected" { return T "state_connected" }
    "reconnecting" { return T "state_reconnecting" }
    "pairing-required" { return T "state_pairing_required" }
    default { return T "state_disconnected" }
  }
}

function Set-UiStatus {
  param([string]$Status, [string]$Message)
  $lblStatusValue.Text = Get-LocalizedState -Raw $Status
  switch ($Status) {
    "connected" { $lblStatusValue.ForeColor = [System.Drawing.Color]::FromArgb(67, 160, 71) }
    "reconnecting" { $lblStatusValue.ForeColor = [System.Drawing.Color]::FromArgb(251, 140, 0) }
    default { $lblStatusValue.ForeColor = [System.Drawing.Color]::FromArgb(229, 57, 53) }
  }
  $lblEndpointValue.Text = $txtConnectEndpoint.Text.Trim()
  if ($Message) { Append-Log -Message "$($lblStatusValue.Text): $Message" }
}

function Show-RuntimeRepairHint {
  $missingMsg = T "msg_runtime_missing"
  $guideMsg = T "msg_runtime_fix_guide"
  Append-Log -Message $missingMsg -Level "ERROR"
  Append-Log -Message $guideMsg -Level "WARN"
  [System.Windows.Forms.MessageBox]::Show("$missingMsg`n`n$guideMsg", (T "app_title"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Set-ThemeColors {
  if ($settings.theme -eq "dark") {
    $script:theme = @{
      Back = [System.Drawing.Color]::FromArgb(30, 32, 36)
      Card = [System.Drawing.Color]::FromArgb(40, 43, 48)
      Fore = [System.Drawing.Color]::FromArgb(236, 239, 241)
      Muted = [System.Drawing.Color]::FromArgb(170, 180, 190)
      InputBack = [System.Drawing.Color]::FromArgb(50, 54, 60)
      Accent = [System.Drawing.Color]::FromArgb(66, 165, 245)
    }
  }
  else {
    $script:theme = @{
      Back = [System.Drawing.Color]::FromArgb(245, 247, 250)
      Card = [System.Drawing.Color]::FromArgb(255, 255, 255)
      Fore = [System.Drawing.Color]::FromArgb(33, 37, 41)
      Muted = [System.Drawing.Color]::FromArgb(96, 106, 116)
      InputBack = [System.Drawing.Color]::FromArgb(255, 255, 255)
      Accent = [System.Drawing.Color]::FromArgb(25, 118, 210)
    }
  }
}

function Apply-Theme {
  Set-ThemeColors
  $fontRegular = New-Object System.Drawing.Font("Segoe UI", 10)
  $fontTitle = New-Object System.Drawing.Font("Segoe UI Semibold", 11)

  $form.BackColor = $theme.Back
  $form.ForeColor = $theme.Fore
  foreach ($p in @($topPanel, $statusPanel, $contentPanel)) { $p.BackColor = $theme.Card }
  foreach ($ctrl in @($lblTopTitle, $lblLang, $lblTheme, $lblProfile, $lblProfileName, $lblStatusTitle, $lblEndpointTitle, $chkMonitor, $lblPairEndpoint, $lblPairCode, $lblConnectEndpoint, $lblControlEndpoint, $lblBitrate, $lblFps, $lblMaxSize, $lblMonitorInt, $lblAbout)) {
    $ctrl.ForeColor = $theme.Fore
    $ctrl.Font = $fontRegular
  }
  foreach ($btn in @($btnSaveProfile, $btnDeleteProfile, $btnPair, $btnConnect, $btnControl, $btnSaveSettings, $btnClearLogs, $btnOpenLogs)) {
    $btn.BackColor = $theme.Accent
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.Font = $fontRegular
  }
  foreach ($input in @($cmbLang, $cmbTheme, $cmbProfile, $txtProfileName, $txtPairEndpoint, $txtPairCode, $txtConnectEndpoint, $txtControlEndpoint, $txtBitrate, $numFps, $numMaxSize, $numMonitorInterval, $txtLog)) {
    $input.BackColor = $theme.InputBack
    $input.ForeColor = $theme.Fore
    $input.Font = $fontRegular
  }
  $lblTopTitle.Font = $fontTitle
  $lblTopTitle.ForeColor = $theme.Accent
  $lblStatusValue.Font = $fontTitle
  $lblEndpointValue.ForeColor = $theme.Muted
  $lblAbout.ForeColor = $theme.Muted
  $tabs.BackColor = $theme.Card
  $tabs.ForeColor = $theme.Fore
}

function Refresh-LocalizedText {
  $form.Text = T "app_title"
  $lblTopTitle.Text = T "top_title"
  $lblLang.Text = T "language"
  $lblTheme.Text = T "theme"
  $lblProfile.Text = T "profile"
  $lblProfileName.Text = T "profile_name"
  $btnSaveProfile.Text = T "save_profile"
  $btnDeleteProfile.Text = T "delete_profile"
  $lblStatusTitle.Text = T "status"
  $lblEndpointTitle.Text = T "endpoint"
  $chkMonitor.Text = T "monitor"
  $tabPair.Text = T "tab_pair"
  $tabControl.Text = T "tab_control"
  $tabSettings.Text = T "tab_settings"
  $tabLogs.Text = T "tab_logs"
  $tabAbout.Text = T "tab_about"
  $lblPairEndpoint.Text = T "pair_endpoint"
  $lblPairCode.Text = T "pair_code"
  $lblConnectEndpoint.Text = T "connect_endpoint"
  $btnPair.Text = T "btn_pair"
  $lblControlEndpoint.Text = T "connect_endpoint"
  $btnConnect.Text = T "btn_connect"
  $btnControl.Text = T "btn_control"
  $lblBitrate.Text = T "bitrate"
  $lblFps.Text = T "fps"
  $lblMaxSize.Text = T "max_size"
  $lblMonitorInt.Text = T "monitor_interval"
  $btnSaveSettings.Text = T "save_settings"
  $btnClearLogs.Text = T "clear_logs"
  $btnOpenLogs.Text = T "open_logs"
  $lblAbout.Text = T "about_text"
}

$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(1020, 700)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(940, 640)

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Location = New-Object System.Drawing.Point(16, 14)
$topPanel.Size = New-Object System.Drawing.Size(970, 90)

$lblTopTitle = New-Object System.Windows.Forms.Label
$lblTopTitle.Location = New-Object System.Drawing.Point(18, 14)
$lblTopTitle.AutoSize = $true

$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Location = New-Object System.Drawing.Point(18, 50)
$lblLang.AutoSize = $true
$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.Location = New-Object System.Drawing.Point(74, 46)
$cmbLang.Size = New-Object System.Drawing.Size(90, 28)
$cmbLang.DropDownStyle = "DropDownList"
[void]$cmbLang.Items.AddRange(@("中文", "English"))
$cmbLang.SelectedIndex = if ($settings.language -eq "en-US") { 1 } else { 0 }

$lblTheme = New-Object System.Windows.Forms.Label
$lblTheme.Location = New-Object System.Drawing.Point(180, 50)
$lblTheme.AutoSize = $true
$cmbTheme = New-Object System.Windows.Forms.ComboBox
$cmbTheme.Location = New-Object System.Drawing.Point(232, 46)
$cmbTheme.Size = New-Object System.Drawing.Size(90, 28)
$cmbTheme.DropDownStyle = "DropDownList"
[void]$cmbTheme.Items.AddRange(@("Dark", "Light"))
$cmbTheme.SelectedIndex = if ($settings.theme -eq "light") { 1 } else { 0 }

$lblProfile = New-Object System.Windows.Forms.Label
$lblProfile.Location = New-Object System.Drawing.Point(350, 50)
$lblProfile.AutoSize = $true
$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.Location = New-Object System.Drawing.Point(406, 46)
$cmbProfile.Size = New-Object System.Drawing.Size(150, 28)
$cmbProfile.DropDownStyle = "DropDownList"

$lblProfileName = New-Object System.Windows.Forms.Label
$lblProfileName.Location = New-Object System.Drawing.Point(566, 50)
$lblProfileName.AutoSize = $true
$txtProfileName = New-Object System.Windows.Forms.TextBox
$txtProfileName.Location = New-Object System.Drawing.Point(638, 46)
$txtProfileName.Size = New-Object System.Drawing.Size(118, 28)
$btnSaveProfile = New-Object System.Windows.Forms.Button
$btnSaveProfile.Location = New-Object System.Drawing.Point(764, 45)
$btnSaveProfile.Size = New-Object System.Drawing.Size(96, 30)
$btnDeleteProfile = New-Object System.Windows.Forms.Button
$btnDeleteProfile.Location = New-Object System.Drawing.Point(866, 45)
$btnDeleteProfile.Size = New-Object System.Drawing.Size(96, 30)

$topPanel.Controls.AddRange(@($lblTopTitle, $lblLang, $cmbLang, $lblTheme, $cmbTheme, $lblProfile, $cmbProfile, $lblProfileName, $txtProfileName, $btnSaveProfile, $btnDeleteProfile))

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(16, 112)
$statusPanel.Size = New-Object System.Drawing.Size(970, 60)

$lblStatusTitle = New-Object System.Windows.Forms.Label
$lblStatusTitle.Location = New-Object System.Drawing.Point(18, 20)
$lblStatusTitle.AutoSize = $true
$lblStatusValue = New-Object System.Windows.Forms.Label
$lblStatusValue.Location = New-Object System.Drawing.Point(72, 18)
$lblStatusValue.AutoSize = $true
$lblEndpointTitle = New-Object System.Windows.Forms.Label
$lblEndpointTitle.Location = New-Object System.Drawing.Point(240, 20)
$lblEndpointTitle.AutoSize = $true
$lblEndpointValue = New-Object System.Windows.Forms.Label
$lblEndpointValue.Location = New-Object System.Drawing.Point(314, 20)
$lblEndpointValue.AutoSize = $true
$chkMonitor = New-Object System.Windows.Forms.CheckBox
$chkMonitor.Location = New-Object System.Drawing.Point(730, 18)
$chkMonitor.AutoSize = $true
$chkMonitor.Checked = $true

$statusPanel.Controls.AddRange(@($lblStatusTitle, $lblStatusValue, $lblEndpointTitle, $lblEndpointValue, $chkMonitor))

$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Location = New-Object System.Drawing.Point(16, 180)
$contentPanel.Size = New-Object System.Drawing.Size(970, 470)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10)
$tabs.Size = New-Object System.Drawing.Size(950, 450)

$tabPair = New-Object System.Windows.Forms.TabPage
$tabControl = New-Object System.Windows.Forms.TabPage
$tabSettings = New-Object System.Windows.Forms.TabPage
$tabLogs = New-Object System.Windows.Forms.TabPage
$tabAbout = New-Object System.Windows.Forms.TabPage
$tabs.TabPages.AddRange(@($tabPair, $tabControl, $tabSettings, $tabLogs, $tabAbout))

$lblPairEndpoint = New-Object System.Windows.Forms.Label
$lblPairEndpoint.Location = New-Object System.Drawing.Point(30, 36)
$lblPairEndpoint.AutoSize = $true
$txtPairEndpoint = New-Object System.Windows.Forms.TextBox
$txtPairEndpoint.Location = New-Object System.Drawing.Point(250, 32)
$txtPairEndpoint.Size = New-Object System.Drawing.Size(320, 28)
$lblPairCode = New-Object System.Windows.Forms.Label
$lblPairCode.Location = New-Object System.Drawing.Point(30, 78)
$lblPairCode.AutoSize = $true
$txtPairCode = New-Object System.Windows.Forms.TextBox
$txtPairCode.Location = New-Object System.Drawing.Point(250, 74)
$txtPairCode.Size = New-Object System.Drawing.Size(320, 28)
$lblConnectEndpoint = New-Object System.Windows.Forms.Label
$lblConnectEndpoint.Location = New-Object System.Drawing.Point(30, 120)
$lblConnectEndpoint.AutoSize = $true
$txtConnectEndpoint = New-Object System.Windows.Forms.TextBox
$txtConnectEndpoint.Location = New-Object System.Drawing.Point(250, 116)
$txtConnectEndpoint.Size = New-Object System.Drawing.Size(320, 28)
$btnPair = New-Object System.Windows.Forms.Button
$btnPair.Location = New-Object System.Drawing.Point(590, 74)
$btnPair.Size = New-Object System.Drawing.Size(220, 40)
$tabPair.Controls.AddRange(@($lblPairEndpoint, $txtPairEndpoint, $lblPairCode, $txtPairCode, $lblConnectEndpoint, $txtConnectEndpoint, $btnPair))

$lblControlEndpoint = New-Object System.Windows.Forms.Label
$lblControlEndpoint.Location = New-Object System.Drawing.Point(30, 38)
$lblControlEndpoint.AutoSize = $true
$txtControlEndpoint = New-Object System.Windows.Forms.TextBox
$txtControlEndpoint.Location = New-Object System.Drawing.Point(250, 34)
$txtControlEndpoint.Size = New-Object System.Drawing.Size(320, 28)
$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Location = New-Object System.Drawing.Point(590, 32)
$btnConnect.Size = New-Object System.Drawing.Size(220, 40)
$btnControl = New-Object System.Windows.Forms.Button
$btnControl.Location = New-Object System.Drawing.Point(590, 82)
$btnControl.Size = New-Object System.Drawing.Size(220, 40)
$tabControl.Controls.AddRange(@($lblControlEndpoint, $txtControlEndpoint, $btnConnect, $btnControl))

$lblBitrate = New-Object System.Windows.Forms.Label
$lblBitrate.Location = New-Object System.Drawing.Point(30, 36)
$lblBitrate.AutoSize = $true
$txtBitrate = New-Object System.Windows.Forms.TextBox
$txtBitrate.Location = New-Object System.Drawing.Point(250, 32)
$txtBitrate.Size = New-Object System.Drawing.Size(120, 28)
$lblFps = New-Object System.Windows.Forms.Label
$lblFps.Location = New-Object System.Drawing.Point(30, 76)
$lblFps.AutoSize = $true
$numFps = New-Object System.Windows.Forms.NumericUpDown
$numFps.Location = New-Object System.Drawing.Point(250, 72)
$numFps.Size = New-Object System.Drawing.Size(120, 28)
$numFps.Minimum = 5
$numFps.Maximum = 120
$lblMaxSize = New-Object System.Windows.Forms.Label
$lblMaxSize.Location = New-Object System.Drawing.Point(30, 116)
$lblMaxSize.AutoSize = $true
$numMaxSize = New-Object System.Windows.Forms.NumericUpDown
$numMaxSize.Location = New-Object System.Drawing.Point(250, 112)
$numMaxSize.Size = New-Object System.Drawing.Size(120, 28)
$numMaxSize.Minimum = 640
$numMaxSize.Maximum = 2160
$lblMonitorInt = New-Object System.Windows.Forms.Label
$lblMonitorInt.Location = New-Object System.Drawing.Point(30, 156)
$lblMonitorInt.AutoSize = $true
$numMonitorInterval = New-Object System.Windows.Forms.NumericUpDown
$numMonitorInterval.Location = New-Object System.Drawing.Point(250, 152)
$numMonitorInterval.Size = New-Object System.Drawing.Size(120, 28)
$numMonitorInterval.Minimum = 3
$numMonitorInterval.Maximum = 120
$btnSaveSettings = New-Object System.Windows.Forms.Button
$btnSaveSettings.Location = New-Object System.Drawing.Point(250, 202)
$btnSaveSettings.Size = New-Object System.Drawing.Size(180, 38)
$tabSettings.Controls.AddRange(@($lblBitrate, $txtBitrate, $lblFps, $numFps, $lblMaxSize, $numMaxSize, $lblMonitorInt, $numMonitorInterval, $btnSaveSettings))

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 20)
$txtLog.Size = New-Object System.Drawing.Size(890, 320)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$btnClearLogs = New-Object System.Windows.Forms.Button
$btnClearLogs.Location = New-Object System.Drawing.Point(20, 350)
$btnClearLogs.Size = New-Object System.Drawing.Size(150, 34)
$btnOpenLogs = New-Object System.Windows.Forms.Button
$btnOpenLogs.Location = New-Object System.Drawing.Point(180, 350)
$btnOpenLogs.Size = New-Object System.Drawing.Size(190, 34)
$tabLogs.Controls.AddRange(@($txtLog, $btnClearLogs, $btnOpenLogs))

$lblAbout = New-Object System.Windows.Forms.Label
$lblAbout.Location = New-Object System.Drawing.Point(30, 26)
$lblAbout.Size = New-Object System.Drawing.Size(880, 200)
$tabAbout.Controls.Add($lblAbout)

$contentPanel.Controls.Add($tabs)
$form.Controls.AddRange(@($topPanel, $statusPanel, $contentPanel))

Refresh-ProfileCombo -PreferredName $profiles.defaultProfile
$selectedProfile = [string]$cmbProfile.SelectedItem
$txtProfileName.Text = $selectedProfile
$p = Find-ProfileByName -Name $selectedProfile
if ($p) {
  $txtConnectEndpoint.Text = $p.endpoint
  $txtControlEndpoint.Text = $p.endpoint
}

$txtBitrate.Text = [string]$settings.bitrate
$numFps.Value = [int]$settings.maxFps
$numMaxSize.Value = [int]$settings.maxSize
$numMonitorInterval.Value = [int]$settings.monitorIntervalSec

Refresh-LocalizedText
Apply-Theme

$cmbLang.Add_SelectedIndexChanged({
    $settings.language = if ($cmbLang.SelectedIndex -eq 1) { "en-US" } else { "zh-CN" }
    Save-Settings
    Refresh-LocalizedText
    Set-UiStatus -Status "disconnected" -Message ""
  })

$cmbTheme.Add_SelectedIndexChanged({
    $settings.theme = if ($cmbTheme.SelectedIndex -eq 1) { "light" } else { "dark" }
    Save-Settings
    Apply-Theme
    Append-Log -Message "Theme switched: $($settings.theme)"
  })

$cmbProfile.Add_SelectedIndexChanged({
    $name = [string]$cmbProfile.SelectedItem
    $txtProfileName.Text = $name
    $p2 = Find-ProfileByName -Name $name
    if ($p2) {
      $txtConnectEndpoint.Text = $p2.endpoint
      $txtControlEndpoint.Text = $p2.endpoint
      $lblEndpointValue.Text = $p2.endpoint
      Append-Log -Message "Loaded profile: $name"
    }
  })

$btnSaveProfile.Add_Click({
    $name = $txtProfileName.Text.Trim()
    if (-not $name) { $name = "default" }
    $endpoint = $txtConnectEndpoint.Text.Trim()
    $existing = Find-ProfileByName -Name $name
    if ($existing) {
      $existing.endpoint = $endpoint
    }
    else {
      $profiles.items += [pscustomobject]@{ name = $name; endpoint = $endpoint }
    }
    $profiles.defaultProfile = $name
    Save-Profiles
    Refresh-ProfileCombo -PreferredName $name
    Append-Log -Message "$(T "msg_profile_saved"): $name"
  })

$btnDeleteProfile.Add_Click({
    $name = [string]$cmbProfile.SelectedItem
    if (-not $name) { return }
    if ($name -eq "default") {
      Append-Log -Message (T "msg_cannot_delete_default") -Level "WARN"
      return
    }
    $profiles.items = @($profiles.items | Where-Object { $_.name -ne $name })
    if ($profiles.items.Count -eq 0) {
      $profiles.items = @([pscustomobject]@{ name = "default"; endpoint = "" })
    }
    $profiles.defaultProfile = [string]$profiles.items[0].name
    Save-Profiles
    Refresh-ProfileCombo -PreferredName $profiles.defaultProfile
    Append-Log -Message "$(T "msg_profile_deleted"): $name"
  })

$btnPair.Add_Click({
    try {
      $pairEndpoint = $txtPairEndpoint.Text.Trim()
      $pairCode = $txtPairCode.Text.Trim()
      $connectEndpoint = $txtConnectEndpoint.Text.Trim()
      if (-not $pairEndpoint -or -not $pairCode) {
        [System.Windows.Forms.MessageBox]::Show((T "msg_input_required"), (T "app_title")) | Out-Null
        return
      }
      Set-UiStatus -Status "reconnecting" -Message (T "msg_pairing")
      $result = Invoke-DevicePairing -PairEndpoint $pairEndpoint -PairCode $pairCode -ConnectEndpoint $connectEndpoint
      if (-not $result.Success) {
        Set-UiStatus -Status "pairing-required" -Message $result.Message
        return
      }
      $txtConnectEndpoint.Text = $result.ConnectEndpoint
      $txtControlEndpoint.Text = $result.ConnectEndpoint
      Set-UiStatus -Status "connected" -Message $result.Message
    }
    catch {
      Set-UiStatus -Status "pairing-required" -Message $_.Exception.Message
    }
  })

$btnConnect.Add_Click({
    try {
      Set-UiStatus -Status "reconnecting" -Message (T "msg_connecting")
      $result = Invoke-DeviceConnection -PreferredEndpoint $txtControlEndpoint.Text.Trim()
      if ($result.Success) {
        $txtControlEndpoint.Text = $result.Endpoint
        $txtConnectEndpoint.Text = $result.Endpoint
        Set-UiStatus -Status "connected" -Message $result.Message
      }
      else {
        Set-UiStatus -Status "pairing-required" -Message $result.Message
      }
    }
    catch {
      Set-UiStatus -Status "pairing-required" -Message $_.Exception.Message
    }
  })

$btnControl.Add_Click({
    try {
      $runtimePath = Join-Path $appRoot "runtime\scrcpy"
      if (-not (Test-Path $runtimePath)) {
        Show-RuntimeRepairHint
        Set-UiStatus -Status "disconnected" -Message (T "msg_runtime_missing")
        return
      }

      $ensure = Invoke-DeviceConnection -PreferredEndpoint $txtControlEndpoint.Text.Trim()
      if (-not $ensure.Success) {
        Set-UiStatus -Status "pairing-required" -Message $ensure.Message
        return
      }
      $txtControlEndpoint.Text = $ensure.Endpoint
      $txtConnectEndpoint.Text = $ensure.Endpoint
      $start = Start-ScrcpyControl -Endpoint $ensure.Endpoint -Bitrate $settings.bitrate -MaxFps $settings.maxFps -MaxSize $settings.maxSize
      if (-not $start.Success) {
        Set-UiStatus -Status "disconnected" -Message $start.Message
        if ($start.Message -like "*runtime\scrcpy*" -or $start.Message -like "*scrcpy.exe not found*") {
          Show-RuntimeRepairHint
        }
        return
      }
      Set-UiStatus -Status "connected" -Message $start.Message
    }
    catch {
      if ($_.Exception.Message -like "*runtime\scrcpy*" -or $_.Exception.Message -like "*scrcpy.exe not found*") {
        Show-RuntimeRepairHint
        Set-UiStatus -Status "disconnected" -Message $_.Exception.Message
      }
      else {
        Set-UiStatus -Status "pairing-required" -Message $_.Exception.Message
      }
    }
  })

$btnSaveSettings.Add_Click({
    $settings.bitrate = $txtBitrate.Text.Trim()
    $settings.maxFps = [int]$numFps.Value
    $settings.maxSize = [int]$numMaxSize.Value
    $settings.monitorIntervalSec = [int]$numMonitorInterval.Value
    Save-Settings
    $timer.Interval = [int]$settings.monitorIntervalSec * 1000
    Append-Log -Message (T "msg_settings_saved")
  })

$btnClearLogs.Add_Click({ $txtLog.Clear() })
$btnOpenLogs.Add_Click({ Start-Process explorer.exe $paths.Logs | Out-Null })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [int]$settings.monitorIntervalSec * 1000
$timer.Add_Tick({
    if (-not $chkMonitor.Checked) { return }
    $state = Get-ConnectionStatus -Endpoint $txtControlEndpoint.Text.Trim()
    if ($state.Endpoint) {
      $txtControlEndpoint.Text = $state.Endpoint
      $txtConnectEndpoint.Text = $state.Endpoint
    }
    if ($state.Status -eq "connected") {
      $lblStatusValue.Text = Get-LocalizedState -Raw "connected"
      $lblStatusValue.ForeColor = [System.Drawing.Color]::FromArgb(67, 160, 71)
      $lblEndpointValue.Text = $txtControlEndpoint.Text.Trim()
    }
    else {
      Set-UiStatus -Status $state.Status -Message $state.Message
    }
  })
$timer.Start()

Append-Log -Message "GUI started."
Set-UiStatus -Status "disconnected" -Message ""
[void]$form.ShowDialog()
