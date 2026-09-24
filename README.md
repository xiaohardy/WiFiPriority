# WiFi Priority

[简体中文说明](README.zh-CN.md)

WiFi Priority is a small macOS menu bar app that switches among your saved Wi-Fi networks in the order you choose.

![WiFi Priority settings with three example networks](docs/images/settings-preview.png)

*Preview with example network names. The badge marks the network currently connected by macOS.*

## Install

1. Download the Apple Silicon DMG from the [v0.9.4 release](https://github.com/xiaohardy/WiFiPriority/releases/tag/v0.9.4).
2. Open the DMG and drag **WiFi Priority** to **Applications**.
3. Open **WiFi Priority** from Applications. The menu bar icon appears at the top of the screen.

![WiFi Priority and Applications in the installer](docs/images/installer.png)

### First launch on macOS

This preview build uses a local signing certificate and has **not been notarized by Apple**. After downloading it, macOS may say it cannot check the app for malicious software or verify its developer. Only continue if you got the DMG from [this project's release](https://github.com/xiaohardy/WiFiPriority/releases/tag/v0.9.4) and trust it.

1. After copying the app to Applications, try to open it once. If a warning appears, click **Done** if available.
2. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway**.
3. When macOS asks again, click **Open**.

macOS saves this choice for the app on your Mac. See [Apple's guide](https://support.apple.com/en-us/102445) for the same steps. If macOS says the app **is damaged** or **will damage your computer**, stop and [report the warning](https://github.com/xiaohardy/WiFiPriority/issues). Do not turn off macOS security checks for all apps.

Requires macOS 13 or later on Apple Silicon. The current build was checked on macOS 27; other versions and Intel Macs have not been tested.

## Set up your networks

1. Connect to each network once in macOS Wi-Fi settings so the system saves it.
2. Add those networks in WiFi Priority, put the preferred one first, and save the order. Allow location access when macOS asks; it lets the app read Wi-Fi names.
3. Select **Enable auto-switching**. macOS may ask for Keychain access to each protected network in your list. If a password changes later, use **Refresh saved credentials** in the app.

The app reads credentials only for networks in your list and keeps its authorized copies in your login Keychain. It does not put passwords in settings or logs. Settings and an event log stay on your Mac; the log includes Wi-Fi names, so remove them before sharing it.

You can pause switching from the menu bar or assign an optional keyboard shortcut. To test a network without giving the app its password, pause switching and use **Test in macOS Wi-Fi**. An iPhone Instant Hotspot can be joined through macOS even when it does not appear in a normal Wi-Fi scan; automatic switching can use it only while it is discoverable as a Wi-Fi network.

The stars in the menu bar icon follow your network order. The brighter star shows the connected network, and the icon dims when switching is paused.

## Build from source

Install Xcode or Swift 5.9 or later and Python 3, then run:

```sh
bash scripts/test.sh
bash scripts/build.sh
open "dist/WiFi Priority.app" --args --preview
```

Preview mode uses example networks and does not scan or connect. The default build has an ad hoc signature and is intended for local development.

## Feedback and license

Report bugs or suggest changes in [GitHub Issues](https://github.com/xiaohardy/WiFiPriority/issues). WiFi Priority is released under the [MIT License](LICENSE).
