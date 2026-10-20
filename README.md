# netum_bluetooth_scanner

[![pub package](https://img.shields.io/pub/v/netum_bluetooth_scanner.svg)](https://pub.dev/packages/netum_bluetooth_scanner)
[![pub points](https://img.shields.io/pub/points/netum_bluetooth_scanner)](https://pub.dev/packages/netum_bluetooth_scanner/score)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Flutter plugin for NETUM Bluetooth barcode scanners: BLE on Android and iOS, SPP (Classic Bluetooth) on
Android. Scan streams, several scanners at once, typed commands, auto-reconnect and saved scanners.

> **Not affiliated with or endorsed by NETUM.** "NETUM" is used only to identify the hardware this plugin talks to.

## What it is / isn't

**It is** a direct Bluetooth connection between your app and the scanner. Barcodes arrive as a Dart stream,
whatever screen or text field has focus, and the app can talk back to the scanner: beep, trigger a scan,
read the battery, change settings.

**It isn't** a keyboard (HID) listener, a USB / 2.4 GHz dongle driver, or a camera scanner. It keeps working
while your app is in the background (see [Background](#background)), but not after the OS ends the app.

## Compatibility

| | Android | iOS |
|---|---|---|
| BLE | ✅ API 24+ (Android 7.0) | ✅ iOS 15+ |
| SPP (Classic Bluetooth) | ✅ API 24+ | ❌ Apple doesn't allow SPP to third-party apps |

Flutter 3.41+ (Dart 3.11+). iOS works with both Swift Package Manager and CocoaPods.

**Scanners.** Developed and hardware-tested with the **NETUM DS5000** (1D). Other NETUM models will most likely
work, since they share the firmware's command set.

**Other brands.** BLE and SPP are standard Bluetooth, not NETUM-proprietary, so scanners from other brands can work
too:

- **SPP:** any scanner that uses the standard Serial Port Profile should deliver scans.
- **BLE:** BLE has no standard "barcode" profile; each brand picks its own data service. This plugin uses the
  `FFF0` (`FFF1`/`FFF2`) or `FF00` (`FF01`/`FF02`) layout, which many BLE serial modules share. A scanner with
  another layout fails to connect with `NetumConnectionFailed` ("No NETUM data service").
- Use `DiscoveryFilter.all` to see devices that don't look like NETUM scanners.
- **Commands are NETUM-only.** Battery, store mode, beeps, settings and the rest are reserved NETUM strings
  that the scanner's firmware understands. They are untested on other brands; queries such as `getBattery()`
  will most likely end in a `NetumCommandTimeout`.

## Install

```yaml
dependencies:
  netum_bluetooth_scanner: ^0.1.0
```

### Android setup

Nothing to add: the plugin's manifest declares the Bluetooth and Location permissions, and they merge into your
app. Ask for them at runtime with `requestPermissions`.

**Location:** on every Android version, Android reports nearby Bluetooth devices only to an app that has the
Location permission, and only while the phone's Location setting is on. Discovery fails with
`NetumLocationServicesOff` when it is off; connecting to a known scanner works without it.

### iOS setup

Add the Bluetooth usage description to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connects to your barcode scanner.</string>
```

The Bluetooth permission prompt appears only when your app first calls `requestPermissions`, `discover` or
`connect`, never at launch.

To keep receiving scans while the app is in the background (screen locked, another app open), also declare the
Bluetooth background mode; see [Background](#background).

## Quick start

```dart
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';

final netum = NetumScanner.instance;

// 1. One global listener for every scanner.
netum.scans.listen((scan) => print('${scan.device.name}: ${scan.text}'));

// 2. Permissions (Android's runtime prompts; iOS's Bluetooth prompt).
if (await netum.checkPermissions() != PermissionStatus.granted) {
  await netum.requestPermissions();
}

// 3. Find a scanner and connect.
await for (final found in netum.discover()) {
  await netum.connect(found.id, transport: found.transport, name: found.name);
  break; // Leaving the loop stops discovery.
}
```

`scan.text` is the barcode without its terminator (CR/LF/TAB); `scan.raw` has the bytes as received.

## Multiple scanners

Connect as many as you need (default limit: `maxConnections = 7`). Every scan carries the `NetumDevice` that
read it, so you can answer the right scanner:

```dart
netum.scans.listen((scan) async {
  final ok = await inventory.accept(scan.text);
  if (!ok) await scan.device.beep(3); // Only that scanner beeps.
});

// Or listen to one scanner only:
device.scans.listen(...);

// Connection changes for every scanner:
netum.connectionEvents.listen((e) => print('${e.device.id}: ${e.state} ${e.reason ?? ''}'));
```

The `id` identifies a scanner (Android: its MAC for that transport; iOS: a per-phone UUID). Names are not
unique, since units ship with identical names; give each one its own with `device.setName('Netum-01')`.

## Saved devices and auto-reconnect

Two separate features:

**Auto-reconnect** (the link drops while the app runs): opt in per connection.

```dart
await netum.connect(id, transport: NetumTransport.ble, autoReconnect: true);
// Out of range / powered off / asleep → `reconnecting` → `connected` on the same handle.
// Gives up after 30 minutes by default: ReconnectPolicy(giveUpAfter: ...).
// disconnect() never reconnects.
```

**Saved scanners** (restore at startup, like a car radio): every successful `connect()` is remembered
(most recent first, with its reconnect settings) unless `remember: false`. The plugin never reconnects
saved scanners on its own; call `restoreSaved` when your app is ready:

```dart
// The most recent scanner that is in range:
final restored = await netum.restoreSaved();
// Or every saved scanner, up to maxConnections:
await netum.restoreSaved(strategy: RestoreStrategy.all);

final saved = await netum.savedScanners();
await netum.forgetScanner(saved.first.id);
```

`restoreSaved` skips saved SPP scanners that the phone is no longer paired with (forgotten in the Bluetooth
settings), so no pairing prompt appears at startup; they stay saved and come back once paired again.

The list is stored natively (SharedPreferences / UserDefaults). To use your own storage, set
`netum.store` to a `NetumStore` before the first connect.

## Background

The connection stays up when the user locks the screen or switches apps, and scans keep reaching your `scans`
listeners: a screen that is still in the navigation stack keeps its subscription, so your handler runs (Flutter
draws the result when the app returns).

| | What happens to scans while the app is in the background |
|---|---|
| **Android** | Works out of the box. Delivered live; after about a minute Android may freeze the app, and scans made while it is frozen are queued and delivered in order when the app returns. |
| **iOS** | Needs the Bluetooth background mode, otherwise scans made while the app isn't on screen are **lost** (iOS suspends the app within seconds). With it, iOS wakes the app for each scan and delivers it live. |

iOS setup, in `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
</array>
```

App Store review asks apps that declare it to explain why; a barcode scanner app is a standard case.

Limits:

- Nothing survives the OS ending the app (memory pressure, the user swiping it away). The scanner disconnects;
  use [saved scanners](#saved-devices-and-auto-reconnect) to reconnect on the next launch.
- On Android, scans queued while the app was frozen arrive when it returns, so their `timestamp` is the return
  time, not the scan time.

Tested on a Samsung A24 (Android 16) and an iPhone 16 Pro Max (iOS 26): locked screen, another app in front, and
about 10 minutes on the home screen.

## Commands

Typed helpers on `NetumDevice` cover the common needs:

```dart
await device.triggerScan(seconds: 3);                   // Fire the scan engine from the app (1–7 s).
await device.beep();                                     // Preset sounds 0–26.
final battery = await device.getBattery();               // Voltage and percent.
await device.setVolume(BeepVolume.low);
await device.setScanMode(ScanMode.trigger);
await device.setSleepTimeout(SleepTimeout.minutes30);
final info = await device.getDeviceInfo();               // Bluetooth module, firmware, Classic MAC.
```

Everything else is in the `NetumCommand` catalog (`system`, `workMode`, `power`, `feedback`, `scan`, `format`,
`keyboard`), sent with `device.send(...)`. `device.sendRaw('...')` sends free text for commands the catalog
doesn't have yet. One command runs at a time per scanner; the others wait in a queue.

> ⚠️ **Dangerous commands** live under `NetumCommand.dangerous.*`: mode switches, factory resets, clearing the
> pairing, USB / 2.4 GHz settings. They can drop the connection or leave the scanner in a mode this plugin can't
> reach (HID, USB). `device.switchMode(...)` is the only typed one; it turns auto-reconnect off first, because
> the scanner restarts in the new mode with a different id.

## SPP pairing (Android)

**Default flow:** put the scanner in SPP mode, then discover and connect. Android shows its pairing prompt
the first time; after that the scanner reconnects directly (about 1 s), also from the saved list.

```dart
await for (final s in netum.discover(transport: NetumTransport.spp)) {
  await netum.connect(s.id, transport: NetumTransport.spp, name: s.name);
  break;
}
```

`netum.bondedScanners()` lists the scanners already paired with the phone, without discovery.

**Pair by scanning** (optional, the vendor's flow): the phone listens and the scanner dials in after
scanning a barcode that contains the phone's Bluetooth MAC. Apps cannot read that MAC on Android 6+, so
the user types it from **Settings → About phone → Status → Bluetooth address**.

```dart
final data = NetumScanner.sppPairingBarcodeData('88:BD:45:33:5E:2C'); // AT+SPPCONN=88BD45335E2C
// Show `data` as a Code 128 barcode, then:
final scanner = await netum.listenForSppScanner().first;
await netum.connect(scanner.id, transport: NetumTransport.spp);
```

**If the scanner was paired with any phone before**, power-cycle it first (or scan `AT+MODE=2`, then
`AT+MODE=1`). Forgetting the scanner in the phone's Bluetooth settings removes only the phone's half of the
pairing; the scanner keeps its own and hangs up right after dialling in. After the power-cycle, the scanner
dials in, Android shows its pairing prompt, and the plugin connects. Once paired this way, the
default flow keeps working even if the phone later forgets the scanner.

## Debugging with `traffic`

Turn on the traffic log to see every packet, both ways, already classified:

```dart
netum.trafficLogEnabled = true;
netum.traffic.listen((t) => debugPrint('$t'));
// TrafficEvent(DD:0D:30:60:B4:2C outbound command "...")
// TrafficEvent(DD:0D:30:60:B4:2C inbound ack)
// TrafficEvent(DD:0D:30:60:B4:2C inbound barcode "7771609001660")
```

Each event has the direction, the bytes, the decoded text and a `PacketKind` (`command`, `ack`, `echo`, `reply`,
`barcode`, `unknown`). It is off by default.

## HID mode

In HID (keyboard) mode the scanner types barcodes into the focused text field, with no app connection, so this
plugin doesn't apply. For HID scanners, see [`barcode_hid_listener`](https://pub.dev/packages/barcode_hid_listener).

## FAQ

**Android connect fails with status 133.** A generic Android BLE error, usually transient. The plugin already
retries once by itself; if the retry fails too, you get `NetumConnectionFailed` with `platformCode: 133`. Try
again, and if it keeps happening, turn Bluetooth off and on.

**Discovery finds nothing on Android.** Check that the Location setting is on (`NetumLocationServicesOff`) and the
Location permission is granted. A scanner connected to another phone usually stops advertising.

**All my scanners have the same name.** Units ship with identical names. The `id` is what identifies a scanner;
give each one a name with `device.setName(...)`.

**An SPP scanner hangs up or won't pair after the phone forgot it.** The scanner still holds its half of the old
pairing. Power-cycle it, or scan `AT+MODE=2` then `AT+MODE=1`, and pair again.

**A scan arrived with the wrong number.** Barcode check digits catch most misreads, not all: a damaged or
blurry code can decode to another valid number. Validate critical codes against your own data (for example
your product catalog).

**Does it work in the background?** Yes, while the OS keeps the app running. On iOS, declare the Bluetooth
background mode. See [Background](#background).

## Documentation

- [Using the example app](doc/example_app.md): every control in the example, the API behind it, and what a DS5000
  actually does
- [Wire protocol](doc/protocol.md)
- [Command catalog](doc/commands.md)

## License

MIT. See [LICENSE](LICENSE).
