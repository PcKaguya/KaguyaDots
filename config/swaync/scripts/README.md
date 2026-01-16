# swaync Wi‑Fi & Bluetooth control scripts

This directory contains two interactive, wofi-centered scripts used by SwayNC to
manage Wi‑Fi and Bluetooth:

- `swaync-wifi-control.sh` — interactive Wi‑Fi menu (scan/search/connect/save/ignore)
- `swaync-bluetooth-control.sh` — interactive Bluetooth menu (scan/pair/connect/ignore)

Both scripts aim to provide a nicer, keyboard-friendly UI (using `wofi`) and modern
UX expectations: search/filter, connect, save/forget, and ignore/hide items.

---

## Features

Wi‑Fi (via `swaync-wifi-control.sh`)

- Scan (search) available networks (rescan + show results)
- Connect to networks (prompts for password when required)
- Save (persist connection profiles via NetworkManager)
- Show saved connections (connect/forget)
- Ignore / Hide SSIDs (persisted, one per line)
- Toggle Wi‑Fi power on/off
- View basic network details
- UI: `wofi` (preferred), falls back to `rofi` or `zenity` if needed
- Notifications via `notify-send`

Bluetooth (via `swaync-bluetooth-control.sh`)

- Scan for (discover) devices
- Pair & Connect (pairing might require device acceptance or PIN confirmation)
- Connect / Disconnect devices
- Trust / Untrust (save/remove device trust)
- Remove (forget) devices
- Ignore / Hide devices by MAC or name (persisted list)
- Toggle Bluetooth power
- UI: `wofi` (preferred), falls back to `rofi` or `zenity`
- Notifications via `notify-send`

---

## Requirements

- Wi‑Fi: NetworkManager (`nmcli`) installed and managing Wi‑Fi on the system.
- Bluetooth: BlueZ (`bluetoothctl`) installed and working.
- A dmenu-style UI:
  - Preferred: `wofi`
  - Fallbacks: `rofi` → `zenity`
- `notify-send` (libnotify) for notifications.
- Sufficient privileges to manage network and bluetooth (e.g., standard user with polkit permissions).

If the preferred UI (`wofi`) is missing the scripts will try `rofi`, then `zenity`.
If none are available the script will exit with a helpful message.

---

## Locations & config

Scripts (in this repo):

- `KaguyaDots/.config/swaync/scripts/swaync-wifi-control.sh`
- `KaguyaDots/.config/swaync/scripts/swaync-bluetooth-control.sh`

Persistent ignore lists (one entry per line):

- Wi‑Fi ignores: `${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync/ignored_wifi`
- Bluetooth ignores: `${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync/ignored_bt`

Notes about the ignore lists:

- You can un-ignore items via the scripts' "Ignored" menu or by editing these files directly.
- Each line is treated as a literal SSID (Wi‑Fi) or MAC / name (Bluetooth) to hide from the
  main discovery lists.

---

## Usage

From SwayNC: the shipped `config.json` already references the scripts; e.g.:

```
{
  "label": " ",
  "command": "/home/<you>/.../KaguyaDots/.config/swaync/scripts/swaync-wifi-control.sh"
}
```

Or run directly from a terminal:

```sh
~/.config/swaync/scripts/swaync-wifi-control.sh
~/.config/swaync/scripts/swaync-bluetooth-control.sh
```

Typical flow:

- Click the Wi‑Fi/BT icon in the SwayNC panel (or run the script).
- Use the dmenu-style UI to search and pick an item.
- After selecting an SSID/device, pick an action (Connect, Save, Ignore, Details, etc).

Password prompts:

- `zenity --password` is used when available (hidden input).
- When `zenity` is not available, the script will attempt `wofi --hide-text` if supported,
  otherwise a visible prompt (this is a limitation of the environment and CLI UI).

---

## Security / Privacy

- Wi‑Fi passwords saved via NetworkManager may be stored in your system keyring or in cleartext
  depending on your system's NetworkManager configuration. Understand your distribution's
  behavior if you care about where credentials are stored.
- Bluetooth pairing may require confirmation or entering a PIN on the device — follow the
  prompts shown by your device or the script notifications.

---

## Troubleshooting

- Nothing shows up in the menus:
  - Ensure `nmcli` / `bluetoothctl` are installed and that the respective services are running.
  - Ensure your user has permission to manage network or bluetooth on your system (polkit).
- `wofi` not installed:
  - Install `wofi` for the best experience; otherwise install `rofi` or `zenity`.
- Pairing/connecting fails:
  - Make sure the remote device is in pairing mode and visible.
  - Check `bluetoothctl` interactively to see any pairing/pin prompts.

---

## Extending / Development notes

- The scripts are intentionally simple and shell-based for portability. If you'd like:
  - Add an option to prefer a different input method (e.g., a graphical password prompt).
  - Implement persistent per-network metadata (e.g., a JSON manifest) if needed.
  - Integrate with system keyrings explicitly for password storage (security-sensitive).
- A good starting point for debugging is to run the commands used by the script manually:
  - `nmcli device wifi list`, `nmcli device wifi rescan`, `nmcli connection show`
  - `bluetoothctl devices`, `bluetoothctl info <MAC>`, `bluetoothctl paired-devices`

---

## Notes / Changelog

- Initial enhancement: replaced older Zenity-only dialogs with a wofi-first UI and added:
  - Search/filter in menus (via dmenu-style matching)
  - Ignore/hide lists (persisted)
  - Save/forget networks & pair/trust devices actions
  - Fallback UI support (rofi, zenity)

---

Simplified behavior (current)

- I simplified both scripts so they are intentionally minimal and automatic:
  - Clicking the Wi‑Fi or Bluetooth control will:
    - Automatically save any currently-connected device to a simple saved-list:
      - Wi‑Fi saved file: ${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync/saved_wifi
        (one SSID per line)
      - Bluetooth saved file: ${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync/saved_bt
        (lines are stored as MAC|Name)
    - Immediately show a short notification listing what's currently connected and
      confirming that it has been saved.
    - No complex menus: the control is non-interactive by default and focused on
      auto-saving and reporting current connections.

- View or manage saved lists (simple and manual):
  - Wi‑Fi: `cat ${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync/saved_wifi`
  - Bluetooth: `cat ${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync/saved_bt`

Stay-Alive feature (prevent suspend)

- I added a Stay‑Alive toggle like the DnD control:
  - The control center has a "Stay" button which runs `stay_alive-toggle.sh`.
  - Clicking it:
    - If Stay‑Alive is OFF, you'll be prompted for a duration (15m / 1h / 4h / 8h / 24h / forever / custom) and Stay‑Alive will be enabled for that time.
    - If Stay‑Alive is ON, clicking it will disable it.
  - The implementation uses `systemd-inhibit` when available and persists state to:
    - PID & expiry: `${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync/stay_alive.*`
    - Log: `${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync/stay_alive.log`
  - Manual commands:
    - `KaguyaDots/.config/swaync/scripts/stay_alive.sh status` – prints `on <remaining>` or `off`
    - `KaguyaDots/.config/swaync/scripts/stay_alive.sh on 1h` – enable for 1 hour
    - `KaguyaDots/.config/swaync/scripts/stay_alive.sh off` – disable now

Reload & test

- Reload swaync to pick up the UI change:
  - `KaguyaDots/.config/swaync/refresh.sh` (restarts swaync)
- Helpful logs:
  - `~/.cache/KaguyaDots/swaync/` contains `wifi.log`, `bt.log`, `stay_alive.log`, etc.

If you want the saved lists to be editable from a simple UI, or for me to add a status label in the control center that always shows the connected SSID and connected Bluetooth device name, tell me and I’ll add it.

Troubleshooting & quick fixes
- If the wofi menu appears fully transparent or invisible on your system, try the rofi wrapper scripts which force rofi as the UI:
  - `KaguyaDots/.config/swaync/scripts/swaync-wifi-control-rofi.sh`
  - `KaguyaDots/.config/swaync/scripts/swaync-bluetooth-control-rofi.sh`
  You can call these directly from the SwayNC config (replace the command path) or run them manually to test.

- To temporarily force a specific UI without editing the config, prefix the script invocation:
  - `SWAYNC_UI=rofi ~/.config/swaync/scripts/swaync-wifi-control.sh`

- After updating CSS or theme files, reload SwayNC so style changes take effect:
  - `swaync-client --reload-config`
  - or run the included helper: `KaguyaDots/.config/swaync/refresh.sh` (this restarts swaync).

- Logs: the Wi‑Fi and Bluetooth scripts emit debug notifications and logs to:
  - `${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync/`
  Look for files such as `wifi.log`, `bt.log`, `wifi-rofi.log`, and `bt-rofi.log` to confirm a button click invoked the script and to see any errors.

If you want additional behavior (e.g., show the currently-connected Wi‑Fi SSID on the bar,
or list connected Bluetooth device names in the status widget), tell me how you want it to
behave and I can help extend the scripts to support it.
