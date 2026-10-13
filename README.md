# netum_bluetooth_scanner

Flutter plugin for NETUM Bluetooth barcode scanners: BLE on Android and iOS, SPP (Classic Bluetooth) on Android. Scan streams, several scanners at once, and typed commands.

> **Not affiliated with or endorsed by NETUM.** "NETUM" is used only to identify the hardware this plugin talks to.

> **Status: in development.** There is no public API yet; the first release will be `0.1.0`.

## What it is / isn't

_To be written._

## Compatibility

_To be written._

## Install

_To be written._

### Android setup

_To be written._

### iOS setup

_To be written._

## Quick start

_To be written._

## Multiple scanners

_To be written._

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

The list is stored natively (SharedPreferences / UserDefaults). To use your own storage, set
`netum.store` to a `NetumStore` before the first connect.

## Commands

_To be written._

## SPP pairing (Android)

**Default flow:** put the scanner in SPP mode, then discover and connect. Android shows its pairing prompt
the first time; after that the scanner reconnects directly (about 1 s), also from the saved list.

```dart
await for (final s in netum.discover(transport: NetumTransport.spp)) {
  await netum.connect(s.id, transport: NetumTransport.spp, name: s.name);
  break;
}
```

**Pair by scanning** (optional, the vendor's flow): the phone listens and the scanner dials in after
scanning a barcode that contains the phone's Bluetooth MAC. Apps cannot read that MAC on Android 6+, so
the user types it from **Settings → About phone → Status → Bluetooth address**.

```dart
final data = NetumScanner.sppPairingBarcodeData('BC:10:7B:D4:9B:C5'); // AT+SPPCONN=BC107BD49BC5
// Show `data` as a Code 128 barcode, then:
final scanner = await netum.listenForSppScanner().first;
await netum.connect(scanner.id, transport: NetumTransport.spp);
```

## Debugging with `traffic`

_To be written._

## HID mode

_To be written._

## FAQ

_To be written._

## Protocol documentation

- [Wire protocol](doc/protocol.md)
- [Command catalog](doc/commands.md)

## License

MIT. See [LICENSE](LICENSE).
