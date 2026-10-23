# GameSir Calibrator

A small macOS app that checks your GameSir controller's sticks for drift and roundness, walks you through the controller's built-in calibration, and measures again so you can see the difference.

Unofficial. Not affiliated with or endorsed by GameSir.

![GameSir Calibrator showing a Cyclone 2's stick measurement](docs/screenshot.jpg)

## Install

Requires macOS 14 or later, on an Apple Silicon or Intel Mac.

1. Download the latest `GameSirCalibrator-<version>.zip` from [Releases](https://github.com/AdhamSamer3301/GameSirCalibrator/releases/latest).
2. Double-click the zip to unzip it, then drag **GameSirCalibrator** into your **Applications** folder.
3. Open it. The first time, macOS says it "could not verify GameSirCalibrator is free of malware". Click **Done**, not Move to Trash.
4. Open **System Settings › Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to the GameSirCalibrator message. Confirm with your password or Touch ID, then click **Open Anyway** once more.

From then on it opens normally. Each new version you download asks once again.

**Why the warning?** The app is free and open source, but it isn't notarized by Apple, which requires a paid Apple Developer account. To check your download, compare the zip's SHA-256 with the one in the release notes (`shasum -a 256 GameSirCalibrator-*.zip`), or [build it yourself](#build).

**Prefer Terminal?** Instead of steps 3 and 4, clear the download flag. Only do this for apps you trust:

```bash
xattr -dr com.apple.quarantine /Applications/GameSirCalibrator.app
```

## Connect your controller

Put the controller in **Switch mode**; macOS then lists it as "Pro Controller".

- **GameSir Cyclone 2, 2.4 GHz dongle:** plug the dongle into your Mac, then press **Home + X**.
- **Bluetooth:** pair the controller in Switch mode (see its manual), then connect it in System Settings › Bluetooth.

Xbox (XInput) mode doesn't work, because macOS can't see controllers in that mode.

## What it does

1. **Measure:** it records where each stick rests (centre offset and noise), then how far and how evenly it travels while you rotate it (reach and roundness). It also suggests a deadzone.
2. **Calibrate:** it shows your controller's own calibration steps. The calibration runs inside the controller, so you don't need the GameSir app.
3. **Measure again:** it shows the before → after numbers side by side.

The app only reads the controller. It never writes to it, and it doesn't change how games see the controller.

## Supported controllers

| Controller | Mode | Connection | Calibration steps |
|---|---|---|---|
| GameSir Cyclone 2 | Switch (shows up as "Pro Controller") | 2.4 GHz dongle (Home + X), Bluetooth. Both tested | Built in |
| Other HID gamepads | Any mode macOS sees as a gamepad | USB, dongle, Bluetooth | Generic ("see your manual") |

In Switch mode the triggers are on/off buttons, so the app can't measure how far they travel.

## Build

Building requires Xcode 26 or later (CI uses Xcode 26.6). The app itself runs on macOS 14 or later.

```bash
xcodebuild -project GameSirCalibrator.xcodeproj -scheme GameSirCalibrator build
```

Or open `GameSirCalibrator.xcodeproj` and press Run. Tests: `xcodebuild … test`.

Release build (universal, for Apple Silicon and Intel):

```bash
xcodebuild -project GameSirCalibrator.xcodeproj -scheme GameSirCalibrator -configuration Release -destination 'generic/platform=macOS' build
```

## Add your controller

Calibration steps live in [`GameSirCalibrator/Guides.swift`](GameSirCalibrator/Guides.swift). Add an entry with your model name and the steps from its manual, then open a pull request. If your controller's sticks show up on the wrong axes, please open an issue and include the "Reading:" line from under the controller name.

## How it works

The app reads raw HID values through IOKit rather than Apple's GameController framework, which filters stick values. Most pads are read from their HID descriptor. Switch Pro-style pads in full report mode (`0x30`) pack the sticks as 12-bit values, so the app decodes those bytes directly (`Gamepad.switchProSticks`). Virtual pads, such as the one Steam Input creates, are ignored so each controller is listed once. The maths is in [`StickStats.swift`](GameSirCalibrator/StickStats.swift). Its thresholds are tuning constants at the top of the file.

## License

MIT
