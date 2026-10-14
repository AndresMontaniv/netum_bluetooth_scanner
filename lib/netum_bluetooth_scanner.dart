/// Flutter plugin for NETUM Bluetooth barcode scanners: BLE on Android and
/// iOS, SPP (Classic Bluetooth) on Android.
///
/// Start with `NetumScanner.instance`: it finds scanners (`discover`),
/// connects them (`connect`) and reports every barcode on one stream
/// (`scans`). Each connected scanner is a `NetumDevice` with its own streams
/// and typed commands.
///
/// ```dart
/// final netum = NetumScanner.instance;
/// netum.scans.listen((scan) => print('${scan.device.name}: ${scan.text}'));
///
/// await netum.requestPermissions();
/// await for (final found in netum.discover()) {
///   await netum.connect(found.id, transport: found.transport);
///   break;
/// }
/// ```
///
/// Errors are `NetumException` subclasses. See the README for platform setup,
/// SPP pairing, auto-reconnect and saved scanners.
library;

export 'src/api/models.dart';
export 'src/api/netum_device.dart' show NetumDevice;
export 'src/api/netum_scanner.dart';
export 'src/api/saved_scanners.dart'
    show NetumStore, RestoreStrategy, SavedScanner;
export 'src/commands/command_options.dart';
export 'src/commands/command_result.dart';
export 'src/commands/netum_command.dart';
export 'src/errors.dart';
export 'src/models/adapter_state.dart';
export 'src/models/battery_info.dart';
