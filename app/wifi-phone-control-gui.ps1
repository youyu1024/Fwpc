$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

function Resolve-AppRoot {
  $candidates = @()
  if ($PSScriptRoot) { $candidates += (Join-Path $PSScriptRoot '..') }
  $candidates += (Split-Path -Parent ([Environment]::GetCommandLineArgs()[0]))
  $candidates += (Get-Location).Path
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path (Join-Path $candidate 'core\common.psm1'))) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw 'Cannot locate the app folder. Extract the full release ZIP.'
}

$appRoot = Resolve-AppRoot
Import-Module (Join-Path $appRoot 'core\common.psm1')
$paths = Get-AppPaths
$defaults = [pscustomobject]@{
  monitorIntervalSec = 8; bitrate = '6M'; maxFps = 30; maxSize = 1280; language = 'zh-CN'; theme = 'light'; autoReconnect = $true
  turnScreenOff = $false; stayAwake = $true; alwaysOnTop = $false; fullscreen = $false; showTouches = $false; noAudio = $false
}
$settings = Read-JsonFile -Path $paths.SettingsFile -DefaultValue $defaults.PSObject.Copy()
foreach ($property in $defaults.PSObject.Properties) {
  if (-not $settings.PSObject.Properties[$property.Name]) {
    $settings | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
  }
}
if ($settings.language -notin @('zh-CN', 'en-US')) { $settings.language = 'zh-CN' }
if ($settings.theme -notin @('light', 'dark')) { $settings.theme = 'light' }
if ($settings.bitrate -notmatch '^[1-9][0-9]{0,8}[KM]?$') { $settings.bitrate = $defaults.bitrate }

$profiles = Read-JsonFile -Path $paths.ProfileFile -DefaultValue ([pscustomobject]@{ defaultProfile = 'default'; items = @() })
if (-not $profiles.items) { $profiles.items = @([pscustomobject]@{ name = 'default'; endpoint = '' }) }
foreach ($profile in $profiles.items) {
  foreach ($name in @('identity', 'hardwareSerial', 'model', 'pendingIdentity')) {
    if (-not $profile.PSObject.Properties[$name]) { $profile | Add-Member -NotePropertyName $name -NotePropertyValue '' }
  }
  if (-not $profile.PSObject.Properties['pendingPair']) {
    $profile | Add-Member -NotePropertyName pendingPair -NotePropertyValue $false
  }
}
# Older versions also saved a global last endpoint. Offer it in the manual address field only.
$legacyAddress = ''
$defaultProfile = $profiles.items | Where-Object { $_.name -eq 'default' } | Select-Object -First 1
if ($defaultProfile -and -not $defaultProfile.endpoint -and (Test-Path -LiteralPath $paths.EndpointFile)) {
  $legacyAddress = [string](Get-Content -LiteralPath $paths.EndpointFile -TotalCount 1)
}

$strings = @{
  title = @('Android 手机控制中心', 'Android Phone Control')
  usbDescription = @('通过数据线投屏和控制。首次连接需在手机上允许 USB 调试。', 'Mirror and control over a data cable. Allow USB debugging on the phone on first use.')
  wifiDescription = @('使用手机上的六位配对码连接局域网中的 Android 设备。', 'Connect an Android phone on your local network with its six-digit pairing code.')
  controls = @('控制与显示', 'Control and display')
  optionHint = @('这些选项在下次启动控制时生效。', 'These options apply to the next control session.')
  shortcuts = @('手机快捷键', 'Phone shortcuts')
  shortcutHint = @('开始控制后，快捷键会发送给当前手机。', 'Start a control session to use shortcuts on the selected phone.')
  turnScreenOff = @('灭屏控制', 'Turn phone screen off')
  stayAwake = @('保持唤醒', 'Stay awake')
  alwaysOnTop = @('窗口置顶', 'Always on top')
  fullscreen = @('全屏启动', 'Start fullscreen')
  showTouches = @('显示触摸点', 'Show touches')
  noAudio = @('关闭音频', 'Mute phone audio')
  storedProfile = @('设备配置', 'Device profile')
  phoneBack = @('返回', 'Back')
  phoneHome = @('主页', 'Home')
  phoneRecents = @('多任务', 'Recents')
  phonePower = @('电源', 'Power')
  volumeUp = @('音量 +', 'Volume +')
  volumeDown = @('音量 −', 'Volume −')
  screenshot = @('截屏', 'Screenshot')
  screenshotSaved = @('截图已保存。', 'Screenshot saved.')
  actionFailed = @('手机操作失败。请查看诊断。', 'The phone action failed. See Diagnostics.')
  home = @('控制中心', 'Control center')
  preferences = @('偏好设置', 'Settings')
  profiles = @('设备管理', 'Devices')
  diagnostics = @('诊断', 'Diagnostics')
  noDevice = @('尚未连接手机', 'No phone connected')
  wifi = @('无线连接', 'Wi-Fi')
  usb = @('USB 直连', 'USB direct')
  usbConnect = @('USB 一键直连', 'Start USB control')
  usbIdle = @('连接手机后点击下方按钮。', 'Plug in your phone, then select the button below.')
  wifiIdle = @('尚未连接无线设备', 'No Wi-Fi phone connected')
  usbOther = @('选择其他 USB 手机', 'Choose another USB phone')
  add = @('连接手机', 'Connect phone')
  resume = @('继续连接', 'Resume connection')
  retry = @('重试连接', 'Retry connection')
  pairAgain = @('配对新设备', 'Pair another device')
  start = @('开始控制', 'Start control')
  stop = @('停止控制', 'Stop control')
  cancel = @('取消', 'Cancel')
  back = @('返回设备页', 'Back to device')
  manual = @('手动输入连接地址', 'Enter connection address')
  phoneStep = @('1. 在手机上打开无线调试', '1. Open wireless debugging on your phone')
  phoneGuide = @('进入「设置 → 开发者选项 → 无线调试」，保持手机和电脑在可互通的局域网。', 'Open Settings → Developer options → Wireless debugging. Keep both devices on a network that allows them to communicate.')
  developerGuide = @('找不到开发者选项？在「关于手机」连续点按版本号，部分机型的入口名称不同。', 'Missing Developer options? Tap Build number repeatedly in About phone. The label varies by device.')
  codeStep = @('2. 输入手机上的配对信息', '2. Enter the pairing details')
  codeGuide = @('在无线调试中选择「使用配对码配对设备」，保持该弹窗打开。', 'Select Pair device with pairing code in Wireless debugging and leave that dialog open.')
  pairAddress = @('配对弹窗中的 IP 地址和端口', 'IP address and port in the pairing dialog')
  pairCode = @('六位配对码', 'Six-digit pairing code')
  pair = @('配对并连接', 'Pair and connect')
  addressGuide = @('返回手机的无线调试主页面，填写该页显示的 IP 地址和端口。', 'Return to the main Wireless debugging page and enter the IP address and port shown there.')
  addressLabel = @('无线调试主页面的连接地址', 'Connection address on the Wireless debugging page')
  chooseUsb = @('选择要控制的 USB 手机', 'Choose a USB phone to control')
  usbGuide = @('使用支持数据传输的线缆，开启 USB 调试，并在手机上确认授权。', 'Use a data cable, enable USB debugging, then allow this computer on the phone.')
  profile = @('无线设备配置', 'Wi-Fi profile')
  profileName = @('新配置名称', 'New profile name')
  addProfile = @('新建配置', 'New profile')
  deleteProfile = @('删除当前配置', 'Delete current profile')
  language = @('语言', 'Language')
  theme = @('主题', 'Theme')
  autoReconnect = @('自动重连已知无线设备', 'Automatically reconnect known Wi-Fi devices')
  interval = @('重连检查间隔（秒）', 'Reconnect check interval (seconds)')
  bitrate = @('视频码率', 'Video bitrate')
  fps = @('最大帧率', 'Maximum frame rate')
  size = @('最大画面尺寸', 'Maximum video size')
  save = @('保存设置', 'Save settings')
  clearLogs = @('清空面板', 'Clear panel')
  openLogs = @('打开日志文件夹', 'Open log folder')
  saved = @('设置已保存。', 'Settings saved.')
  badBitrate = @('请输入有效的视频码率，例如 6M。', 'Enter a valid bitrate, such as 6M.')
  deleteQuestion = @('删除当前无线配置？手机上的授权可以在系统设置中管理。', 'Delete this Wi-Fi profile? Manage the phone authorization in Android settings.')
  disconnected = @('尚未连接手机。', 'No phone connected.')
  pairing = @('正在配对，请保持手机配对弹窗打开。', 'Pairing. Leave the phone pairing dialog open.')
  discovering = @('已配对，正在查找手机。', 'Paired. Looking for the phone.')
  connecting = @('正在确认所选手机的连接。', 'Checking the selected phone.')
  'address-needed' = @('未找到手机的连接地址。可从手机的无线调试主页面手动填写。', 'No connection address found. Enter it from the main Wireless debugging page.')
  'paired-address-needed' = @('已配对。请从手机的无线调试主页面填写连接地址。', 'Paired. Enter the connection address shown on the main Wireless debugging page.')
  'invalid-address' = @('请输入有效的 IP 地址和端口，例如 192.168.1.8:37001。', 'Enter a valid IP address and port, for example 192.168.1.8:37001.')
  'invalid-code' = @('请输入手机当前显示的六位数字。', 'Enter the six digits displayed on your phone.')
  'pair-failed' = @('配对失败。请在手机上获取新的六位码后重试。', 'Pairing failed. Get a fresh six-digit code on the phone and retry.')
  'pair-unreachable' = @('配对地址不可达。请确认配对弹窗仍打开，并检查设备间网络连接。', 'Cannot reach the pairing address. Keep the dialog open and check the network between devices.')
  'network-unreachable' = @('无法连接这个地址。请核对手机端口，检查访客网络或设备隔离。', 'Cannot connect to this address. Check the phone port and any guest network or client isolation.')
  'device-mismatch' = @('这个地址对应的设备与已保存的手机不同，请核对目标。', 'This address points to a different device. Verify the target phone.')
  'pairing-required' = @('手机未授权这台电脑。请在手机上重新配对。', 'The phone has not authorized this computer. Pair it again from the phone.')
  connected = @('已连接，可开始控制。', 'Connected and ready to control.')
  'usb-wait' = @('正在检测 USB。首次连接请解锁手机并允许 USB 调试。', 'Checking USB. For first use, unlock the phone and allow USB debugging.')
  'usb-missing' = @('未检测到 USB 手机。请确认数据线和 USB 调试，然后重试。', 'No USB phone detected. Check the data cable and USB debugging, then retry.')
  'usb-disconnected' = @('USB 已断开。请重新插入原手机，或选择另一台。', 'USB disconnected. Reconnect the same phone or choose another.')
  'usb-authorization' = @('等待手机授权超时。请允许 USB 调试后重试。', 'USB authorization timed out. Allow USB debugging and retry.')
  'usb-offline' = @('已检测到 USB 手机，但设备未就绪。请解锁手机或重新插线。', 'The USB phone is not ready. Unlock it or reconnect the cable.')
  'choose-usb' = @('检测到多台 USB 手机。请选择需要控制的一台。', 'Multiple USB phones found. Select the one you want to control.')
  launching = @('正在启动控制。', 'Starting control.')
  controlling = @('正在控制手机。', 'Controlling your phone.')
  'control-failed' = @('控制窗口启动失败。请检查设备连接，或查看诊断。', 'Control could not start. Check the device or open Diagnostics.')
  cancelled = @('已取消，可以重试。', 'Cancelled. You can try again.')
  timeout = @('连接请求超时。请检查设备与网络后重试。', 'The request timed out. Check the phone and network, then retry.')
  failure = @('操作失败。请在诊断页查看详情。', 'The operation failed. See Diagnostics for details.')
  'runtime-missing' = @('发布包不完整。请重新下载并完整解压 ZIP。', 'The release is incomplete. Download and extract the entire ZIP again.')
}

function Text-For([string]$Key) {
  if (-not $strings.ContainsKey($Key)) { return $Key }
  return $strings[$Key][[int]($settings.language -eq 'en-US')]
}

$form = New-Object Windows.Forms.Form
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(890, 654)
$form.MinimumSize = New-Object Drawing.Size(680, 510)
$form.AutoScaleMode = 'Dpi'
$uiFontName = 'Microsoft YaHei UI'
$form.Font = New-Object Drawing.Font($uiFontName, 10)
$form.KeyPreview = $true

$palette = @{}
$captions = New-Object 'System.Collections.Generic.List[object]'
$surfaces = New-Object 'System.Collections.Generic.List[object]'
$buttons = New-Object 'System.Collections.Generic.List[object]'
$inputs = New-Object 'System.Collections.Generic.List[object]'
$headFont = New-Object Drawing.Font($uiFontName, 16, [Drawing.FontStyle]::Bold)
$sectionFont = New-Object Drawing.Font($uiFontName, 11, [Drawing.FontStyle]::Bold)

function Set-Caption($Control, [string]$Key) {
  $Control.Text = Text-For $Key
  $captions.Add(@{ Control = $Control; Key = $Key })
}

function New-Stack([int]$Padding = 0) {
  $panel = New-Object Windows.Forms.TableLayoutPanel
  $panel.AutoSize = $true
  $panel.AutoSizeMode = 'GrowAndShrink'
  $panel.Dock = 'Top'
  $panel.ColumnCount = 1
  $panel.Padding = New-Object Windows.Forms.Padding($Padding)
  $panel.GrowStyle = 'AddRows'
  $panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
  return $panel
}

function Add-Row($Stack, $Control, [int]$Gap = 12) {
  $Control.Margin = New-Object Windows.Forms.Padding(0, 0, 0, $Gap)
  $rowIndex = $Stack.RowCount
  $Stack.RowCount = $rowIndex + 1
  [void]$Stack.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
  $Stack.Controls.Add($Control, 0, $rowIndex)
}

function New-Label([string]$Key, [string]$Style = 'body') {
  $label = New-Object Windows.Forms.Label
  $label.AutoSize = $true
  if ($Style -eq 'heading') { $label.Font = $headFont }
  if ($Style -eq 'section') { $label.Font = $sectionFont }
  if ($Key) { Set-Caption $label $Key }
  if ($Style -ne 'heading') {
    $label.MaximumSize = New-Object Drawing.Size(490, 0)
  }
  $label.Tag = $Style
  return $label
}

function New-Button([string]$Key, [bool]$Primary = $false) {
  $button = New-Object Windows.Forms.Button
  $button.AutoSize = $true
  $button.AutoSizeMode = 'GrowAndShrink'
  $button.MinimumSize = New-Object Drawing.Size(116, 38)
  $button.Padding = New-Object Windows.Forms.Padding(12, 4, 12, 4)
  $button.FlatStyle = 'Flat'
  $button.UseVisualStyleBackColor = $false
  $button.Tag = $Primary
  if ($Key) { Set-Caption $button $Key }
  $buttons.Add($button)
  return $button
}

function New-ButtonRow([object[]]$Controls) {
  $row = New-Object Windows.Forms.FlowLayoutPanel
  $row.AutoSize = $true
  $row.AutoSizeMode = 'GrowAndShrink'
  $row.Dock = 'Top'
  $row.Size = New-Object Drawing.Size(560, 1)
  $row.WrapContents = $true
  foreach ($control in $Controls) {
    $control.Margin = New-Object Windows.Forms.Padding(0, 0, 9, 5)
    $row.Controls.Add($control)
  }
  return $row
}

function New-Input([int]$Width, [string]$LabelKey) {
  $box = New-Object Windows.Forms.TextBox
  $box.Width = $Width
  if ($LabelKey) { $box.AccessibleName = Text-For $LabelKey }
  $inputs.Add($box)
  return $box
}

function New-Combo {
  $box = New-Object Windows.Forms.ComboBox
  $box.DropDownStyle = 'DropDownList'
  $box.Width = 260
  $inputs.Add($box)
  return $box
}

function New-Number([int]$Min, [int]$Max, [int]$Value) {
  $box = New-Object Windows.Forms.NumericUpDown
  $box.Minimum = $Min
  $box.Maximum = $Max
  $box.Value = [Math]::Max($Min, [Math]::Min($Max, $Value))
  $box.Width = 110
  $inputs.Add($box)
  return $box
}

function New-Page([string]$Key) {
  $page = New-Object Windows.Forms.TabPage
  Set-Caption $page $Key
  $page.AutoScroll = $true
  $surfaces.Add($page)
  return $page
}

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Padding = New-Object Drawing.Point(13, 6)
$pageHome = New-Page 'home'
$pageProfiles = New-Page 'profiles'
$pageSettings = New-Page 'preferences'
$pageLogs = New-Page 'diagnostics'
$tabs.TabPages.AddRange(@($pageHome, $pageProfiles, $pageSettings, $pageLogs))
$form.Controls.Add($tabs)


$homeLayout = New-Stack 24
$pageHome.Controls.Add($homeLayout)
$masthead = New-Stack 17
$mastheadTitle = New-Label 'title' 'heading'
Add-Row $masthead $mastheadTitle 0
$form.Controls.Add($masthead)

$card = New-Stack 18
$surfaces.Add($card)
$deviceName = New-Label '' 'section'
$deviceMode = New-Label '' 'body'
$statusLabel = New-Label '' 'body'
$btnPrimary = New-Button '' $true
$btnUsb = New-Button '' $true
$btnCancel = New-Button 'cancel'
$btnManual = New-Button 'manual'
$btnNewPair = New-Button 'pairAgain'
$btnUsbOther = New-Button 'usbOther'
$wifiDescription = New-Label 'wifiDescription'
$wifiDescription.MaximumSize = New-Object Drawing.Size(265, 0)
$wifiTitle = New-Label 'wifi' 'section'
Add-Row $card $wifiTitle 5
Add-Row $card $wifiDescription 12
Add-Row $card $deviceName 5
Add-Row $card $deviceMode 5
Add-Row $card $statusLabel 11
Add-Row $card (New-ButtonRow @($btnPrimary, $btnCancel)) 0
Add-Row $card (New-ButtonRow @($btnManual, $btnNewPair)) 0

$usbCard = New-Stack 17
$surfaces.Add($usbCard)
$usbTitle = New-Label 'usb' 'section'
$usbDescription = New-Label 'usbDescription'
$usbDescription.MaximumSize = New-Object Drawing.Size(265, 0)
$usbModel = New-Label '' 'body'
$usbStatus = New-Label '' 'body'
Add-Row $usbCard $usbTitle 5
Add-Row $usbCard $usbDescription 12
Add-Row $usbCard $usbModel 5
Add-Row $usbCard $usbStatus 11
Add-Row $usbCard (New-ButtonRow @($btnUsb, $btnUsbOther)) 0
$btnUsbCancel = New-Button 'cancel'
Add-Row $usbCard $btnUsbCancel 0

function New-SplitCards($Left, $Right) {
  $columns = New-Object Windows.Forms.TableLayoutPanel
  $columns.AutoSize = $true
  $columns.AutoSizeMode = 'GrowAndShrink'
  $columns.Dock = 'Fill'
  $columns.ColumnCount = 2
  $columns.RowCount = 1
  [void]$columns.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 50)))
  [void]$columns.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 50)))
  [void]$columns.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
  $Left.Dock = 'Fill'
  $Right.Dock = 'Fill'
  $Left.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 0)
  $Right.Margin = New-Object Windows.Forms.Padding(0)
  $columns.Controls.Add($Left, 0, 0)
  $columns.Controls.Add($Right, 1, 0)
  return $columns
}

$homeCards = New-SplitCards $usbCard $card
Add-Row $homeLayout $homeCards 12

$optionsCard = New-Stack 17
$surfaces.Add($optionsCard)
$optionsTitle = New-Label 'controls' 'section'
Add-Row $optionsCard $optionsTitle 5
Add-Row $optionsCard (New-Label 'optionHint') 10
$optionChecks = [ordered]@{}
foreach ($key in @('turnScreenOff', 'stayAwake', 'alwaysOnTop', 'fullscreen', 'showTouches', 'noAudio')) {
  $checkbox = New-Object Windows.Forms.CheckBox
  $checkbox.AutoSize = $true
  $checkbox.Checked = [bool]$settings.$key
  Set-Caption $checkbox $key
  $optionChecks[$key] = $checkbox
}
Add-Row $optionsCard (New-ButtonRow @($optionChecks.Values)) 0
$shortcutCard = New-Stack 17
$surfaces.Add($shortcutCard)
$shortcutTitle = New-Label 'shortcuts' 'section'
Add-Row $shortcutCard $shortcutTitle 5
$shortcutFeedback = New-Label ''
Add-Row $shortcutCard $shortcutFeedback 10
$shortcutButtons = @{}
$shortcutKeys = [ordered]@{ phoneBack = 4; phoneHome = 3; phoneRecents = 187; phonePower = 26; volumeUp = 24; volumeDown = 25; screenshot = -1 }
foreach ($key in $shortcutKeys.Keys) {
  $button = New-Button $key
  $button.MinimumSize = New-Object Drawing.Size(67, 35)
  $button.Add_Paint({
      param($sender, $eventArgs)
      if ($sender.Enabled -or $settings.theme -ne 'dark') { return }
      $rectangle = $sender.ClientRectangle
      $eventArgs.Graphics.Clear($palette.Card)
      $pen = New-Object Drawing.Pen($palette.Border)
      try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $rectangle.Width - 1, $rectangle.Height - 1) }
      finally { $pen.Dispose() }
      [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $sender.Text, $sender.Font, $rectangle,
        $palette.Muted, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine')
    })
  $shortcutButtons[$key] = $button
}
Add-Row $shortcutCard (New-ButtonRow @($shortcutKeys.Keys | ForEach-Object { $shortcutButtons[$_] })) 0
$quickCards = New-SplitCards $optionsCard $shortcutCard
Add-Row $homeLayout $quickCards 0

$pairPanel = New-Stack 18
$surfaces.Add($pairPanel)
Add-Row $pairPanel (New-Label 'phoneStep' 'section') 5
Add-Row $pairPanel (New-Label 'phoneGuide') 6
Add-Row $pairPanel (New-Label 'developerGuide') 14
Add-Row $pairPanel (New-Label 'codeStep' 'section') 5
Add-Row $pairPanel (New-Label 'codeGuide') 10
$pairAddress = New-Input 260 'pairAddress'
$pairAddress.MaxLength = 64
$pairCode = New-Input 130 'pairCode'
$pairCode.MaxLength = 6
$pairCode.UseSystemPasswordChar = $true
$btnPair = New-Button 'pair' $true
$btnBackPair = New-Button 'back'
$btnPairManual = New-Button 'manual'
$btnCancelPair = New-Button 'cancel'
$pairFeedback = New-Label ''
Add-Row $pairPanel (New-Label 'pairAddress') 4
Add-Row $pairPanel $pairAddress 10
Add-Row $pairPanel (New-Label 'pairCode') 4
Add-Row $pairPanel $pairCode 12
Add-Row $pairPanel (New-ButtonRow @($btnPair, $btnBackPair, $btnCancelPair)) 6
Add-Row $pairPanel $pairFeedback 6
Add-Row $pairPanel $btnPairManual 0
Add-Row $homeLayout $pairPanel 12

$addressPanel = New-Stack 18
$surfaces.Add($addressPanel)
Add-Row $addressPanel (New-Label 'addressLabel' 'section') 5
Add-Row $addressPanel (New-Label 'addressGuide') 10
$addressInput = New-Input 260 'addressLabel'
$addressInput.MaxLength = 64
$btnAddress = New-Button 'resume' $true
$btnBackAddress = New-Button 'back'
$btnCancelAddress = New-Button 'cancel'
$addressFeedback = New-Label ''
Add-Row $addressPanel $addressInput
Add-Row $addressPanel (New-ButtonRow @($btnAddress, $btnBackAddress, $btnCancelAddress)) 6
Add-Row $addressPanel $addressFeedback 0
Add-Row $homeLayout $addressPanel 12

$usbPanel = New-Stack 18
$surfaces.Add($usbPanel)
Add-Row $usbPanel (New-Label 'chooseUsb' 'section') 5
Add-Row $usbPanel (New-Label 'usbGuide') 10
$usbList = New-Combo
$usbList.AccessibleName = Text-For 'chooseUsb'
$usbList.DisplayMember = 'Label'
$btnUsbSelect = New-Button 'start' $true
$btnBackUsb = New-Button 'back'
Add-Row $usbPanel $usbList
Add-Row $usbPanel (New-ButtonRow @($btnUsbSelect, $btnBackUsb)) 0
Add-Row $homeLayout $usbPanel 12

$deviceLayout = New-Stack 24
$pageProfiles.Controls.Add($deviceLayout)
Add-Row $deviceLayout (New-Label 'profiles' 'section')
$profileList = New-Combo
$profileList.DisplayMember = 'name'
$profileList.AccessibleName = Text-For 'profile'
$profileName = New-Input 260 'profileName'
$profileName.MaxLength = 50
$btnAddProfile = New-Button 'addProfile'
$btnDeleteProfile = New-Button 'deleteProfile'
Add-Row $deviceLayout (New-Label 'profile') 4
Add-Row $deviceLayout $profileList
Add-Row $deviceLayout (New-Label 'profileName') 4
Add-Row $deviceLayout $profileName
Add-Row $deviceLayout (New-ButtonRow @($btnAddProfile, $btnDeleteProfile))

$preferences = New-Stack 24
$pageSettings.Controls.Add($preferences)
Add-Row $preferences (New-Label 'preferences' 'section')
$langList = New-Combo
[void]$langList.Items.AddRange(@('简体中文', 'English'))
$langList.SelectedIndex = [int]($settings.language -eq 'en-US')
$langList.AccessibleName = Text-For 'language'
$themeList = New-Combo
[void]$themeList.Items.AddRange(@('Light / 浅色', 'Dark / 深色'))
$themeList.SelectedIndex = [int]($settings.theme -eq 'dark')
$themeList.AccessibleName = Text-For 'theme'
$autoReconnect = New-Object Windows.Forms.CheckBox
$autoReconnect.AutoSize = $true
$autoReconnect.Checked = [bool]$settings.autoReconnect
Set-Caption $autoReconnect 'autoReconnect'
$interval = New-Number 3 120 $settings.monitorIntervalSec
$bitrate = New-Input 110 'bitrate'
$bitrate.Text = [string]$settings.bitrate
$fps = New-Number 1 240 $settings.maxFps
$maxSize = New-Number 0 8192 $settings.maxSize
$btnSaveSettings = New-Button 'save' $true
$settingsNote = New-Label '' 'body'
foreach ($field in @(
    @{ Key = 'language'; Control = $langList },
    @{ Key = 'theme'; Control = $themeList },
    @{ Key = 'interval'; Control = $interval },
    @{ Key = 'bitrate'; Control = $bitrate },
    @{ Key = 'fps'; Control = $fps },
    @{ Key = 'size'; Control = $maxSize })) {
  Add-Row $preferences (New-Label $field.Key) 4
  $field.Control.AccessibleName = Text-For $field.Key
  Add-Row $preferences $field.Control
}
Add-Row $preferences $autoReconnect
Add-Row $preferences $btnSaveSettings
Add-Row $preferences $settingsNote

$logLayout = New-Stack 24
$pageLogs.Controls.Add($logLayout)
$logBox = New-Input 450 ''
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.Height = 300
$logBox.Dock = 'Fill'
$btnClearLogs = New-Button 'clearLogs'
$btnOpenLogs = New-Button 'openLogs'
Add-Row $logLayout (New-Label 'diagnostics' 'section')
Add-Row $logLayout $logBox
Add-Row $logLayout (New-ButtonRow @($btnClearLogs, $btnOpenLogs))

$state = @{
  Job = $null; View = 'home'; Status = 'disconnected'; Device = $null; Mode = 'wifi'
  UsbSerial = ''; Control = $null; ErrorLog = ''; ShortcutNote = ''; NextMonitor = [DateTime]::UtcNow
  Runtime = Test-ScrcpyRuntime; LoadingProfiles = $false; Closing = $false
}
$managedInputs = @($pairAddress, $pairCode, $addressInput, $usbList, $profileList,
  $profileName, $btnAddProfile, $btnDeleteProfile, $btnPair, $btnAddress, $btnUsbSelect)

function Apply-Appearance {
  $dark = $settings.theme -eq 'dark'
  if ($dark) {
    $palette.Page = [Drawing.ColorTranslator]::FromHtml('#151D29')
    $palette.Card = [Drawing.ColorTranslator]::FromHtml('#202C3D')
    $palette.Input = [Drawing.ColorTranslator]::FromHtml('#101923')
    $palette.Text = [Drawing.ColorTranslator]::FromHtml('#ECF3FE')
    $palette.Muted = [Drawing.ColorTranslator]::FromHtml('#C2CFE3')
    $palette.Border = [Drawing.ColorTranslator]::FromHtml('#495B75')
  } else {
    $palette.Page = [Drawing.ColorTranslator]::FromHtml('#F3F4F6')
    $palette.Card = [Drawing.Color]::White
    $palette.Input = [Drawing.Color]::White
    $palette.Text = [Drawing.ColorTranslator]::FromHtml('#1E293B')
    $palette.Muted = [Drawing.ColorTranslator]::FromHtml('#3F5774')
    $palette.Border = [Drawing.ColorTranslator]::FromHtml('#D4DEEB')
  }
  $accent = [Drawing.ColorTranslator]::FromHtml('#2563EB')
  $masthead.BackColor = $palette.Card
  $mastheadTitle.ForeColor = if ($dark) { [Drawing.ColorTranslator]::FromHtml('#93BCFF') } else { $accent }
  $form.ForeColor = $palette.Text
  $form.BackColor = $palette.Page
  foreach ($surface in $surfaces) {
    $surface.BackColor = if ($surface -is [Windows.Forms.TabPage]) { $palette.Page } else { $palette.Card }
    $surface.ForeColor = $palette.Text
  }
  foreach ($inputControl in $inputs) {
    $inputControl.ForeColor = $palette.Text
    $inputControl.BackColor = $palette.Input
  }
  foreach ($button in $buttons) {
    $button.BackColor = if ($button.Tag -eq $true) { $accent } else { $palette.Card }
    $button.ForeColor = if ($button.Tag -eq $true) { [Drawing.Color]::White } else { $palette.Text }
    $button.FlatAppearance.BorderColor = if ($button.Tag -eq $true) { $accent } else { $palette.Border }
  }
  foreach ($label in @($deviceMode, $wifiDescription, $usbDescription, $usbStatus, $pairFeedback, $addressFeedback)) { $label.ForeColor = $palette.Muted }
  foreach ($label in @($wifiTitle, $usbTitle, $optionsTitle, $shortcutTitle)) { $label.ForeColor = $mastheadTitle.ForeColor }
}

function Add-Diagnostic([string]$Detail) {
  if (-not $Detail) { return }
  $stamp = Get-Date -Format 'HH:mm:ss'
  if ($logBox.TextLength -gt 24000) { $logBox.Clear() }
  $logBox.AppendText("[$stamp] $Detail" + [Environment]::NewLine)
  try { Write-AppLog -Message $Detail } catch { $logBox.AppendText($_.Exception.Message + [Environment]::NewLine) }
}

function Show-State {
  $busy = $null -ne $state.Job
  $running = $null -ne $state.Control
  $selected = $profileList.SelectedItem
  $statusKey = if ($state.Status -eq 'address-needed' -and $selected.pendingPair) { 'paired-address-needed' } else { $state.Status }
  $statusLabel.Text = Text-For $statusKey
  if ($state.Device) {
    $deviceName.Text = if ($state.Device.Model) { $state.Device.Model } else { $state.Device.Serial }
  } elseif ($state.Mode -eq 'wifi' -and $selected.model) {
    $deviceName.Text = $selected.model
  } else {
    $deviceName.Text = Text-For 'noDevice'
  }
  $btnPrimary.Text = if ($running) { Text-For 'stop' }
    elseif ($state.Status -in @('connected', 'control-failed') -and $state.Device.Kind -eq 'wifi') { Text-For 'start' }
    elseif ($selected.pendingPair) { Text-For 'resume' }
    elseif ($selected.identity) { Text-For 'retry' }
    elseif ($selected.endpoint) { Text-For 'resume' }
    else { Text-For 'add' }
  $onHome = $state.View -eq 'home'
  $hasProfile = [bool]($selected.identity -or $selected.pendingPair -or $selected.endpoint)
  $canConnect = $onHome -and -not $busy -and -not $running
  $usbActive = $state.Mode -eq 'usb'
  $usbRunning = $usbActive -and $running
  $homeCards.Visible = $onHome
  $quickCards.Visible = $onHome
  foreach ($button in $shortcutButtons.Values) { $button.Enabled = $running -and -not $busy }
  $shortcutFeedback.Text = if ($state.ShortcutNote) { Text-For $state.ShortcutNote }
    elseif ($running) { $statusLabel.Text }
    else { Text-For 'shortcutHint' }
  $btnPrimary.Visible = $onHome
  $btnPrimary.Enabled = $canConnect -or ($running -and -not $usbActive -and -not $busy)
  $btnUsb.Text = if ($usbRunning) { Text-For 'stop' } else { Text-For 'usbConnect' }
  $btnUsb.Enabled = $canConnect -or ($usbRunning -and -not $busy)
  $btnUsbOther.Visible = $canConnect -and [bool]$state.UsbSerial
  $btnManual.Visible = $canConnect -and ($hasProfile -or $state.Status -eq 'address-needed')
  $btnNewPair.Visible = $canConnect -and $hasProfile
  $btnCancel.Visible = $busy -and $onHome -and -not $usbActive
  $btnUsbCancel.Visible = $busy -and $onHome -and $usbActive
  $btnCancelPair.Visible = $busy -and $state.View -eq 'pair'
  $btnCancelAddress.Visible = $busy -and $state.View -eq 'address'
  foreach ($cancelButton in @($btnCancel, $btnUsbCancel, $btnCancelPair, $btnCancelAddress)) {
    $cancelButton.Enabled = $busy -and -not $state.Job.Token.IsCancellationRequested
  }
  $btnBackPair.Enabled = -not $busy
  $btnBackAddress.Enabled = -not $busy
  $btnPairManual.Visible = -not $busy
  $deviceName.Visible = [bool]($selected.model -or ($state.Device -and -not $usbActive))
  $deviceMode.Visible = $hasProfile
  $deviceMode.Text = if ($hasProfile) { (Text-For 'storedProfile') + ' · ' + $selected.name } else { '' }
  $usbModel.Text = if ($usbActive -and $state.Device) { $deviceName.Text } else { '' }
  $usbModel.Visible = [bool]$usbModel.Text
  $usbStatus.Text = if ($usbActive) { Text-For $state.Status } else { Text-For 'usbIdle' }
  if ($usbActive) {
    $deviceName.Text = if ($selected.model) { $selected.model } else { Text-For 'noDevice' }
    $statusLabel.Text = Text-For 'wifiIdle'
    $btnPrimary.Text = if ($hasProfile) { Text-For 'resume' } else { Text-For 'add' }
  }
  $pairFeedback.Text = Text-For $state.Status
  $pairFeedback.Visible = $state.View -eq 'pair' -and $state.Status -ne 'disconnected'
  $addressFeedback.Text = Text-For $statusKey
  $addressFeedback.Visible = $state.View -eq 'address' -and $state.Status -ne 'disconnected'
  $pairPanel.Visible = $state.View -eq 'pair'
  $addressPanel.Visible = $state.View -eq 'address'
  $usbPanel.Visible = $state.View -eq 'usb'
  foreach ($control in $managedInputs) { $control.Enabled = -not $busy -and -not $running }
  $btnUsbSelect.Enabled = -not $busy -and $usbList.SelectedIndex -ge 0
  $form.AcceptButton = if ($busy) { $null }
    elseif ($state.View -eq 'pair') { $btnPair }
    elseif ($state.View -eq 'address') { $btnAddress }
    elseif ($state.View -eq 'usb') { $btnUsbSelect }
    else { $null }
  $statusLabel.ForeColor = if ($state.Mode -eq 'wifi' -and $state.Status -in @('connected', 'controlling')) {
    if ($settings.theme -eq 'dark') { [Drawing.ColorTranslator]::FromHtml('#85DFC0') }
    else { [Drawing.ColorTranslator]::FromHtml('#146A50') }
  } else { $palette.Muted }
}

function Set-State([string]$Status, [string]$Detail) {
  if ($state.Status -ne $Status -and $Detail) { Add-Diagnostic $Detail }
  $state.Status = $Status
  Show-State
}

function Save-Profiles {
  Write-JsonFile -Path $paths.ProfileFile -Value $profiles
}

function Update-Profiles([string]$Preferred) {
  $state.LoadingProfiles = $true
  try {
    $profileList.Items.Clear()
    foreach ($entry in $profiles.items) {
      [void]$profileList.Items.Add($entry)
      if ($entry.name -eq $Preferred) { $profileList.SelectedItem = $entry }
    }
    if ($profileList.SelectedIndex -lt 0) { $profileList.SelectedIndex = 0 }
  }
  finally { $state.LoadingProfiles = $false }
}


$worker = {
  param($Root, $Task, $Data, [Threading.CancellationToken]$Token)
  $ErrorActionPreference = 'Stop'
  Import-Module (Join-Path $Root 'core\pairing.psm1')
  Import-Module (Join-Path $Root 'core\control.psm1')
  Import-Module (Join-Path $Root 'core\monitor.psm1')
  $video = @{ Bitrate = $Data.Bitrate; MaxFps = $Data.Fps; MaxSize = $Data.Size; Options = $Data.Options }

  switch ($Task) {
    'pair' { Invoke-DevicePairing -PairEndpoint $Data.Address -PairCode $Data.Code -Token $Token }
    'discover' { Resolve-WifiDevice -Identity $Data.Identity -WaitForDiscovery -Token $Token }
    'manual' {
      Resolve-WifiDevice -Identity $Data.Identity -Address $Data.Address -HardwareSerial $Data.HardwareSerial -ExplicitAddress -Token $Token
    }
    'monitor' {
      Get-ConnectionStatus -Identity $Data.Identity -Address $Data.Address -HardwareSerial $Data.HardwareSerial -Token $Token
    }
    'usb' {
      $result = Resolve-UsbDevice -Serial $Data.Serial -Token $Token
      if ($result.Status -ne 'connected') { return $result }
      Start-ScrcpyControl -Device $result.Device @video -Token $Token
    }
    'usb-status' { Resolve-UsbDevice -Serial $Data.Serial -Token $Token -AuthorizationSeconds 0 }
    'shortcut' { Invoke-PhoneAction -Device $Data.Device -HardwareSerial $Data.HardwareSerial -KeyCode $Data.KeyCode -Token $Token }
    'control' {
      Start-ScrcpyControl -Device $Data.Device -HardwareSerial $Data.HardwareSerial @video -Token $Token
    }
  }
}

function Start-Work([string]$Task, [hashtable]$Data = @{}, [string]$Message) {
  if ($state.Job -or $state.Closing) { return }
  $state.Runtime = Test-ScrcpyRuntime
  if (-not $state.Runtime.Success) {
    Set-State 'runtime-missing' $state.Runtime.Message
    return
  }
  $env:ADB = Join-Path $state.Runtime.Root 'adb.exe'
  $env:SCRCPY_SERVER_PATH = Join-Path $state.Runtime.Root 'scrcpy-server'
  $Data.Bitrate = [string]$settings.bitrate
  $Data.Fps = [int]$settings.maxFps
  $Data.Size = [int]$settings.maxSize
  $Data.Options = @{}
  foreach ($key in $optionChecks.Keys) { $Data.Options[$key] = $optionChecks[$key].Checked }
  $cancelSource = New-Object Threading.CancellationTokenSource
  $pipeline = [PowerShell]::Create()
  try {
    [void]$pipeline.AddScript($worker.ToString()).AddArgument($appRoot).AddArgument($Task).AddArgument($Data).AddArgument($cancelSource.Token)
    $handle = $pipeline.BeginInvoke()
    $state.Job = @{ Pipeline = $pipeline; Handle = $handle; Token = $cancelSource; Task = $Task }
    if ($Message) { Set-State $Message }
    else { Show-State }
  }
  catch {
    $pipeline.Dispose()
    $cancelSource.Dispose()
    Set-State 'failure' $_.Exception.Message
  }
}

function Stop-Control {
  if (-not $state.Control) { return }
  try { if (-not $state.Control.HasExited) { $state.Control.Kill() } } catch [InvalidOperationException] {}
  finally {
    $state.Control.Dispose()
    $state.Control = $null
    $state.ShortcutNote = ''
  }
}

function Show-ConnectAddress([bool]$UseStoredAddress) {
  $profile = $profileList.SelectedItem
  $addressInput.Text = if (-not $UseStoredAddress -or $profile.pendingPair) { '' }
    elseif ($profile.endpoint) { $profile.endpoint }
    elseif ($profile.name -eq 'default') { $legacyAddress }
    else { '' }
  $state.View = 'address'
  Show-State
  $pageHome.AutoScrollPosition = New-Object Drawing.Point(0, 0)
  [void]$addressInput.Focus()
}

function Set-ConnectedWifi($Result) {
  $selected = $profileList.SelectedItem
  if ($Result.Address) { $selected.endpoint = $Result.Address }
  elseif ($selected.pendingPair) { $selected.endpoint = '' }
  $selected.identity = [string]$Result.Identity
  if ($Result.HardwareSerial) { $selected.hardwareSerial = $Result.HardwareSerial }
  elseif ($selected.pendingPair) { $selected.hardwareSerial = '' }
  $selected.model = [string]$Result.Device.Model
  $selected.pendingIdentity = ''
  $selected.pendingPair = $false
  try { Save-Profiles } catch { Add-Diagnostic $_.Exception.Message }
  $state.Device = $Result.Device
  $state.Mode = 'wifi'
  $state.View = 'home'
  Set-State 'connected'
}

function Receive-Work {
  $job = $state.Job
  if (-not $job -or -not $job.Handle.IsCompleted) { return }
  $state.Job = $null
  $state.NextMonitor = [DateTime]::UtcNow.AddSeconds([int]$interval.Value)
  $result = $null
  $exception = $null
  try {
    $output = @($job.Pipeline.EndInvoke($job.Handle))
    if ($output.Count -ne 1) { throw 'The device operation returned an unexpected result.' }
    $result = $output[0]
  }
  catch { $exception = $_.Exception }
  finally {
    $cancelled = $job.Token.IsCancellationRequested
    $job.Pipeline.Dispose()
    $job.Token.Dispose()
  }

  if ($cancelled -or $state.Closing) {
    if ($result.Process) {
      $state.Control = $result.Process
      Stop-Control
    }
    if (-not $state.Closing) {
      if ($job.Task -eq 'shortcut') { $state.ShortcutNote = 'cancelled'; Show-State }
      else { Set-State 'cancelled' }
    }
    return
  }
  if ($exception) {
    $detail = $exception.GetBaseException().Message
    if ($job.Task -eq 'shortcut') {
      Add-Diagnostic $detail
      $state.ShortcutNote = 'actionFailed'
      Show-State
      return
    }
    Set-State $(if ($detail -match 'timed out|timeout') { 'timeout' } else { 'failure' }) $detail
    return
  }

  if ($job.Task -eq 'shortcut') {
    Add-Diagnostic $result.Detail
    $state.ShortcutNote = if ($result.Status -eq 'action-failed') { 'actionFailed' }
      elseif ($result.Path) { 'screenshotSaved' }
      else { '' }
    if ($result.Path) {
      try { Start-Process -FilePath $result.Path } catch { Add-Diagnostic $_.Exception.Message }
    }
    Show-State
    return
  }

  $profile = $profileList.SelectedItem
  if ($job.Task -eq 'pair' -and $result.Status -eq 'paired') {
    $pairCode.Clear()
    $profile.pendingPair = $true
    $profile.pendingIdentity = [string]$result.Identity
    try { Save-Profiles } catch { Add-Diagnostic $_.Exception.Message }
    $state.View = 'home'
    $state.Device = $null
    if ($profile.pendingIdentity) {
      Start-Work 'discover' @{ Identity = $profile.pendingIdentity } 'discovering'
    } else {
      Set-State 'address-needed'
      Show-ConnectAddress $false
    }
    return
  }

  if ($job.Task -in @('discover', 'manual', 'monitor') -and $result.Status -eq 'connected') {
    if ($job.Task -eq 'monitor' -and $state.Device.Serial -ceq $result.Device.Serial -and
        $profile.endpoint -eq $result.Address -and $state.Status -eq 'connected') {
      Show-State
    } else {
      Set-ConnectedWifi $result
    }
    return
  }

  if ($result.Status -eq 'choose-usb') {
    $usbList.Items.Clear()
    foreach ($candidate in $result.Devices) {
      $label = if ($candidate.Model) { "$($candidate.Model)  ·  $($candidate.Serial)" } else { $candidate.Serial }
      [void]$usbList.Items.Add([pscustomobject]@{ Label = $label; Serial = $candidate.Serial })
    }
    $state.View = 'usb'
    Set-State 'choose-usb'
    [void]$usbList.Focus()
    return
  }
  if ($result.Status -eq 'controlling') {
    $state.Control = $result.Process
    $state.ErrorLog = $result.ErrorLog
    $state.Device = $result.Device
    if ($job.Task -eq 'usb') { $state.UsbSerial = $result.Device.Serial }
    Set-State 'controlling'
    return
  }
  if ($job.Task -eq 'usb-status') {
    if ($result.Status -eq 'usb-missing') {
      $state.Device = $null
      Set-State 'usb-disconnected'
    } elseif ($result.Status -eq 'connected') {
      Set-State 'disconnected'
    } else {
      Set-State $result.Status $result.Detail
    }
    return
  }
  if ($result.Device -and $job.Task -eq 'usb') { $state.UsbSerial = $result.Device.Serial }
  if ($job.Task -in @('discover', 'manual', 'monitor')) { $state.Device = $null }
  Set-State $result.Status $result.Detail
  if ($job.Task -eq 'discover' -and $result.Status -eq 'address-needed') { Show-ConnectAddress $false }
}

function Start-Usb([string]$Serial) {
  $state.Mode = 'usb'
  $state.Device = $null
  $state.View = 'home'
  Start-Work 'usb' @{ Serial = $Serial } 'usb-wait'
}

function Show-PairForm {
  $state.Mode = 'wifi'
  $state.View = 'pair'
  $state.Device = $null
  Set-State 'disconnected'
  $pageHome.AutoScrollPosition = New-Object Drawing.Point(0, 0)
  [void]$pairAddress.Focus()
}

function Open-Home {
  if ($state.Job) { return }
  $state.View = 'home'
  Show-State
  $pageHome.AutoScrollPosition = New-Object Drawing.Point(0, 0)
}

$btnPrimary.Add_Click({
    if ($state.Control) {
      Stop-Control
      Set-State $(if ($state.Mode -eq 'wifi' -and $state.Device) { 'connected' } else { 'disconnected' })
      return
    }
    $profile = $profileList.SelectedItem
    $state.Mode = 'wifi'
    if ($state.Status -in @('connected', 'control-failed') -and $state.Device.Kind -eq 'wifi') {
      Start-Work 'control' @{ Device = $state.Device; HardwareSerial = $profile.hardwareSerial } 'launching'
    } elseif ($profile.pendingPair) {
      if ($profile.pendingIdentity -and $state.Status -notin @('address-needed', 'pairing-required')) {
        Start-Work 'discover' @{ Identity = $profile.pendingIdentity } 'discovering'
      } elseif ($state.Status -eq 'pairing-required') {
        Show-PairForm
      } else {
        Show-ConnectAddress $false
      }
    } elseif ($state.Status -eq 'pairing-required') {
      Show-PairForm
    } elseif ($profile.identity -and $state.Status -ne 'address-needed') {
      Start-Work 'monitor' @{ Identity = $profile.identity; Address = $profile.endpoint; HardwareSerial = $profile.hardwareSerial } 'connecting'
    } elseif ($profile.endpoint -or $profile.identity -or ($profile.name -eq 'default' -and $legacyAddress)) {
      Show-ConnectAddress $true
    } else {
      Show-PairForm
    }
  })
$btnPair.Add_Click({
    $address = $pairAddress.Text.Trim()
    $code = $pairCode.Text
    Start-Work 'pair' @{ Address = $address; Code = $code } 'pairing'
  })
$btnManual.Add_Click({
    $state.Mode = 'wifi'
    Show-ConnectAddress $true
  })
$btnNewPair.Add_Click({ Show-PairForm })
$btnPairManual.Add_Click({ Show-ConnectAddress $true })
$btnAddress.Add_Click({
    $profile = $profileList.SelectedItem
    $identity = if ($profile.pendingPair) { $profile.pendingIdentity } else { $profile.identity }
    $storedSerial = if ($profile.pendingPair) { '' } else { $profile.hardwareSerial }
    Start-Work 'manual' @{ Identity = $identity; Address = $addressInput.Text.Trim(); HardwareSerial = $storedSerial } 'connecting'
  })
$btnUsb.Add_Click({
    if ($state.Control -and $state.Mode -eq 'usb') {
      Stop-Control
      Set-State 'disconnected'
    } else { Start-Usb $state.UsbSerial }
  })
$btnUsbOther.Add_Click({
    $state.UsbSerial = ''
    Start-Usb ''
  })
$btnUsbSelect.Add_Click({
    if ($usbList.SelectedItem) { Start-Usb $usbList.SelectedItem.Serial }
  })
$usbList.Add_SelectedIndexChanged({ Show-State })
foreach ($cancelButton in @($btnCancel, $btnUsbCancel, $btnCancelPair, $btnCancelAddress)) {
  $cancelButton.Add_Click({ if ($state.Job) { $state.Job.Token.Cancel(); Show-State } })
}
$btnBackPair.Add_Click({ Open-Home })
$btnBackAddress.Add_Click({ Open-Home })
$btnBackUsb.Add_Click({ Open-Home })
$form.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -ne [Windows.Forms.Keys]::Escape) { return }
    if ($state.Job) { $state.Job.Token.Cancel(); Show-State }
    elseif ($state.View -ne 'home') { Open-Home }
    else { return }
    $eventArgs.Handled = $true
    $eventArgs.SuppressKeyPress = $true
  })

$profileList.Add_SelectedIndexChanged({
    if ($state.LoadingProfiles -or -not $profileList.SelectedItem) { return }
    $profiles.defaultProfile = $profileList.SelectedItem.name
    try { Save-Profiles } catch { Add-Diagnostic $_.Exception.Message }
    $state.Device = $null
    $state.Mode = 'wifi'
    $state.View = 'home'
    $state.NextMonitor = [DateTime]::UtcNow
    Set-State 'disconnected'
  })
$btnAddProfile.Add_Click({
    $name = $profileName.Text.Trim()
    if (-not $name -or $profiles.items.name -contains $name) { return }
    $profiles.items = @($profiles.items) + [pscustomobject]@{
      name = $name; endpoint = ''; identity = ''; hardwareSerial = ''; model = ''; pendingIdentity = ''; pendingPair = $false
    }
    $profileName.Clear()
    $profiles.defaultProfile = $name
    Save-Profiles
    Update-Profiles $name
    $state.Device = $null
    $state.Mode = 'wifi'
    $state.View = 'home'
    Set-State 'disconnected'
  })
$btnDeleteProfile.Add_Click({
    $selected = $profileList.SelectedItem
    if (-not $selected -or $selected.name -eq 'default') { return }
    if ([Windows.Forms.MessageBox]::Show($form, (Text-For 'deleteQuestion'), $form.Text, 'YesNo', 'Question') -ne 'Yes') { return }
    $profiles.items = @($profiles.items | Where-Object { $_.name -ne $selected.name })
    $profiles.defaultProfile = 'default'
    Save-Profiles
    Update-Profiles 'default'
    $state.Device = $null
    $state.Mode = 'wifi'
    $state.View = 'home'
    Set-State 'disconnected'
  })

function Refresh-Language {
  $form.Text = Text-For 'title'
  foreach ($entry in $captions) { $entry.Control.Text = Text-For $entry.Key }
  foreach ($field in @(
      @{ Key = 'profile'; Control = $profileList }, @{ Key = 'profileName'; Control = $profileName },
      @{ Key = 'pairAddress'; Control = $pairAddress }, @{ Key = 'pairCode'; Control = $pairCode },
      @{ Key = 'addressLabel'; Control = $addressInput }, @{ Key = 'chooseUsb'; Control = $usbList },
      @{ Key = 'language'; Control = $langList }, @{ Key = 'theme'; Control = $themeList },
      @{ Key = 'bitrate'; Control = $bitrate }, @{ Key = 'interval'; Control = $interval },
      @{ Key = 'fps'; Control = $fps }, @{ Key = 'size'; Control = $maxSize })) {
    $field.Control.AccessibleName = Text-For $field.Key
  }
  Show-State
}

$btnSaveSettings.Add_Click({
    $settings.language = if ($langList.SelectedIndex -eq 1) { 'en-US' } else { 'zh-CN' }
    if ($bitrate.Text.Trim() -notmatch '^[1-9][0-9]{0,8}[KM]?$') {
      $settingsNote.Text = Text-For 'badBitrate'
      return
    }
    $settings.theme = if ($themeList.SelectedIndex -eq 1) { 'dark' } else { 'light' }
    $settings.bitrate = $bitrate.Text.Trim().ToUpperInvariant()
    $settings.maxFps = [int]$fps.Value
    $settings.maxSize = [int]$maxSize.Value
    $settings.monitorIntervalSec = [int]$interval.Value
    $settings.autoReconnect = $autoReconnect.Checked
    Write-JsonFile -Path $paths.SettingsFile -Value $settings
    Apply-Appearance
    Refresh-Language
    $settingsNote.Text = Text-For 'saved'
  })

foreach ($key in $optionChecks.Keys) {
  $optionChecks[$key].Add_CheckedChanged({
      foreach ($name in $optionChecks.Keys) { $settings.$name = $optionChecks[$name].Checked }
      try { Write-JsonFile -Path $paths.SettingsFile -Value $settings } catch { Add-Diagnostic $_.Exception.Message }
    })
}
foreach ($key in $shortcutKeys.Keys) {
  $shortcutButtons[$key].Tag = $shortcutKeys[$key]
  $shortcutButtons[$key].Add_Click({
      param($sender, $eventArgs)
      if (-not $state.Control -or $state.Control.HasExited -or $state.Job) { return }
      $serial = if ($state.Mode -eq 'wifi') { $profileList.SelectedItem.hardwareSerial } else { '' }
      $state.ShortcutNote = ''
      Start-Work 'shortcut' @{ Device = $state.Device; HardwareSerial = $serial; KeyCode = [int]$sender.Tag }
    })
}

$btnClearLogs.Add_Click({ $logBox.Clear() })
$btnOpenLogs.Add_Click({ Start-Process explorer.exe ('"{0}"' -f $paths.Logs) })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 125
$timer.Add_Tick({
    Receive-Work
    if ($state.Control -and $state.Control.HasExited) {
      $exitCode = $state.Control.ExitCode
      Stop-Control
      if ($exitCode -ne 0 -and (Test-Path -LiteralPath $state.ErrorLog)) {
        Add-Diagnostic (Get-Content -LiteralPath $state.ErrorLog -Raw -ErrorAction SilentlyContinue)
      }
      if ($state.Mode -eq 'usb' -and $state.UsbSerial) {
        Start-Work 'usb-status' @{ Serial = $state.UsbSerial } 'usb-wait'
      } else {
        $state.Device = $null
        Set-State 'disconnected'
      }
    }
    if ($state.Job -or $state.Control -or $state.Mode -ne 'wifi' -or $state.View -ne 'home' -or
        -not $settings.autoReconnect -or -not $state.Runtime.Success -or [DateTime]::UtcNow -lt $state.NextMonitor) { return }
    $profile = $profileList.SelectedItem
    if ($profile.pendingPair -or -not $profile.identity -or $state.Status -eq 'pairing-required' -or $tabs.SelectedTab -ne $pageHome) { return }
    $state.NextMonitor = [DateTime]::UtcNow.AddSeconds([int]$settings.monitorIntervalSec)
    Start-Work 'monitor' @{ Identity = $profile.identity; Address = $profile.endpoint; HardwareSerial = $profile.hardwareSerial }
  })
$form.Add_FormClosing({
    param($sender, $eventArgs)
    $state.Closing = $true
    if ($state.Job) { $state.Job.Token.Cancel() }
    Stop-Control
  })

Update-Profiles $profiles.defaultProfile
Apply-Appearance
Refresh-Language
if (-not $state.Runtime.Success) { Set-State 'runtime-missing' $state.Runtime.Message }
$form.Add_Shown({ Show-State; $timer.Start() })
try { [void]$form.ShowDialog() }
finally {
  $timer.Stop()
  $timer.Dispose()
  if ($state.Job) {
    $state.Job.Token.Cancel()
    [void]$state.Job.Handle.AsyncWaitHandle.WaitOne()
    Receive-Work
  }
  $form.Dispose()
  $headFont.Dispose()
  $sectionFont.Dispose()
}
