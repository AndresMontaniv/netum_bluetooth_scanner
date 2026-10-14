import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:netum_bluetooth_scanner/src/api/models.dart';
import 'package:netum_bluetooth_scanner/src/api/netum_device.dart';
import 'package:netum_bluetooth_scanner/src/api/saved_scanners.dart';
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
  final _traffic = StreamController<TrafficEvent>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void>? _initialization;
  AdapterState _adapterState = AdapterState.unknown;
  int _maxConnections = 7;
  NetumStore? _store;
  Future<void> _storeWrites = Future.value();
  _Discovery? _discovery;
  StreamController<DiscoveredScanner>? _sppListening;

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
    await _traffic.close();
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

  /// Devices bonded (paired) with the phone over Classic Bluetooth, the SPP
  /// candidates. Android only; empty on iOS. Needs the connection
  /// permission.
  Future<List<DiscoveredScanner>> bondedScanners({
    DiscoveryFilter filter = DiscoveryFilter.likelyNetum,
  }) async {
    await initialize();
    if (!isSupported(NetumTransport.spp)) return const [];
    final bonded = await transport.bondedDevices();
    return [
      for (final found in bonded)
        if (filter == DiscoveryFilter.all || _Discovery.isLikelyNetum(found))
          DiscoveredScanner(
            id: found.id,
            transport: NetumTransport.spp,
            name: found.name,
            rssi: found.rssi,
            bonded: true,
            likelyNetum: _Discovery.isLikelyNetum(found),
            serviceUuids: found.serviceUuids,
            lastSeen: DateTime.now(),
          ),
    ];
  }

  // region SPP pair by scanning (Android)

  /// Waits for a scanner to dial in after it scans the barcode made from
  /// [sppPairingBarcodeData] (the vendor's "pair by scanning" flow). Emits
  /// that scanner once and closes; connect to it as usual. Closes empty
  /// after [timeout] or on [stopListeningForSppScanner].
  ///
  /// The default SPP flow, [discover] with [NetumTransport.spp] and then
  /// connect (which shows the OS pairing prompt), does not need this.
  ///
  /// A scanner that was paired with any phone before keeps its half of the
  /// pairing even after the phone forgets it, and then hangs up right after
  /// dialling in. Power-cycle it first (or scan `AT+MODE=2`, then
  /// `AT+MODE=1`).
  ///
  /// Android only: throws [NetumUnsupportedTransport] elsewhere.
  Stream<DiscoveredScanner> listenForSppScanner({
    Duration timeout = const Duration(minutes: 2),
  }) {
    late final StreamController<DiscoveredScanner> controller;
    StreamSubscription<DiscoveredDeviceMsg>? subscription;
    Timer? timer;
    var finished = false;
    Future<void> finish() async {
      // Runs once: closing the stream also triggers onCancel.
      if (finished) return;
      finished = true;
      timer?.cancel();
      await subscription?.cancel();
      subscription = null;
      try {
        await transport.stopSppListener();
      } on NetumException {
        // Already stopped.
      }
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<DiscoveredScanner>(
      onListen: () async {
        try {
          await initialize();
          if (!isSupported(NetumTransport.spp)) {
            throw const NetumUnsupportedTransport('SPP is Android only');
          }
          await _discovery?.end();
          subscription = transport.discoveries.listen((found) {
            if (found.transport != TransportMsg.spp) return;
            controller.add(
              DiscoveredScanner(
                id: found.id,
                transport: NetumTransport.spp,
                name: found.name,
                rssi: found.rssi,
                bonded: found.bonded,
                likelyNetum: true,
                serviceUuids: found.serviceUuids,
                lastSeen: DateTime.now(),
              ),
            );
            unawaited(finish());
          }, onError: controller.addError);
          await transport.startSppListener(timeout.inMilliseconds + 2000);
          timer = Timer(timeout, () => unawaited(finish()));
        } on Object catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await finish();
        }
      },
      onCancel: finish,
    );
    _sppListening = controller;
    return controller.stream;
  }

  /// Stops [listenForSppScanner], closing its stream.
  Future<void> stopListeningForSppScanner() async {
    final listening = _sppListening;
    _sppListening = null;
    if (listening != null && !listening.isClosed) await listening.close();
    try {
      await transport.stopSppListener();
    } on NetumException {
      // Already stopped.
    }
  }

  /// The barcode text that makes a scanner in SPP mode dial in to this
  /// phone: `AT+SPPCONN=AABBCCDDEEFF`. Render it as Code 128.
  ///
  /// Apps cannot read the phone's own Bluetooth MAC (Android 6+): the user
  /// finds it in Settings → About phone → Status → Bluetooth address.
  /// Accepts `AA:BB:CC:DD:EE:FF` or `AABBCCDDEEFF`; throws
  /// [NetumInvalidArgument] otherwise.
  static String sppPairingBarcodeData(String phoneBluetoothMac) {
    final hex = phoneBluetoothMac.trim().toUpperCase().replaceAll(':', '');
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(hex)) {
      throw NetumInvalidArgument(
        'Not a Bluetooth MAC address: "$phoneBluetoothMac"',
      );
    }
    return 'AT+SPPCONN=$hex';
  }

  // endregion

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
    bool autoReconnect = false,
    ReconnectPolicy reconnectPolicy = const ReconnectPolicy(),
    bool remember = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final handle = device(id, transport: transport, name: name);
    await handle.connect(
      autoReconnect: autoReconnect,
      reconnectPolicy: reconnectPolicy,
      remember: remember,
      timeout: timeout,
    );
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

  // region Saved scanners

  /// Where the saved-scanner list lives. Defaults to native key-value
  /// storage; set your own before the first connect to use other storage.
  NetumStore get store => _store ??= NativeNetumStore(transport);

  set store(NetumStore value) => _store = value;

  /// Remembered scanners, most recently connected first.
  Future<List<SavedScanner>> savedScanners() async {
    await _storeWrites;
    return decodeSavedScanners(await store.load());
  }

  /// Removes [id] from the saved scanners.
  Future<void> forgetScanner(String id) => _updateSaved(
    (saved) => saved.where((s) => s.id != id).toList(),
  );

  /// Reconnects saved scanners, each with its saved reconnect settings.
  /// Call it when the app is ready (e.g. at startup); the plugin never
  /// reconnects saved scanners by itself.
  ///
  /// Returns the devices that are connected afterwards. Scanners that are
  /// off or out of range are skipped; adapter and permission errors are
  /// thrown.
  Future<List<NetumDevice>> restoreSaved({
    RestoreStrategy strategy = RestoreStrategy.firstAvailable,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await initialize();
    final saved = await savedScanners();
    Future<NetumDevice?> attempt(SavedScanner entry) async {
      final handle = device(
        entry.id,
        transport: entry.transport,
        name: entry.name,
      );
      try {
        await handle.connect(
          autoReconnect: entry.autoReconnect,
          reconnectPolicy: entry.reconnectPolicy,
          timeout: timeout,
        );
        return handle;
      } on NetumConnectionFailed {
        return null;
      } on NetumDeviceBusy {
        return null;
      } on NetumMaxConnectionsReached {
        return null;
      }
    }

    switch (strategy) {
      case RestoreStrategy.firstAvailable:
        for (final entry in saved) {
          if (await attempt(entry) case final device?) return [device];
        }
        return [];
      case RestoreStrategy.all:
        final results = await Future.wait(
          saved.take(maxConnections).map(attempt),
        );
        return [...results.nonNulls];
    }
  }

  @override
  Future<void> remember(NetumDevice device) => _updateSaved((saved) {
    final entry = SavedScanner(
      id: device.id,
      transport: device.transport,
      name: device.name,
      lastConnected: DateTime.now(),
      autoReconnect: device.autoReconnect,
      reconnectPolicy: device.reconnectPolicy,
    );
    return [entry, ...saved.where((s) => s.id != device.id)];
  });

  @override
  Future<void> updateSavedName(NetumDevice device) => _updateSaved(
    (saved) => [
      for (final entry in saved)
        if (entry.id == device.id)
          SavedScanner(
            id: entry.id,
            transport: entry.transport,
            name: device.name,
            lastConnected: entry.lastConnected,
            autoReconnect: entry.autoReconnect,
            reconnectPolicy: entry.reconnectPolicy,
          )
        else
          entry,
    ],
  );

  /// Serializes read-modify-write cycles on the store.
  Future<void> _updateSaved(
    List<SavedScanner> Function(List<SavedScanner> saved) update,
  ) {
    final write = _storeWrites.then((_) async {
      final saved = decodeSavedScanners(await store.load());
      await store.save(encodeSavedScanners(update(saved)));
    });
    _storeWrites = write.catchError((Object _) {});
    return write;
  }

  // endregion

  // region Global streams

  /// Barcodes from every device. Broadcast and hot: only current listeners
  /// receive a scan, so listen from a long-lived service.
  Stream<ScanEvent> get scans => _scans.stream;

  /// Connection state changes of every device.
  Stream<ConnectionEvent> get connectionEvents => _connectionEvents.stream;

  /// Whether [traffic] reports packets. Off by default: it costs an event
  /// per packet.
  @override
  bool trafficLogEnabled = false;

  /// Every packet of every device, classified, while [trafficLogEnabled].
  /// For debugging.
  Stream<TrafficEvent> get traffic => _traffic.stream;

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

  @override
  void onTraffic(TrafficEvent event) => _traffic.add(event);

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
    final likelyNetum = isLikelyNetum(found);
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
  static const _sppService = '1101';
  static final _netumName = RegExp('barcode|netum', caseSensitive: false);

  /// BLE: advertises FFF0, FF00 or 18F0. SPP / bonded: the module vendor's
  /// Classic MAC prefix `DC:0D:30`, the SPP service in the record, or a name
  /// like "DS barcode scanner" / "Netum-01" (B2).
  static bool isLikelyNetum(DiscoveredDeviceMsg found) {
    final shortUuids = found.serviceUuids.map(_shortUuid).toSet();
    if (found.transport == TransportMsg.ble) {
      return shortUuids.any(_netumServices.contains);
    }
    return found.id.toUpperCase().startsWith('DC:0D:30') ||
        shortUuids.contains(_sppService) ||
        _netumName.hasMatch(found.name ?? '');
  }

  /// `FFF0` from `FFF0` or `0000FFF0-0000-1000-8000-00805F9B34FB`.
  static String _shortUuid(String uuid) {
    final upper = uuid.toUpperCase();
    return upper.length == 4 ? upper : upper.substring(4, 8);
  }
}
