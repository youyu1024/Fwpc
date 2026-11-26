# Fwpc

Fwpc 是面向 Windows 10/11 x64 的 Android 投屏与键鼠控制工具，支持 USB 有线直连和 Wi-Fi 六位码配对。

## 下载和使用

从 [GitHub Releases](https://github.com/youyu1024/Fwpc/releases) 下载 Windows x64 发布包。完整解压后，双击 WiFiPhoneControl.exe。发布包内置 scrcpy 4.0 和 ADB 37.0.0，无需额外安装。

### USB 一键直连

1. 在手机的开发者选项中开启 **USB 调试**，用支持数据传输的线缆连接电脑。
2. 在控制中心点击 **USB 一键直连**。首次连接时解锁手机，并在手机上允许 USB 调试。
3. 如果同时插入多台手机，先选择目标手机，再开始控制。USB 直连在手机关闭 Wi-Fi 时也可使用。

### Wi-Fi 六位码配对（Android 11 及以上）

1. 让手机与电脑接入可以互通的局域网。在手机的开发者选项中开启 **无线调试**。
2. 在手机上选择 **使用配对码配对设备**，保持配对弹窗开启。
3. 在电脑上点击 **连接手机**，输入弹窗中的 IP 地址、端口和六位配对码。
4. 连接成功后点击 **开始控制**。

配对已成功但未找到设备时，选择 **手动输入连接地址**，填写手机**无线调试主页面**上的当前 IP 地址和端口。访客网络或路由器的设备隔离可能阻止手机与电脑互通。可在 **诊断** 中查看失败详情，或暂时改用 USB 直连。

控制中心提供灭屏、保持唤醒、窗口置顶、全屏、触摸显示和音频选项。控制期间还可操作返回、主页、音量和截屏。

## 构建和验证

在 Windows PowerShell 中切换到仓库根目录，依次执行以下命令。

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\connection.tests.ps1
    .\build-release.cmd

构建会校验官方 scrcpy ZIP 的 SHA-256，并通过 ps2exe 打包启动器。v1.1.0 的产物为 release\WiFiPhoneControl-v1.1.0-win-x64.zip。验收项目见 [Windows 与 Android 发布检查](docs/release-acceptance.md)。

## 许可证

[MIT](LICENSE)
