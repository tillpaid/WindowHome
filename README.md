# WindowHome

WindowHome is a native macOS menu bar app that remembers where each app window belongs. Arrange your windows normally and it automatically keeps their latest position and size as Home for each display, ready to restore whenever your desktop gets rearranged.

It also includes practical window-management tools—keyboard and mouse snapping, centered resizing, display switching, and optional automation—without networking, accounts, telemetry, or cloud storage.

## Features

- Automatically save a **Home** after you move or resize a window with the mouse.
- Restore a separate Home for each app, display, and effective resolution.
- Save or replace a Home manually whenever you want explicit control.
- Undo and redo up to 20 Home changes for the focused app.
- Restore the main windows of all running apps at once.
- Move windows between displays while preserving their size when it fits.
- Apply the destination display's full Home after a WindowHome display move by default, with an option to preserve the current size for regular windows.
- Snap by keyboard to full screen, halves, or quarters.
- Repeat a side or corner shortcut to cycle through 50%, 66%, and 33% widths.
- Resize symmetrically from the window center with configurable steps.
- Optionally snap with the mouse, with visible activation areas and target previews.
- Restore saved geometry after an app launches.
- Configure or disable every global shortcut from Settings.

## Install

WindowHome currently requires:

- macOS 26.5 or later

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/tillpaid/WindowHome/releases).
2. Open the disk image and drag **WindowHome** into **Applications**.
3. Launch WindowHome. Its icon will appear in the menu bar.

### Build from source

To build WindowHome yourself, install Xcode with the macOS 26.5 SDK, then:

```sh
git clone https://github.com/tillpaid/WindowHome.git
cd WindowHome
open WindowHome.xcodeproj
```

In Xcode:

1. Select the **WindowHome** scheme and **My Mac** as the destination.
2. Choose your development team under **Signing & Capabilities** if Xcode asks for one.
3. Press `⌘R` to build and run the app.

## First launch

1. Open **WindowHome → Settings** from the menu bar.
2. Grant **Accessibility** access so WindowHome can read and position other apps' windows.
3. Grant **Input Monitoring** so it can detect when a mouse move or resize finishes.
4. Under **Snap & Resize → Mouse**, enable **Save Home after I move or resize a window with the mouse**.
5. Arrange your windows normally. WindowHome will automatically remember each regular position and size after you release the mouse.
6. Press `⌥⌘↩` whenever you want to return the focused window to its Home.

Full-screen, maximized, snapped, and standard half-screen layouts are not saved automatically. You can still use **Save Home** (`⌃⌥⌘S`) whenever you want to set a Home explicitly.

macOS may ask you to grant permissions again after the app is moved or rebuilt with a different signature.

## Default shortcuts

All shortcuts are global, configurable, and can be disabled individually.

| Action | Shortcut |
| --- | --- |
| Save / Restore Home | `⌃⌥⌘S` / `⌥⌘↩` |
| Undo / Redo Home | `⌃⌥⌘Z` / `⌃⌥⇧⌘Z` |
| Restore All / Center & Save | `⌃⌥⌘↩` / `⌃⌘C` |
| Previous / Next display | `⌃⌥⌘←` / `⌃⌥⌘→` |
| Snap left / right / top / bottom | `⌥⌘←` / `⌥⌘→` / `⌥⌘↑` / `⌥⌘↓` |
| Snap full screen | `⌥⌘F` |
| Snap top-left / top-right | `⌃⌘←` / `⌃⌘→` |
| Snap bottom-left / bottom-right | `⌃⇧⌘←` / `⌃⇧⌘→` |
| Decrease / increase width | `⌃⌥⇧⌘←` / `⌃⌥⇧⌘→` |
| Increase / decrease height | `⌃⌥⇧⌘↑` / `⌃⌥⇧⌘↓` |

## Storage and privacy

WindowHome works entirely on-device. It has no networking, telemetry, accounts, cloud storage, or third-party dependencies.

Saved window profiles are stored as JSON at:

```text
~/Library/Application Support/WindowHome/profiles.json
```

**Accessibility** is used only to identify, read, move, and resize application windows. **Input Monitoring** is used to detect mouse drag boundaries for automatic Home saving and optional mouse Snap. WindowHome does not record typed text or keep a history of pointer coordinates.

## Behavior and limitations

- A Home belongs to an application, display, and effective resolution—not to an individual window or browser tab.
- **Restore All** restores one main window per running app so multiple windows do not overlap.
- App-launch restore keeps a window on its current display.
- Automatic display-move restore applies only to WindowHome's Next/Previous Display shortcuts; WindowHome does not monitor arbitrary window movements.
- Mouse Snap currently supports left, right, and full-screen targets; keyboard Snap also supports top, bottom, and corners.
- Some apps enforce their own minimum or maximum window size. WindowHome keeps the closest geometry the app accepts.
- WindowHome uses public macOS Accessibility APIs; cross-app moves cannot be applied as one atomic animated frame update.

## Development

The project is built with SwiftUI, AppKit, Accessibility, Core Graphics, and Carbon hotkeys. UI code is kept separate from window, display, shortcut, and persistence services.

Run the test suite without code signing:

```sh
xcodebuild \
  -project WindowHome.xcodeproj \
  -scheme WindowHome \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/WindowHomeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:WindowHomeTests \
  test
```

Project overview:

```text
WindowHome/
├── App/          App state and feature coordination
├── Models/       Window geometry, profiles, and shortcuts
├── Services/     Accessibility, displays, hotkeys, automation, and storage
└── UI/           Settings pages and shortcut recording
```

## License

WindowHome is available under the [MIT License](LICENSE).
