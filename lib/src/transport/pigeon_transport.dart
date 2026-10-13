import 'dart:async';

import 'package:flutter/services.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart'
    as native
    show adapterStates, data, discoveries, linkStates;
import 'package:netum_bluetooth_scanner/src/transport/platform_errors.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

/// [NetumTransportApi] backed by the Pigeon-generated channels.
///
/// A native event channel has a single sink, so each native stream is
/// subscribed at most once and re-broadcast to any number of Dart listeners.
/// Native errors surface as `NetumException`s.
/// The native subscription starts with the first listener and ends with the
/// last.
class PigeonTransport implements NetumTransportApi {
  /// Creates a transport. The parameters exist for tests.
  PigeonTransport({
    NetumHostApi? hostApi,
    Stream<AdapterStateMsg> Function()? adapterStates,
    Stream<DiscoveredDeviceMsg> Function()? discoveries,
    Stream<LinkStateMsgEvent> Function()? linkStates,
    Stream<DataMsg> Function()? data,
  }) : _host = hostApi ?? NetumHostApi(),
       _adapterStates = _SharedStream(adapterStates ?? native.adapterStates),
       _discoveries = _SharedStream(discoveries ?? native.discoveries),
       _linkStates = _SharedStream(linkStates ?? native.linkStates),
       _data = _SharedStream(data ?? native.data);

  final NetumHostApi _host;
  final _SharedStream<AdapterStateMsg> _adapterStates;
  final _SharedStream<DiscoveredDeviceMsg> _discoveries;
  final _SharedStream<LinkStateMsgEvent> _linkStates;
  final _SharedStream<DataMsg> _data;

  @override
  Future<List<ActiveLinkMsg>> initialize() => guardPlatform(_host.initialize);

  @override
  Future<AdapterStateMsg> adapterState() => guardPlatform(_host.adapterState);

  @override
  Future<PermissionResultMsg> checkPermissions(PermissionScopeMsg scope) =>
      guardPlatform(() => _host.checkPermissions(scope));

  @override
  Future<PermissionResultMsg> requestPermissions(PermissionScopeMsg scope) =>
      guardPlatform(() => _host.requestPermissions(scope));

  @override
  Future<bool> requestEnableBluetooth() =>
      guardPlatform(_host.requestEnableBluetooth);

  @override
  Future<void> startDiscovery(DiscoveryOptionsMsg options) =>
      guardPlatform(() => _host.startDiscovery(options));

  @override
  Future<void> stopDiscovery() => guardPlatform(_host.stopDiscovery);

  @override
  Future<List<DiscoveredDeviceMsg>> bondedDevices() =>
      guardPlatform(_host.bondedDevices);

  @override
  Future<void> connect(String id, ConnectOptionsMsg options) =>
      guardPlatform(() => _host.connect(id, options));

  @override
  Future<void> disconnect(String id) =>
      guardPlatform(() => _host.disconnect(id));

  @override
  Future<void> setAutoReconnect(String id, {required bool enabled}) =>
      guardPlatform(() => _host.setAutoReconnect(id, enabled));

  @override
  Future<void> write(String id, Uint8List bytes) =>
      guardPlatform(() => _host.write(id, bytes));

  @override
  Future<Uint8List> readCharacteristic(
    String id,
    String serviceUuid,
    String characteristicUuid,
  ) => guardPlatform(
    () => _host.readCharacteristic(id, serviceUuid, characteristicUuid),
  );

  @override
  Future<int> readRssi(String id) => guardPlatform(() => _host.readRssi(id));

  @override
  Future<void> startSppListener(int timeoutMs) =>
      guardPlatform(() => _host.startSppListener(timeoutMs));

  @override
  Future<void> stopSppListener() => guardPlatform(_host.stopSppListener);

  @override
  Future<String?> loadSavedScanners() => guardPlatform(_host.loadSavedScanners);

  @override
  Future<void> saveSavedScanners(String json) =>
      guardPlatform(() => _host.saveSavedScanners(json));

  @override
  Stream<AdapterStateMsg> get adapterStates => _adapterStates.stream;

  @override
  Stream<DiscoveredDeviceMsg> get discoveries => _discoveries.stream;

  @override
  Stream<LinkStateMsgEvent> get linkStates => _linkStates.stream;

  @override
  Stream<DataMsg> get data => _data.stream;
}

/// One native subscription shared by every Dart listener.
class _SharedStream<T> {
  _SharedStream(this._open) {
    _controller = StreamController<T>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  final Stream<T> Function() _open;
  late final StreamController<T> _controller;
  StreamSubscription<T>? _subscription;

  Stream<T> get stream => _controller.stream;

  void _start() {
    _subscription = _open().listen(
      _controller.add,
      onError: (Object error, StackTrace stackTrace) => _controller.addError(
        error is PlatformException ? mapPlatformException(error) : error,
        stackTrace,
      ),
    );
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
