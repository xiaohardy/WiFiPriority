# WiFi Priority

[简体中文说明](README.md)

WiFi Priority is a native macOS menu bar app that connects to saved Wi-Fi networks in your chosen order. It supports multiple backups, hidden networks, an optional global pause shortcut, and eight interface languages.

## Getting started

1. Connect to and save each network in macOS Wi-Fi settings first.
2. Open WiFi Priority and grant location access so it can read the current Wi-Fi name. Add your saved networks in priority order. The badge on a row shows the network macOS is currently using; the blue selection only shows which row you are editing.
3. Enable automatic switching. macOS may ask for Keychain access separately for each protected network in your list. The app copies only those authorized credentials into its own encrypted login Keychain items, so routine switches do not prompt again. Refresh saved credentials in the app after changing a Wi-Fi password.
4. To test a network manually, pause automatic switching, select the row, and choose **Test in macOS Wi-Fi**. Make the connection in the system UI. The app checks the resulting network name for up to two minutes and leaves your selection connected.
5. Optionally record a global shortcut to pause or resume switching. The app asks macOS to register it and retains the previous shortcut if the new combination is unavailable.

The menu bar icon places one star at each priority position, up to twelve. The connected network's star is brighter. The icon dims while switching is paused. When connected to a backup, the app reads the current network every 15 seconds and scans candidates every 30 seconds. A disconnected Mac scans every 15 seconds. A network must be seen in two scans before the app tries to switch to it. Failures back off for 5, 10, then 15 minutes.

**iPhone Instant Hotspot:** macOS may show and join a nearby hotspot that does not appear in a normal CoreWLAN scan. This app cannot reliably wake such a hotspot. You can test it through the system Wi-Fi UI; it participates in automatic switching only when it appears as an ordinary discoverable network.

## Privacy and limits

- Credential lookup is restricted to the exact network names in your priority list. The app does not enumerate unrelated Keychain items, write passwords into settings or logs, or upload them.
- Credential copies live in the app's own login Keychain items. The app tries to delete a copy when its network is removed and reports a deletion failure.
- Local settings and a bounded event log are stored in `~/Library/Application Support/WiFiPriorityOpen/` with permissions for the current user only. Existing files are tightened when the new version starts. The log contains Wi-Fi names; anonymize it before sharing diagnostics.
- The app confirms Wi-Fi association only. It does not check Internet access, captive portals, VPNs, or proxies, and it does not alter wired networking, DNS, routes, proxies, or network service order. Switching a single Wi-Fi adapter can briefly disconnect it.

## Build from source

Requires macOS, Xcode/Swift 5.9 or newer, and Python 3. The package targets macOS 13, but this version has only been built and checked on Apple Silicon with macOS 27. Other macOS versions and Intel Macs have not been tested.

```sh
bash scripts/test.sh
bash scripts/build.sh
open "dist/WiFi Priority.app" --args --preview
```

Preview mode uses fictional networks and neither scans nor connects. The default build uses an ad hoc signature. Public binary distribution requires a stable Developer ID signature, notarization, and broader system testing. Source version: **0.9.2 (build 14)**. A locally self-signed test DMG is not provided as a public release.

## License

[MIT](LICENSE)
