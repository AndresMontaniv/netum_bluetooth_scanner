// Pigeon contract between the Dart layer and the native byte pipes.
// Regenerate with: dart run pigeon --input pigeons/netum_api.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'netum_bluetooth_scanner',
    dartOut: 'lib/src/generated/netum_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/dev/andresmontano/netum_bluetooth_scanner/generated/NetumApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'dev.andresmontano.netum_bluetooth_scanner.generated',
    ),
    swiftOut:
        'ios/netum_bluetooth_scanner/Sources/netum_bluetooth_scanner/Generated/NetumApi.g.swift',
  ),
)
enum TransportMsg { ble, spp }

enum AdapterStateMsg {
  unknown,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn,
  locationServicesOff,
}

enum LinkStateMsg { disconnected, connecting, connected, disconnecting }

enum PermissionScopeMsg { discovery, connection }

enum PermissionResultMsg { granted, denied, permanentlyDenied, notRequired }

class DiscoveredDeviceMsg {
  DiscoveredDeviceMsg({
    required this.id,
    required this.transport,
    required this.bonded,
    required this.serviceUuids,
    this.name,
    this.rssi,
  });

  String id;
  TransportMsg transport;
  String? name;
  int? rssi;
  bool bonded;
  List<String> serviceUuids;
}

class LinkStateMsgEvent {
  LinkStateMsgEvent({
    required this.id,
    required this.transport,
    required this.state,
    required this.userInitiated,
    this.platformCode,
    this.message,
  });

  String id;
  TransportMsg transport;
  LinkStateMsg state;
  int? platformCode;
  bool userInitiated;
  String? message;
}

class DataMsg {
  DataMsg({
    required this.id,
    required this.bytes,
    required this.timestampMicros,
  });

  String id;
  Uint8List bytes;
  int timestampMicros;
}

class DiscoveryOptionsMsg {
  DiscoveryOptionsMsg({
    required this.transport,
    required this.filterNetum,
    required this.timeoutMs,
  });

  TransportMsg transport;
  bool filterNetum;
  int timeoutMs;
}

class ConnectOptionsMsg {
  ConnectOptionsMsg({
    required this.transport,
    required this.timeoutMs,
    required this.autoReconnect,
    required this.sppInsecureFallback,
  });

  TransportMsg transport;
  int timeoutMs;
  bool autoReconnect;
  bool sppInsecureFallback;
}

class ActiveLinkMsg {
  ActiveLinkMsg({required this.id, required this.transport, this.name});

  String id;
  TransportMsg transport;
  String? name;
}

@HostApi()
abstract class NetumHostApi {
  /// Returns the links that survived a hot restart.
  List<ActiveLinkMsg> initialize();

  AdapterStateMsg adapterState();

  PermissionResultMsg checkPermissions(PermissionScopeMsg scope);

  @async
  PermissionResultMsg requestPermissions(PermissionScopeMsg scope);

  @async
  bool requestEnableBluetooth();

  void startDiscovery(DiscoveryOptionsMsg options);

  void stopDiscovery();

  /// Android only; iOS returns an empty list.
  List<DiscoveredDeviceMsg> bondedDevices();

  /// Completes when the link is READY (notifications enabled).
  @async
  void connect(String id, ConnectOptionsMsg options);

  @async
  void disconnect(String id);

  // Kept positional to match the B4 contract.
  // ignore: avoid_positional_boolean_parameters
  void setAutoReconnect(String id, bool enabled);

  /// Completes on the platform's write callback.
  @async
  void write(String id, Uint8List bytes);

  /// BLE only (Device Information Service, 180A).
  @async
  Uint8List readCharacteristic(
    String id,
    String serviceUuid,
    String characteristicUuid,
  );

  @async
  int readRssi(String id);

  /// Android only.
  void startSppListener(int timeoutMs);

  void stopSppListener();
}

@EventChannelApi()
abstract class NetumEventApi {
  AdapterStateMsg adapterStates();

  DiscoveredDeviceMsg discoveries();

  LinkStateMsgEvent linkStates();

  DataMsg data();
}
