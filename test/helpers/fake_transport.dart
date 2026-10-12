import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

/// A scriptable native side: records calls, lets tests push events.
class FakeTransport extends Fake implements NetumTransportApi {
  final adapterStateController = StreamController<AdapterStateMsg>.broadcast();
  final discoveryController = StreamController<DiscoveredDeviceMsg>.broadcast();
  final linkController = StreamController<LinkStateMsgEvent>.broadcast();
  final dataController = StreamController<DataMsg>.broadcast();

  final writes = <(String, Uint8List)>[];
  final connects = <String>[];
  final disconnects = <String>[];
  final discoveryStarts = <DiscoveryOptionsMsg>[];
  int discoveryStops = 0;
  int initializeCalls = 0;

  List<ActiveLinkMsg> activeLinks = [];
  AdapterStateMsg currentAdapterState = AdapterStateMsg.poweredOn;

  /// Thrown by [connect] instead of succeeding.
  NetumException? connectError;

  /// Thrown by [startDiscovery].
  NetumException? discoveryError;

  /// Whether [connect] also emits the native link events.
  bool emitLinkEvents = true;

  void link(String id, LinkStateMsg state, {bool user = false, int? code}) =>
      linkController.add(
        LinkStateMsgEvent(
          id: id,
          transport: TransportMsg.ble,
          state: state,
          userInitiated: user,
          platformCode: code,
        ),
      );

  void receive(String id, List<int> bytes) => dataController.add(
    DataMsg(id: id, bytes: Uint8List.fromList(bytes), timestampMicros: 0),
  );

  void found(String id, {String? name, int? rssi, List<String>? uuids}) =>
      discoveryController.add(
        DiscoveredDeviceMsg(
          id: id,
          transport: TransportMsg.ble,
          name: name,
          rssi: rssi,
          bonded: false,
          serviceUuids: uuids ?? ['0000FFF0-0000-1000-8000-00805F9B34FB'],
        ),
      );

  @override
  Stream<AdapterStateMsg> get adapterStates => adapterStateController.stream;

  @override
  Stream<DiscoveredDeviceMsg> get discoveries => discoveryController.stream;

  @override
  Stream<LinkStateMsgEvent> get linkStates => linkController.stream;

  @override
  Stream<DataMsg> get data => dataController.stream;

  @override
  Future<List<ActiveLinkMsg>> initialize() async {
    initializeCalls++;
    return activeLinks;
  }

  @override
  Future<AdapterStateMsg> adapterState() async => currentAdapterState;

  @override
  Future<PermissionResultMsg> checkPermissions(
    PermissionScopeMsg scope,
  ) async => PermissionResultMsg.denied;

  @override
  Future<PermissionResultMsg> requestPermissions(
    PermissionScopeMsg scope,
  ) async => PermissionResultMsg.granted;

  @override
  Future<void> connect(String id, ConnectOptionsMsg options) async {
    connects.add(id);
    if (emitLinkEvents) link(id, LinkStateMsg.connecting, user: true);
    if (connectError case final error?) {
      if (emitLinkEvents) {
        link(id, LinkStateMsg.disconnected, code: 133);
      }
      throw error;
    }
    if (emitLinkEvents) link(id, LinkStateMsg.connected, user: true);
  }

  @override
  Future<void> disconnect(String id) async {
    disconnects.add(id);
    link(id, LinkStateMsg.disconnecting, user: true);
    link(id, LinkStateMsg.disconnected, user: true);
  }

  @override
  Future<void> write(String id, Uint8List bytes) async =>
      writes.add((id, bytes));

  @override
  Future<int> readRssi(String id) async => -48;

  @override
  Future<void> startDiscovery(DiscoveryOptionsMsg options) async {
    discoveryStarts.add(options);
    if (discoveryError case final error?) throw error;
  }

  @override
  Future<void> stopDiscovery() async => discoveryStops++;
}
