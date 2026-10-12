import 'dart:typed_data';

import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';

/// The native side of the plugin as seen by the Dart layer: raw byte pipes
/// plus connection facts, with no protocol knowledge.
///
/// `PigeonTransport` talks to the platform; tests use a fake.
abstract interface class NetumTransportApi {
  /// Prepares the native side and returns the links that survived a hot
  /// restart.
  Future<List<ActiveLinkMsg>> initialize();

  /// The current Bluetooth adapter state.
  Future<AdapterStateMsg> adapterState();

  /// Whether the permissions for [scope] are granted, without prompting.
  Future<PermissionResultMsg> checkPermissions(PermissionScopeMsg scope);

  /// Prompts for the permissions of [scope] when needed.
  Future<PermissionResultMsg> requestPermissions(PermissionScopeMsg scope);

  /// Asks the user to turn Bluetooth on. Returns whether it is on afterwards.
  Future<bool> requestEnableBluetooth();

  /// Starts discovery; results arrive on [discoveries].
  Future<void> startDiscovery(DiscoveryOptionsMsg options);

  /// Stops a running discovery.
  Future<void> stopDiscovery();

  /// Devices bonded with the phone (Android). Empty on iOS.
  Future<List<DiscoveredDeviceMsg>> bondedDevices();

  /// Connects to [id]; completes once the link is ready for data.
  Future<void> connect(String id, ConnectOptionsMsg options);

  /// Disconnects [id].
  Future<void> disconnect(String id);

  /// Turns automatic reconnection for [id] on or off.
  Future<void> setAutoReconnect(String id, {required bool enabled});

  /// Writes [bytes] to [id]; completes on the platform's write callback.
  Future<void> write(String id, Uint8List bytes);

  /// Reads a GATT characteristic of [id] (BLE only).
  Future<Uint8List> readCharacteristic(
    String id,
    String serviceUuid,
    String characteristicUuid,
  );

  /// Reads the signal strength of [id].
  Future<int> readRssi(String id);

  /// Starts the SPP "pair by scanning" listener (Android).
  Future<void> startSppListener(int timeoutMs);

  /// Stops the SPP listener.
  Future<void> stopSppListener();

  /// Adapter state changes. The current state is emitted on subscription.
  Stream<AdapterStateMsg> get adapterStates;

  /// Devices found by discovery.
  Stream<DiscoveredDeviceMsg> get discoveries;

  /// Link state changes of every device.
  Stream<LinkStateMsgEvent> get linkStates;

  /// Raw inbound bytes of every device.
  Stream<DataMsg> get data;
}
