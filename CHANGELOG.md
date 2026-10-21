## 0.1.1

* README: a photo of the tested hardware (NETUM DS5000) and a short features list.
* pub.dev: screenshots of the example app.
* Example: content stays clear of Android's navigation bar (edge-to-edge); unnamed devices show as "(no name)"
  in the log.

## 0.1.0

First release. Developed and hardware-tested with the NETUM DS5000.

* **BLE on Android and iOS, SPP (Classic Bluetooth) on Android.**
* **Discovery:** NETUM filter or everything nearby; SPP lists bonded scanners first, then live results.
  Permission, Bluetooth and Location state with typed errors.
* **Connections:** several scanners at once, one global `scans` stream plus per-device streams, connection
  events with the reason for each disconnect. Connections survive a Dart hot restart.
* **SPP pairing:** the OS pairing prompt on first connect, and the optional "pair by scanning" flow
  (`listenForSppScanner`, `sppPairingBarcodeData`).
* **Commands:** typed helpers (trigger, beep, battery, firmware, volume, tone, vibration, command beep,
  scan mode, sleep, terminator, power off, rename, mode switch, device and Bluetooth info, inventory mode),
  the `NetumCommand` catalog, and `sendRaw`. One command at a time per scanner, queued.
* **Auto-reconnect** (opt in per connection; gives up after 30 minutes by default) and **saved scanners**
  with `restoreSaved` (most recent first, or all), stored natively or in your own `NetumStore`.
* **Background:** scans keep reaching your listeners while the app is in the background (Android out of the
  box; iOS with the `bluetooth-central` background mode). See the README.
* **Debugging:** opt-in `traffic` stream with every packet classified.
* Example app with Status, Scanners, Scans and Console tabs, a pair-by-scanning screen, and a guide to every
  control (`doc/example_app.md`).
