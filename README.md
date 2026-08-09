# Scarlett 6i6 Mixer for macOS

A native macOS control panel for the **Focusrite Scarlett 6i6 (3rd Gen)**, written in SwiftUI, with a small C daemon that talks to the hardware over USB.

This is the result of reverse-engineering the Scarlett 6i6's USB control protocol on macOS — a control surface that Focusrite dropped for macOS in favour of the web-based Focusrite Control 2. It gives you back full offline control of your interface.

## Features

- **Matrix mixer / routing** — every input (analog, S/PDIF, ADAT) to every output, with gain in dB
- **Level meters** — 10 Hz polling with fast decay and click-to-reset peak hold
- **Preamps** — gain, +48V phantom power, input switching (line / instrument / 10kΩ pad), phase invert
- **Clock & sample rate** — `Internal` / `S/PDIF` / `ADAT` clock source and 44.1–96 kHz rate selection, straight from the UI
- **Presets** — JSON save/load/export/import, plus **write presets to the hardware's internal flash** (like Focusrite Control)
- **Zero setup** — ships as a `.app` bundle with the daemon embedded; no kernel drivers, no kexts, no Focusrite Control 2 needed
- **Resilience** — daemon auto-respawns, watchdog recovers from USB resets, app auto-reconnects
- **No notifications required** — the 3rd-gen interrupt endpoint is not exposed on macOS, so the daemon polls the hardware instead

## Architecture

```
┌─────────────────────────┐         ┌──────────────────────────────────┐
│  fase-2-gui/ (SwiftUI)  │  UNIX   │  fase-1-daemon/ (C, IOUSBHost)  │
│  Scarlett 6i6 Mixer.app │ socket  │  scarlett-6i6d                  │
│                         │◄───────►│  /tmp/scarlett-6i6.sock         │
└─────────────────────────┘         └───────────────┬──────────────────┘
                                                    │ USB vendor protocol
                                                    ▼
                                          Focusrite Scarlett 6i6 (3rd Gen)
```

- `fase-1-daemon/` — C daemon (`src/main.c`, `src/usb-io.mm`): opens the device, decodes the FCP protocol, serves a simple line-based socket API (`DUMP`, `SET mix`, `SET preamp`, `SET clock`, `SET rate`, `SET save`, …)
- `fase-2-gui/scarlett-app/` — Swift package with the SwiftUI app: matrix view, preamps, meters, clock/rate pickers, presets panel
- `fase-2-gui/package.sh` — assembles `dist/Scarlett 6i6 Mixer.app` with the daemon embedded in `Contents/Resources`

The daemon launches automatically from the app (`DaemonManager`), so you just open the app and the interface comes alive.

## Build & run

Requirements: macOS 14+, Xcode Command Line Tools.

```bash
# 1. Build the daemon
cd fase-1-daemon && make

# 2. Build the app (from repo root)
cd fase-2-gui/scarlett-app && swift build

# 3. Package the .app (includes daemon)
cd fase-2-gui && ./package.sh

# 4. Run
open "dist/Scarlett 6i6 Mixer.app"
```

Or run the daemon standalone for headless control:

```bash
fase-1-daemon/scarlett-6i6d &
echo "DUMP" | socat - UNIX-CONNECT:/tmp/scarlett-6i6.sock
```

## Hardware support

- **Supported:** Focusrite Scarlett 6i6 3rd Gen (verified on real hardware)
- **Not supported:** 1st/2nd Gen, other Scarlett models, Clarett/Vocaster. The daemon decodes FCP (2nd Gen+) and hardcodes the 6i6 3rd-gen register map.

## Credits & references

This project is a clean-room-ish macOS port that could not exist without the Linux audio community's work. It uses no code from them (except as reference), but the protocol knowledge was built from:

- **[fcp](https://github.com/geoffreybennett/fcp) — Geoffrey D. Bennett's Focusrite Control Protocol kernel driver** (GPL-2.0). The authoritative source for the FCP vendor protocol used by 2nd/3rd/4th Gen Scarletts.
- **[Linux ALSA Scarlett mixer driver](https://github.com/geoffreybennett/linux-scarlett)** (`sound/usb/mixer_scarlett.c`, GPL-2.0-or-later) — gen-1 register layout and gain/DB scaling.
- **[alsa-scarlett-gui](https://github.com/Kemuri/alsa-scarlett-gui)** by Kemuri — Linux control panel; UI layout and meter behaviour informed ours.
- **[scarlett-mixcontrol-1stgen](https://github.com/Nas3nmann/scarlett-mixcontrol-1stgen)** — Focusrite's community-edition MixControl, used as reference for preset format and reconnect behaviour.

## License

GPL-2.0 — the daemon derives from GPL-2.0 protocol documentation and headers from the ALSA/FCP ecosystem; the whole repository is released under the same license.
