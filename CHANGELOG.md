## 0.0.1-dev

* Project scaffold: package metadata, MIT license, lints, protocol docs in `doc/`.
* Pigeon contract between Dart and the native byte pipes (Android, iOS); adapter state works end-to-end.
* Protocol core (pure Dart, no device needed): frame encoder, reassembler, packet classifier, decoder,
  and a per-device session with a one-at-a-time command queue.
* `NetumCommand` catalog with validated builders, `CommandResult`, `BatteryInfo`, `AdapterState` and the
  `NetumException` hierarchy.
* Android BLE: permissions, adapter and Location state, discovery (NETUM filter, throttle-safe), connections
  with a GATT operation queue, several scanners at once, connections that survive a Dart hot restart.
* Public API: `NetumScanner` (discover, connect, global `scans` / `connectionEvents`) and `NetumDevice`
  (per-device streams, `triggerScan`, `beep`, `getBattery`, `getFirmwareVersion`, `send`, `sendRaw`).
* iOS BLE: the Bluetooth prompt appears only when the app asks (permissions, discovery or connect), discovery,
  connections (also to saved scanners without discovery), several scanners at once, hot-restart survival.
* `NetumDevice.getDeviceInfo()` (Device Information Service; shows the Classic MAC even on iOS).
* Example app with Status, Discover, Devices, Scans and Console tabs.
