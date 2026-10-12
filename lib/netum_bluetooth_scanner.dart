/// Flutter plugin for NETUM Bluetooth barcode scanners: BLE on Android and
/// iOS, SPP (Classic Bluetooth) on Android.
library;

export 'src/api/models.dart';
export 'src/api/netum_device.dart' show NetumDevice;
export 'src/api/netum_scanner.dart';
export 'src/commands/command_options.dart';
export 'src/commands/command_result.dart';
export 'src/commands/netum_command.dart';
export 'src/errors.dart';
export 'src/models/adapter_state.dart';
export 'src/models/battery_info.dart';
