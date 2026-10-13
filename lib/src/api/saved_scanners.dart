import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:netum_bluetooth_scanner/src/api/models.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

/// A scanner remembered after a successful connect, with its reconnect
/// settings.
@immutable
class SavedScanner {
  /// Creates a saved scanner.
  const SavedScanner({
    required this.id,
    required this.transport,
    required this.lastConnected,
    this.name,
    this.autoReconnect = false,
    this.reconnectPolicy = const ReconnectPolicy(),
  });

  /// Restores an entry written by [toJson].
  factory SavedScanner.fromJson(Map<String, Object?> json) {
    final giveUpMs = json['giveUpAfterMs'] as int?;
    return SavedScanner(
      id: json['id']! as String,
      transport: NetumTransport.values.byName(json['transport']! as String),
      name: json['name'] as String?,
      lastConnected:
          DateTime.tryParse(json['lastConnected'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      autoReconnect: json['autoReconnect'] as bool? ?? false,
      reconnectPolicy: json['unlimited'] == true
          ? ReconnectPolicy.unlimited
          : ReconnectPolicy(
              giveUpAfter: giveUpMs == null
                  ? const Duration(minutes: 30)
                  : Duration(milliseconds: giveUpMs),
            ),
    );
  }

  /// The platform id (Android MAC, iOS identifier UUID).
  final String id;

  /// The transport it was connected over.
  final NetumTransport transport;

  /// The last known name (display only: names are not unique).
  final String? name;

  /// When it last connected.
  final DateTime lastConnected;

  /// Whether to auto-reconnect it after a drop.
  final bool autoReconnect;

  /// How long auto-reconnect keeps trying.
  final ReconnectPolicy reconnectPolicy;

  /// A JSON-safe map.
  Map<String, Object?> toJson() => {
    'id': id,
    'transport': transport.name,
    'name': name,
    'lastConnected': lastConnected.toIso8601String(),
    'autoReconnect': autoReconnect,
    if (reconnectPolicy.giveUpAfter == null)
      'unlimited': true
    else
      'giveUpAfterMs': reconnectPolicy.giveUpAfter!.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is SavedScanner &&
      other.id == id &&
      other.transport == transport &&
      other.name == name &&
      other.lastConnected == lastConnected &&
      other.autoReconnect == autoReconnect &&
      other.reconnectPolicy == reconnectPolicy;

  @override
  int get hashCode => Object.hash(
    id,
    transport,
    name,
    lastConnected,
    autoReconnect,
    reconnectPolicy,
  );

  @override
  String toString() => 'SavedScanner($id, $name, $lastConnected)';
}

/// How `NetumScanner.restoreSaved` reconnects saved scanners.
enum RestoreStrategy {
  /// Like a car radio: try the most recently connected scanner, then the
  /// next, until one connects.
  firstAvailable,

  /// Reconnect every saved scanner, up to `NetumScanner.maxConnections`.
  all,
}

/// Where the saved-scanner list lives. The default stores it natively
/// (Android SharedPreferences, iOS UserDefaults); apps can provide their own
/// (e.g. encrypted or synced storage).
abstract interface class NetumStore {
  /// The stored JSON, or `null` if nothing was saved.
  Future<String?> load();

  /// Replaces the stored JSON.
  Future<void> save(String json);
}

/// The default [NetumStore]: native key-value storage.
@internal
class NativeNetumStore implements NetumStore {
  /// Stores through [transport].
  NativeNetumStore(this.transport);

  /// The native side.
  final NetumTransportApi transport;

  @override
  Future<String?> load() => transport.loadSavedScanners();

  @override
  Future<void> save(String json) => transport.saveSavedScanners(json);
}

/// Decodes a stored list, most recent first; corrupt data reads as empty.
@internal
List<SavedScanner> decodeSavedScanners(String? json) {
  if (json == null || json.isEmpty) return [];
  try {
    final list = [
      for (final entry in jsonDecode(json) as List<Object?>)
        SavedScanner.fromJson(entry! as Map<String, Object?>),
    ]..sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
    return list;
  } on Object {
    return [];
  }
}

/// Encodes a list for storage.
@internal
String encodeSavedScanners(List<SavedScanner> scanners) =>
    jsonEncode([for (final s in scanners) s.toJson()]);
