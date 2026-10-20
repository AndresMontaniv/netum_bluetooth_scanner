# Using the example app

The example app (`example/`) exercises every part of the plugin with real hardware: use it to learn the API, or
to check what your own scanner does before writing code. Each control below lists the API call behind it, so you
can copy it into your app, and what we observed on a **NETUM DS5000** during testing. Other models may behave
differently; other brands won't understand the NETUM commands at all (see the README's
[Compatibility](../README.md#compatibility) section).

Run it with `flutter run` from `example/`. For [pair by scanning](#pair-by-scanning-android-spp), pass your phone's
Bluetooth MAC: `flutter run --dart-define=NETUM_PHONE_MAC=AA:BB:CC:DD:EE:FF`.

The app has four tabs. Every action is also written to the log at the bottom of the **Console** tab (and to the
debug console as `NETUM …` lines), with its result or error.

## Status

The phone side: is Bluetooth usable?

| Control | API | Notes |
|---|---|---|
| Adapter | `netum.adapterState` | `poweredOn`, `poweredOff`, `unauthorized`, `unsupported`, or `unknown` (iOS, before the app first asks for Bluetooth). |
| Permissions: discovery → Check / Request | `checkPermissions` / `requestPermissions(scope: PermissionScope.discovery)` | Android: Bluetooth scan + connect + Location. iOS: the Bluetooth prompt. |
| Permissions: connection → Check / Request | same with `PermissionScope.connection` | Connecting to a known scanner needs no Location. |
| Ask to turn Bluetooth on | `requestEnableBluetooth()` | Android's system dialog. iOS has none (returns `false`). |
| Max connections | `netum.maxConnections` | Default 7. |

## Scanners

Your scanners and the ones nearby, like the phone's Bluetooth settings.

**Header**

| Control | API | Notes |
|---|---|---|
| BLE / SPP | `discover(transport: …)` | SPP is Android only. Put the scanner in the matching mode first. |
| NETUM / All | `discover(filter: DiscoveryFilter.likelyNetum / .all)` | NETUM hides devices that don't look like NETUM scanners; All shows everything nearby. |
| Auto-reconnect | `connect(autoReconnect: …)` | Used for new connections from this tab. |
| ▦ Pair by scanning | `listenForSppScanner()` | Android, SPP. See [below](#pair-by-scanning-android-spp). |
| Scan / Stop | `discover()` / `stopDiscovery()` | Stops by itself after 10 s. |

**My scanners** lists every scanner you know: connected ones, saved ones (every successful connect is
remembered, see `savedScanners()`), and on Android the scanners paired with the phone over SPP
(`bondedScanners()`). For SPP the phone's pairing list is the truth: a saved SPP scanner whose pairing was
removed in the OS settings is left out until it is paired again. A coloured **BLE** / **SPP** badge marks each
tile's transport. The button on the right follows the state: **Connect**, **Disconnect**, a spinner while
connecting, or **Stop** while it is reconnecting. Tap a tile for:

| Control | API | Notes |
|---|---|---|
| Auto-reconnect | `device.autoReconnect = …` | Can change while connected. |
| Rename | `device.setName('Netum-01')` | The scanner restarts its radio; with auto-reconnect on it comes back by itself (about 3–5 s). The new name shows in discovery and in the saved list. |
| Device info | `device.getDeviceInfo()` | BLE: the Bluetooth module's maker, model, firmware and the Classic MAC (visible even on iOS). SPP: serial and firmware only. |
| Bluetooth info | `device.getBluetoothInfo()` | Name, address and module firmware (`AT+NAME`, `AT+ADDR`, `AT+VER`). |
| Forget | `netum.forgetScanner(id)` | Removes it from the saved list (not the OS pairing). |
| ⟲ Restore (section header) | `restoreSaved(strategy: …)` | **First available**: the most recent saved scanner that is in range. **All**: every saved scanner, up to max connections. No discovery needed. |

When a scan finds a scanner that is already in My scanners but not connected, its tile is marked **in range**
(with the signal strength) and the Available section says how many it found there.

**Available** shows what the current scan finds that isn't already in My scanners. Tap **Connect**; once it is
connected it moves up to My scanners. Over SPP, the first connect shows Android's pairing prompt.

### Pair by scanning (Android, SPP)

The vendor's alternative to discovery: the phone listens and the scanner dials in.

1. Check the MAC field (your phone's Bluetooth address, from Settings → About phone → Status).
2. If the scanner was paired with any phone before, **power-cycle it first**: it keeps its half of the old pairing
   and hangs up otherwise.
3. Tap **Listen** (`listenForSppScanner()`), then scan the on-screen barcode with the scanner
   (`NetumScanner.sppPairingBarcodeData(mac)`, rendered as Code 128).
4. Accept Android's pairing prompt. The app connects back as a client.

## Scans

Every barcode from every connected scanner (`netum.scans`), newest first: the text (terminator removed), the
scanner, the time it reached the app, and the raw bytes in hex. **Clear** empties the list.

## Console

Commands for the scanner selected at the top. Everything here is NETUM-specific.

### Settings (first row)

| Control | API | DS5000 behaviour |
|---|---|---|
| Volume | `setVolume(BeepVolume.high / medium / low / mute)` | Low and high are clearly different. |
| Tone | `setTone(BeepTone.high / low)` | Acknowledged, but **no audible change** on the DS5000. |
| Scan mode | `setScanMode(ScanMode …)` | `trigger`: laser while the trigger is held (default). `continuous`: a press toggles a steady laser on and off. `pulse`: a press gives one ~3 s scan. `hostTrigger`: a press toggles a repeating ~1 s scan cycle (not app-only, despite the name). App triggers work in every mode. |
| Sleep | `setSleepTimeout(SleepTimeout …)` | Idle time before the scanner sleeps (`never` … 2 h). |
| Terminator | `setTerminator(Terminator …)` | What the scanner adds after each barcode. The DS5000 already ends scans in CR with `none` (its factory value), so `cr` adds a **second** CR. The plugin strips any trailing CR/LF/TAB run, so `scan.text` is the same either way. |
| Work mode | `setWorkMode(WorkMode.normal / store)` | `store` (experimental): scans stay in the scanner's memory instead of being sent. See the stored-scans row below. |
| Switch mode | `switchMode(NetumMode.ble / spp / hid)` | ⚠️ The scanner restarts in the new mode and **drops the connection** (auto-reconnect is turned off first, since the id changes: BLE `DD:…`, SPP `DC:…`). Connect again over the new transport. `hid` leaves the plugin's reach: the scanner then types as a keyboard. |
| Vibration on / off | `setVibration(enabled: …)` | Felt on every scan when on. |
| ACK beep on / off | `setCommandConfirmationBeep(enabled: …)` | When on, the scanner beeps on every command it receives. Off is silent; replies still arrive. |

### Queries and stored scans (second row)

| Control | API | DS5000 behaviour |
|---|---|---|
| Sleep? | `getSleepTimeout()` | `null` means never. |
| Engine? | `getEngineModel()` | The decode engine's model. |
| Stored? | `getStoredCount()` | How many scans are in memory (store mode). |
| Upload | `uploadStored()` | Sends the stored scans; they arrive on `scans`, one event per code. |
| Upload+clear | `uploadStored(clearAfter: true)` | Same, then empties the memory. |
| Clear stored | `clearStored()` | Empties the memory without sending. |
| Traffic log | `netum.trafficLogEnabled` / `netum.traffic` | Logs every packet both ways, classified (`command`, `ack`, `echo`, `reply`, `barcode`, `unknown`). Off by default. |

### Actions (third row)

| Control | API | DS5000 behaviour |
|---|---|---|
| Scan 1s / Scan 3s | `triggerScan(seconds: …)` | Fires the scan engine from the app (1–7 s), as if the trigger were pressed. |
| Battery | `getBattery()` | Voltage and percent, e.g. `3.98 V, 64 %`. |
| Firmware | `getFirmwareVersion()` | E.g. `bn0HDS_RFSBTD43bc_CB071`. |
| RSSI | `readRssi()` | Signal strength in dBm. BLE only; over SPP it fails with an error. |
| Info | `getDeviceInfo()` | As in the Scanners tab. |

### Beep slider

`beep(preset)` plays one of the scanner's 27 preset sounds (0–26). Move the slider and tap **Beep N** to hear
each one.

### Free text

Type any command and send it, for commands the catalog doesn't cover (`NetumCommand` has most of them):

| Button | API | Use |
|---|---|---|
| Framed | `sendRaw(text)` | Wraps the text in NETUM's command frame (`02 len 0A … checksum 03`), the default. |
| Raw | `sendRaw(text, framed: false)` | Sends the bytes exactly as typed. |

The default text, `%BAT_VOL#`, is the battery query. The result (an ACK, a reply or nothing) appears in the log.
