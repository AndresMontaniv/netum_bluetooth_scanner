import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:netum_bluetooth_scanner/src/api/models.dart';
import 'package:netum_bluetooth_scanner/src/api/netum_device.dart';
import 'package:netum_bluetooth_scanner/src/errors.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/models/adapter_state.dart';
import 'package:netum_bluetooth_scanner/src/transport/pigeon_transport.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

/// Entry point of the plugin. A singleton that holds all state, so it is
/// safe to use from any widget or service.
///
/// ```dart
/// final netum = NetumScanner.instance;
/// netum.scans.listen((scan) => print('${scan.deviceId}: ${scan.text}'));
/// await for (final found in netum.discover()) {
///   await netum.connect(found.id, transport: found.transport);
///   break;
/// }
/// ```
class NetumScanner implements DeviceHost {
  NetumScanner._(this.transport);

  /// A scanner over a fake [transport], for tests.
  @visibleForTesting
  factory NetumScanner.withTransport(NetumTransportApi transport) =>
      NetumScanner._(transport);

  static NetumScanner? _instance;

  /// The plugin's single instance.
  // A singleton getter by design (B2): all state lives in one instance.
  // ignore: prefer_constructors_over_static_methods
  static NetumScanner get instance =>
      _instance ??= NetumScanner._(PigeonTransport());

  /// The native side.
  @override
  @internal
  final NetumTransportApi transport;

  final _devices = <String, NetumDevice>{};
  final _adapterStates = StreamController<AdapterState>.broadcast();
  final _scans = StreamController<ScanEvent>.broadcast();
  final _connectionEvents = StreamController<ConnectionEvent>.broadcast();
  final _deviceLists = StreamController<List<NetumDevice>>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void>? _initialization;
  AdapterState _adapterState = AdapterState.unknown;
  int _maxConnections = 7;
  _Discovery? _discovery;

  // region Lifecycle

  /// Syncs with the native side once: re-adopts connections that survived a
  /// Dart hot restart. Idempotent; every other call runs it implicitly.
  @override
  Future<void> initialize() => _initialization ??= _initialize().catchError(
    (Object error, StackTrace stackTrace) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    },
  );

  Future<void> _initialize() async {
    if (_subscriptions.isEmpty) {
      _subscriptions.addAll([
        transport.adapterStates.listen(_onAdapterState),
        transport.linkStates.listen(_onLinkEvent),
        transport.data.listen(_onData),
      ]);
    }
    _onAdapterState(await transport.adapterState());
    for (final link in await transport.initialize()) {
      _deviceFor(
        link.id,
        _transportOf(link.transport),
        name: link.name,
      ).adoptConnectedLink(name: link.name);
    }
  }

  /// Stops listening to the native side and closes every stream. For tests.
  @visibleForTesting
  Future<void> dispose() async {
    await _discovery?.end(stopNative: false);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _adapterStates.close();
    await _scans.close();
    await _connectionEvents.close();
    await _deviceLists.close();
  }

  // endregion

  // region Environment

  /// Adapter state changes. Broadcast; emits the current state on listen
  /// (once the native side has reported it), then every change.
  Stream<AdapterState> get adapterState => Stream.multi((controller) {
    AdapterState? last;
    void emit(AdapterState state) {
      if (state == last || controller.isClosed) return;
      last = state;
      controller.add(state);
    }

    final subscription = _adapterStates.stream.listen(
      emit,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
    unawaited(
      initialize().then(
        (_) => emit(_adapterState),
        onError: (Object error, StackTrace stackTrace) {
          if (!controller.isClosed) controller.addError(error, stackTrace);
        },
      ),
    );
  }, isBroadcast: true);

  /// The last known adapter state.
  @override
  AdapterState get currentAdapterState => _adapterState;

  /// Whether [transport] works on this platform (SPP is Android only).
  bool isSupported(NetumTransport transport) =>
      transport == NetumTransport.ble ||
      defaultTargetPlatform == TargetPlatform.android;

  /// Whether the permissions for [scope] are granted, without prompting.
  Future<PermissionStatus> checkPermissions({
    PermissionScope scope = PermissionScope.discovery,
  }) async {
    await initialize();
    return _status(await transport.checkPermissions(_scopeMsg(scope)));
  }

  /// Prompts for the permissions of [scope] if they are not granted yet.
  /// Call [checkPermissions] first and only request when needed.
  Future<PermissionStatus> requestPermissions({
    PermissionScope scope = PermissionScope.discovery,
  }) async {
    await initialize();
    return _status(await transport.requestPermissions(_scopeMsg(scope)));
  }

  /// Asks the user to turn Bluetooth on (Android system dialog). Returns
  /// whether it is on afterwards.
  Future<bool> requestEnableBluetooth() async {
    await initialize();
    return transport.requestEnableBluetooth();
  }

  // endregion

  // region Discovery

  /// Finds scanners. Results are de-duplicated by id and re-emitted when the
  /// name or signal strength changes. The stream closes after [timeout] or
  /// on [stopDiscovery]; starting a new discovery ends the previous one.
  ///
  /// With [DiscoveryFilter.likelyNetum] only devices advertising a NETUM
  /// service are reported. Errors ([NetumPermissionDenied],
  /// [NetumBluetoothUnavailable], [NetumLocationServicesOff], ...) arrive on
  /// the stream, which then closes.
  Stream<DiscoveredScanner> discover({
    NetumTransport transport = NetumTransport.ble,
    DiscoveryFilter filter = DiscoveryFilter.likelyNetum,
    Duration timeout = const Duration(seconds: 10),
  }) {
    late final _Discovery discovery;
    final controller = StreamController<DiscoveredScanner>(
      onListen: () => unawaited(_startDiscovery(discovery)),
      onCancel: () => discovery.end(),
    );
    discovery = _Discovery(this, controller, transport, filter, timeout);
    return controller.stream;
  }

  /// Ends the running discovery, closing its stream.
  Future<void> stopDiscovery() async => _discovery?.end();

  /// Whether a discovery is running.
  bool get isDiscovering => _discovery != null;

  Future<void> _startDiscovery(_Discovery discovery) async {
    await _discovery?.end(stopNative: false);
    _discovery = discovery;
    try {
      await initialize();
      if (!isSupported(discovery.transport)) {
        throw const NetumUnsupportedTransport();
      }
      discovery.subscription = transport.discoveries.listen(
        discovery.report,
        onError: discovery.fail,
      );
      await transport.startDiscovery(
        DiscoveryOptionsMsg(
          transport: _transportMsg(discovery.transport),
          filterNetum: discovery.filter == DiscoveryFilter.likelyNetum,
          // Dart owns the timeout; native stops a little later as a safety
          // net.
          timeoutMs: discovery.timeout.inMilliseconds + 2000,
        ),
      );
      discovery.timer = Timer(discovery.timeout, discovery.end);
    } on Object catch (error, stackTrace) {
      await discovery.fail(error, stackTrace);
    }
  }

  // endregion

  // region Devices

  /// The handle for [id], created on first call (no I/O). The same instance
  /// is returned for the same id, so it is safe to keep, e.g. for saved
  /// scanners.
  ///
  /// Throws [NetumInvalidArgument] if [id] is already known with another
  /// transport.
  NetumDevice device(
    String id, {
    required NetumTransport transport,
    String? name,
  }) {
    final device = _deviceFor(id, transport, name: name);
    if (device.transport != transport) {
      throw NetumInvalidArgument(
        '$id is already known as a ${device.transport.name} device',
      );
    }
    return device;
  }

  /// Shortcut for `device(id, transport: transport, name: name).connect()`.
  ///
  /// [name] is for display only: several scanners can share a name, so the
  /// [id] is what identifies a device.
  Future<NetumDevice> connect(
    String id, {
    required NetumTransport transport,
    String? name,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final handle = device(id, transport: transport, name: name);
    await handle.connect(timeout: timeout);
    return handle;
  }

  /// Every handle created in this run.
  @override
  List<NetumDevice> get knownDevices => List.unmodifiable(_devices.values);

  /// The handles that are connected.
  List<NetumDevice> get connectedDevices => List.unmodifiable(
    _devices.values.where((d) => d.isConnected),
  );

  /// Emits [knownDevices] whenever a handle is added or changes state.
  Stream<List<NetumDevice>> get devices => _deviceLists.stream;

  /// How many devices may be connected at once (1–7, default 7).
  @override
  int get maxConnections => _maxConnections;

  set maxConnections(int value) {
    if (value < 1 || value > 7) {
      throw NetumInvalidArgument('maxConnections must be 1–7, got $value');
    }
    _maxConnections = value;
  }

  NetumDevice _deviceFor(String id, NetumTransport transport, {String? name}) {
    final existing = _devices[id];
    if (existing != null) {
      existing.updateName(name);
      return existing;
    }
    final created = NetumDevice(
      id: id,
      transport: transport,
      host: this,
      name: name,
    );
    _devices[id] = created;
    _deviceLists.add(knownDevices);
    return created;
  }

  // endregion

  // region Global streams

  /// Barcodes from every device. Broadcast and hot: only current listeners
  /// receive a scan, so listen from a long-lived service.
  Stream<ScanEvent> get scans => _scans.stream;

  /// Connection state changes of every device.
  Stream<ConnectionEvent> get connectionEvents => _connectionEvents.stream;

  // endregion

  // region Router

  void _onAdapterState(AdapterStateMsg state) {
    final mapped = AdapterState.values.byName(state.name);
    if (mapped == _adapterState) return;
    _adapterState = mapped;
    _adapterStates.add(mapped);
  }

  void _onLinkEvent(LinkStateMsgEvent event) {
    _deviceFor(event.id, _transportOf(event.transport)).handleLinkEvent(event);
  }

  void _onData(DataMsg data) {
    _devices[data.id]?.handleData(data.bytes);
  }

  @override
  void onConnectionEvent(ConnectionEvent event) {
    _connectionEvents.add(event);
    _deviceLists.add(knownDevices);
  }

  @override
  void onScan(ScanEvent event) => _scans.add(event);

  // endregion

  static NetumTransport _transportOf(TransportMsg transport) =>
      transport == TransportMsg.ble ? NetumTransport.ble : NetumTransport.spp;

  static TransportMsg _transportMsg(NetumTransport transport) =>
      transport == NetumTransport.ble ? TransportMsg.ble : TransportMsg.spp;

  static PermissionScopeMsg _scopeMsg(PermissionScope scope) =>
      PermissionScopeMsg.values.byName(scope.name);

  static PermissionStatus _status(PermissionResultMsg result) =>
      PermissionStatus.values.byName(result.name);
}

/// One running `discover()` call.
class _Discovery {
  _Discovery(
    this.scanner,
    this.controller,
    this.transport,
    this.filter,
    this.timeout,
  );

  final NetumScanner scanner;
  final StreamController<DiscoveredScanner> controller;
  final NetumTransport transport;
  final DiscoveryFilter filter;
  final Duration timeout;
  final _seen = <String, DiscoveredScanner>{};
  StreamSubscription<DiscoveredDeviceMsg>? subscription;
  Timer? timer;
  bool _ended = false;

  void report(DiscoveredDeviceMsg found) {
    if (_ended) return;
    final likelyNetum = _advertisesNetum(found.serviceUuids);
    // The native filter already applies, but a result from the previous
    // (unfiltered) scan can still be in flight when this one starts.
    if (filter == DiscoveryFilter.likelyNetum && !likelyNetum) return;
    final previous = _seen[found.id];
    final scanner = DiscoveredScanner(
      id: found.id,
      transport: NetumScanner._transportOf(found.transport),
      name: found.name ?? previous?.name,
      rssi: found.rssi,
      bonded: found.bonded,
      likelyNetum: likelyNetum,
      serviceUuids: found.serviceUuids,
      lastSeen: DateTime.now(),
    );
    _seen[found.id] = scanner;
    if (previous != null &&
        previous.name == scanner.name &&
        previous.rssi == scanner.rssi) {
      return;
    }
    controller.add(scanner);
  }

  Future<void> fail(Object error, [StackTrace? stackTrace]) async {
    if (_ended) return;
    controller.addError(error, stackTrace);
    await end();
  }

  Future<void> end({bool stopNative = true}) async {
    if (_ended) return;
    _ended = true;
    timer?.cancel();
    // Not awaited: a broadcast subscription's cancel completes at once, and
    // waiting on it would only delay stopping native discovery.
    unawaited(subscription?.cancel());
    if (identical(scanner._discovery, this)) {
      scanner._discovery = null;
      if (stopNative) {
        try {
          await scanner.transport.stopDiscovery();
        } on NetumException {
          // Already stopped (e.g. Bluetooth turned off).
        }
      }
    }
    await controller.close();
  }

  static const _netumServices = {'FFF0', 'FF00', '18F0'};

  /// Matches 16-bit UUIDs (`FFF0`) and their 128-bit form
  /// (`0000FFF0-0000-1000-8000-00805F9B34FB`).
  static bool _advertisesNetum(List<String> uuids) => uuids.any((uuid) {
    final upper = uuid.toUpperCase();
    final short = upper.length == 4 ? upper : upper.substring(4, 8);
    return _netumServices.contains(short);
  });
}
