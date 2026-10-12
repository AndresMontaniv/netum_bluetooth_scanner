import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:netum_bluetooth_scanner/src/api/netum_device.dart';
import 'package:netum_bluetooth_scanner/src/commands/netum_command.dart';

/// How the phone talks to a scanner.
enum NetumTransport {
  /// Bluetooth Low Energy (Android and iOS).
  ble,

  /// Serial Port Profile over Classic Bluetooth (Android only).
  spp,
}

/// The connection state of a [NetumDevice].
enum NetumConnectionState {
  /// Not connected.
  disconnected,

  /// Connecting (link, services, notifications).
  connecting,

  /// Connected and ready for data.
  connected,

  /// Waiting to reconnect after the link was lost.
  reconnecting,

  /// Disconnecting at the user's request.
  disconnecting,
}

/// Which permissions a call needs.
enum PermissionScope {
  /// Finding scanners: Bluetooth scan permission plus Location on Android.
  discovery,

  /// Connecting to a known scanner: no Location needed.
  connection,
}

/// The outcome of a permission check or request.
enum PermissionStatus {
  /// Everything needed is granted.
  granted,

  /// Not granted yet; asking may help.
  denied,

  /// Denied in a way the app can no longer ask about; the user has to grant
  /// it in Settings.
  permanentlyDenied,

  /// Nothing is needed on this platform version.
  notRequired,
}

/// Which devices discovery reports.
enum DiscoveryFilter {
  /// Only devices that look like NETUM scanners.
  likelyNetum,

  /// Everything nearby.
  all,
}

/// A scanner found by discovery.
@immutable
class DiscoveredScanner {
  /// Creates a discovery result.
  const DiscoveredScanner({
    required this.id,
    required this.transport,
    required this.bonded,
    required this.likelyNetum,
    required this.serviceUuids,
    required this.lastSeen,
    this.name,
    this.rssi,
  });

  /// Restores a result saved with [toJson], e.g. a remembered scanner.
  factory DiscoveredScanner.fromJson(Map<String, Object?> json) =>
      DiscoveredScanner(
        id: json['id']! as String,
        transport: NetumTransport.values.byName(json['transport']! as String),
        name: json['name'] as String?,
        rssi: json['rssi'] as int?,
        bonded: json['bonded'] as bool? ?? false,
        likelyNetum: json['likelyNetum'] as bool? ?? true,
        serviceUuids: [
          for (final uuid in json['serviceUuids'] as List<Object?>? ?? [])
            uuid! as String,
        ],
        lastSeen:
            DateTime.tryParse(json['lastSeen'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// The platform id: the MAC of this transport on Android, a per-phone
  /// UUID on iOS. Pass it to `NetumScanner.device`.
  final String id;

  /// The transport this result was found on.
  final NetumTransport transport;

  /// The advertised or bonded name, if known.
  final String? name;

  /// Signal strength in dBm, if known.
  final int? rssi;

  /// Whether the phone is paired with it.
  final bool bonded;

  /// Whether it looks like a NETUM scanner (BLE: advertises FFF0, FF00 or
  /// 18F0).
  final bool likelyNetum;

  /// Advertised service UUIDs.
  final List<String> serviceUuids;

  /// When it was last seen.
  final DateTime lastSeen;

  /// A JSON-safe map, e.g. to remember a scanner between runs.
  Map<String, Object?> toJson() => {
    'id': id,
    'transport': transport.name,
    'name': name,
    'rssi': rssi,
    'bonded': bonded,
    'likelyNetum': likelyNetum,
    'serviceUuids': serviceUuids,
    'lastSeen': lastSeen.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is DiscoveredScanner &&
      other.id == id &&
      other.transport == transport &&
      other.name == name &&
      other.rssi == rssi &&
      other.bonded == bonded &&
      other.likelyNetum == likelyNetum &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode =>
      Object.hash(id, transport, name, rssi, bonded, likelyNetum, lastSeen);

  @override
  String toString() => 'DiscoveredScanner($id, $name, rssi: $rssi)';
}

/// A barcode read by a scanner.
@immutable
class ScanEvent {
  /// Creates a scan event.
  const ScanEvent({
    required this.device,
    required this.text,
    required this.raw,
    required this.timestamp,
  });

  /// The scanner that read it.
  final NetumDevice device;

  /// The scanner's id (same as `device.id`).
  String get deviceId => device.id;

  /// The barcode text, without the terminator.
  final String text;

  /// The bytes as received, terminator included.
  final Uint8List raw;

  /// When it arrived.
  final DateTime timestamp;

  @override
  String toString() => 'ScanEvent($deviceId: $text)';
}

/// A change of a device's connection state.
@immutable
class ConnectionEvent {
  /// Creates a connection event.
  const ConnectionEvent({
    required this.device,
    required this.state,
    this.reason,
  });

  /// The device whose state changed.
  final NetumDevice device;

  /// The device's id (same as `device.id`).
  String get deviceId => device.id;

  /// The new state.
  final NetumConnectionState state;

  /// Why the device disconnected, for [NetumConnectionState.disconnected].
  final DisconnectReason? reason;

  @override
  String toString() =>
      'ConnectionEvent($deviceId: ${state.name}'
      '${reason == null ? '' : ', $reason'})';
}

/// Why a device disconnected.
sealed class DisconnectReason {
  const DisconnectReason();
}

/// The app called `disconnect()`.
final class UserRequested extends DisconnectReason {
  /// Creates the reason.
  const UserRequested();

  @override
  String toString() => 'UserRequested';
}

/// The link was lost (power off, out of range).
final class LinkLost extends DisconnectReason {
  /// Creates the reason with the platform status.
  const LinkLost([this.platformCode]);

  /// Android GATT status (8) or iOS CBError code (6), if any.
  final int? platformCode;

  @override
  String toString() => 'LinkLost($platformCode)';
}

/// Bluetooth was turned off.
final class BluetoothOff extends DisconnectReason {
  /// Creates the reason.
  const BluetoothOff();

  @override
  String toString() => 'BluetoothOff';
}

/// The scanner closed the connection (e.g. right after a rename).
final class RemoteTerminated extends DisconnectReason {
  /// Creates the reason with the platform status.
  const RemoteTerminated([this.platformCode]);

  /// Android GATT status (19) or iOS CBError code (7), if any.
  final int? platformCode;

  @override
  String toString() => 'RemoteTerminated($platformCode)';
}

/// Connecting failed.
final class ConnectFailed extends DisconnectReason {
  /// Creates the reason.
  const ConnectFailed({this.platformCode, this.message});

  /// The platform status, e.g. Android GATT status 133.
  final int? platformCode;

  /// The platform's description, if any.
  final String? message;

  @override
  String toString() => 'ConnectFailed($platformCode, $message)';
}

/// A command that drops the link (rename, power off, mode switch) was
/// accepted.
final class ExpectedAfterCommand extends DisconnectReason {
  /// Creates the reason for [command].
  const ExpectedAfterCommand(this.command);

  /// The command that caused the disconnect.
  final NetumCommand command;

  @override
  String toString() => 'ExpectedAfterCommand(${command.ascii})';
}

/// Identity read from the scanner's Device Information Service (BLE, no
/// scanner command needed).
@immutable
class DeviceInfo {
  /// Creates device information.
  const DeviceInfo({
    this.manufacturer,
    this.model,
    this.serial,
    this.hardwareRevision,
    this.firmwareRevision,
    this.classicAddress,
  });

  /// Manufacturer name, e.g. `Feasycom` (the Bluetooth module's maker).
  final String? manufacturer;

  /// Model, e.g. `FSC-BT825`.
  final String? model;

  /// Serial number. On the DS5000 this is the Classic Bluetooth MAC.
  final String? serial;

  /// Hardware revision, e.g. `1.1`.
  final String? hardwareRevision;

  /// Firmware (software) revision of the Bluetooth module, e.g. `1.6.2`.
  final String? firmwareRevision;

  /// The Classic Bluetooth MAC (`DC:0D:30:…`), when the serial is one. It is
  /// the same in BLE and SPP mode, and visible on iOS, which hides MACs.
  final String? classicAddress;

  @override
  String toString() =>
      'DeviceInfo($manufacturer $model, serial: $serial, '
      'hw: $hardwareRevision, fw: $firmwareRevision)';
}
