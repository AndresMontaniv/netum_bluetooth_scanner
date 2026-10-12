import 'package:netum_bluetooth_scanner/src/models/battery_info.dart';

// Parsers for decoded reply text (terminator and NUL bytes already
// stripped). Each returns null when the text does not match.

final _battery = RegExp(r'^BAT_VOL=(\d+(?:\.\d+)?)V\s+(\d+)%$');
final _storedCount = RegExp(r'^Total Counters=(\d+)$');
final _sleep = RegExp(r'^Sleeptime=(\d+)(min|h)$');
final _name = RegExp(r'^\+NAME=(.*)$');
final _address = RegExp(r'^\+ADDR=([0-9A-F]{12})$');
final _version = RegExp(r'^\+VER=(.*)$');

/// Parses `BAT_VOL=3.81V 37%`.
BatteryInfo? parseBattery(String reply) {
  final match = _battery.firstMatch(reply);
  if (match == null) return null;
  return BatteryInfo(
    voltage: double.parse(match[1]!),
    percent: int.parse(match[2]!),
    raw: reply,
  );
}

/// Parses `Total Counters=0`.
int? parseStoredCount(String reply) {
  final match = _storedCount.firstMatch(reply);
  return match == null ? null : int.parse(match[1]!);
}

/// Parses `Sleeptime=30min` or `Sleeptime=1h`.
Duration? parseSleepTimeout(String reply) {
  final match = _sleep.firstMatch(reply);
  if (match == null) return null;
  final value = int.parse(match[1]!);
  return match[2] == 'h' ? Duration(hours: value) : Duration(minutes: value);
}

/// Parses `+NAME=DS barcode scanner`.
String? parseBluetoothName(String reply) => _name.firstMatch(reply)?[1];

/// Parses `+ADDR=DC0D3060B42C` into `DC:0D:30:60:B4:2C`.
String? parseBluetoothAddress(String reply) {
  final hex = _address.firstMatch(reply)?[1];
  if (hex == null) return null;
  return [
    for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2),
  ].join(':');
}

/// Parses `+VER=1.6.2`.
String? parseBluetoothFirmware(String reply) => _version.firstMatch(reply)?[1];
