# lights

Control WiZ smart lights on your local network from a Mac. Two tools, no dependencies:

- **`wiz.py`**: a small Python command-line script.
- **WizBar**: a native macOS menu bar app (Swift/AppKit + SwiftUI).

Both talk to the lights directly over the WiZ local protocol (JSON over UDP, port 38899). No cloud account or app needed; the computer just has to be on the same Wi-Fi as the lights.

## wiz.py

Requires Python 3, standard library only.

```bash
python3 wiz.py find            # list lights on the network
python3 wiz.py on              # turn on
python3 wiz.py off             # turn off
python3 wiz.py dim 40          # brightness 10-100
python3 wiz.py temp 3000       # color temperature 2200-6500 K
python3 wiz.py set 60 4000     # brightness + temperature together
python3 wiz.py status          # current state
```

By default every light found by broadcast is targeted. To control specific lights, set `LIGHT_IPS` at the top of the script (e.g. `["192.168.1.42"]`) after running `find`.

## WizBar

A menu bar app with:

- On/off switch, brightness and color temperature sliders
- Presets (add, reorder, remove, reset in Settings)
- Per-light selection, with custom names, or control all lights at once
- Automatic discovery, plus **Refresh Lights** (⌘R)

### Build

Requires macOS 14+ on Apple Silicon and the Xcode command-line tools (`xcode-select --install`).

```bash
./WizBar/build.sh              # builds WizBar/WizBar.app
./WizBar/build.sh --install    # also copies it into ~/Applications
```

The app is ad-hoc signed and runs as a menu bar–only app (no Dock icon).

## Layout

```
wiz.py                  Python CLI
WizBar/
  build.sh              build script (swiftc + codesign)
  Info.plist
  Sources/
    main.swift          entry point
    AppDelegate.swift   menu bar UI and control logic
    WizClient.swift     UDP client (Swift port of wiz.py)
    LightStore.swift    discovered lights and names
    PresetStore.swift   saved presets
    SettingsView.swift  SwiftUI settings window
    SliderMenuItem.swift, SwitchMenuItem.swift  custom menu items
```
