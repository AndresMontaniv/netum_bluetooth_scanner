import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:netum_bluetooth_scanner/src/api/models.dart';
import 'package:netum_bluetooth_scanner/src/commands/command_options.dart';
import 'package:netum_bluetooth_scanner/src/commands/command_result.dart';
import 'package:netum_bluetooth_scanner/src/commands/netum_command.dart';
import 'package:netum_bluetooth_scanner/src/commands/reply_parsers.dart';
import 'package:netum_bluetooth_scanner/src/errors.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/models/adapter_state.dart';
import 'package:netum_bluetooth_scanner/src/models/battery_info.dart';
import 'package:netum_bluetooth_scanner/src/protocol/classifier.dart';
import 'package:netum_bluetooth_scanner/src/session/device_session.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

/// What a [NetumDevice] needs from the scanner that owns it.
@internal
abstract interface class DeviceHost {
  /// The native side.
  NetumTransportApi get transport;

  /// Upper bound of simultaneous connections.
  int get maxConnections;

  /// Every handle created so far.
  List<NetumDevice> get knownDevices;

  /// The last known adapter state.
  AdapterState get currentAdapterState;

  /// Syncs with native once; called before any I/O.
  Future<void> initialize();

  /// A device changed state.
  void onConnectionEvent(ConnectionEvent event);

  /// A device read a barcode.
  void onScan(ScanEvent event);
}

/// A handle to one scanner. `NetumScanner.device` returns the same instance
/// for the same id, and its streams survive disconnects and reconnects, so
/// it can be kept for the lifetime of the app.
class NetumDevice {
  /// Creates a handle. Use `NetumScanner.device` instead.
  @internal
  NetumDevice({
    required this.id,
    required this.transport,
    required DeviceHost host,
    String? name,
  }) : _host = host,
       _name = name {
    _session = DeviceSession(deviceId: id, transport: host.transport);
    _session.packets.listen(_onPacket);
  }

  /// Android: the MAC address of this transport. iOS: the per-phone
  /// identifier UUID.
  final String id;

  /// The transport this handle connects over.
  final NetumTransport transport;

  final DeviceHost _host;
  late final DeviceSession _session;
  final _states = StreamController<NetumConnectionState>.broadcast();
  final _scans = StreamController<ScanEvent>.broadcast();
  String? _name;
  NetumConnectionState _state = NetumConnectionState.disconnected;

  /// The last known advertised or bonded name.
  String? get name => _name;

  /// The current connection state.
  NetumConnectionState get state => _state;

  /// Whether the device is connected and ready for commands.
  bool get isConnected => _state == NetumConnectionState.connected;

  /// State changes. Broadcast; survives reconnects.
  Stream<NetumConnectionState> get stateChanges => _states.stream;

  /// Barcodes read by this device. Broadcast and hot: only current
  /// listeners receive a scan.
  Stream<ScanEvent> get scans => _scans.stream;

  /// Connects and enables notifications. Completes once the device is ready
  /// for data; does nothing if already connected.
  ///
  /// Fails fast while Bluetooth is off or unauthorized. Throws
  /// [NetumDeviceBusy] while already connecting,
  /// [NetumMaxConnectionsReached], [NetumPermissionDenied],
  /// [NetumBluetoothUnavailable] or [NetumConnectionFailed].
  Future<void> connect({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _host.initialize();
    if (_state == NetumConnectionState.connected) return;
    switch (_host.currentAdapterState) {
      case AdapterState.poweredOff:
      case AdapterState.unsupported:
        throw NetumBluetoothUnavailable(_host.currentAdapterState);
      case AdapterState.unauthorized:
        throw NetumPermissionDenied(const ['bluetooth']);
      case AdapterState.unknown:
      case AdapterState.poweredOn:
      // Connecting works with Location services off.
      case AdapterState.locationServicesOff:
        break;
    }
    if (_state == NetumConnectionState.connecting) {
      throw const NetumDeviceBusy();
    }
    final active = _host.knownDevices.where(
      (d) =>
          !identical(d, this) &&
          (d.state == NetumConnectionState.connected ||
              d.state == NetumConnectionState.connecting),
    );
    if (active.length >= _host.maxConnections) {
      throw const NetumMaxConnectionsReached();
    }

    _setState(NetumConnectionState.connecting);
    try {
      await _host.transport.connect(
        id,
        ConnectOptionsMsg(
          transport: transport == NetumTransport.ble
              ? TransportMsg.ble
              : TransportMsg.spp,
          timeoutMs: timeout.inMilliseconds,
          autoReconnect: false,
          sppInsecureFallback: false,
        ),
      );
    } on NetumException catch (error) {
      _setState(
        NetumConnectionState.disconnected,
        reason: ConnectFailed(
          platformCode: error is NetumConnectionFailed
              ? error.platformCode
              : null,
          message: error.message,
        ),
      );
      rethrow;
    }
    _markConnected();
  }

  /// Disconnects. User-initiated: never followed by an automatic reconnect.
  Future<void> disconnect() async {
    if (_state == NetumConnectionState.disconnected) return;
    await _host.transport.disconnect(id);
    // The native link event normally got here first.
    _onDisconnected(userInitiated: true);
  }

  /// Turns the scan engine on for [seconds] (1–7), as if the trigger were
  /// pressed. Throws [NetumInvalidArgument] outside that range.
  Future<void> triggerScan({int seconds = 1}) async {
    await _send(NetumCommand.scan.trigger(seconds));
  }

  /// Plays preset sound [preset] (0–26).
  Future<void> beep([int preset = 0]) async {
    await _send(NetumCommand.feedback.beep(preset));
  }

  /// Reads the battery voltage and charge level.
  Future<BatteryInfo> getBattery() async {
    final result = await _send(NetumCommand.power.battery);
    final reply = result.reply ?? '';
    return parseBattery(reply) ?? (throw NetumUnexpectedReply(reply));
  }

  /// Reads the scanner firmware version, e.g. `bn0HDS_RFSBTD43bc_CB071`.
  Future<String> getFirmwareVersion() =>
      _query(NetumCommand.system.firmwareVersion);

  // region Typed settings (persist on the scanner)

  /// Sets the beeper volume.
  Future<void> setVolume(BeepVolume volume) async {
    await _send(NetumCommand.feedback.volume(volume));
  }

  /// Sets the beeper tone.
  Future<void> setTone(BeepTone tone) async {
    await _send(NetumCommand.feedback.tone(tone));
  }

  /// Turns vibration on or off.
  Future<void> setVibration({required bool enabled}) async {
    await _send(NetumCommand.feedback.vibration(enabled: enabled));
  }

  /// Whether framed commands (everything this plugin sends) are confirmed
  /// with a beep and vibration. With `false` they are silent but still
  /// acknowledged, which suits background queries such as battery polling.
  Future<void> setCommandConfirmationBeep({required bool enabled}) async {
    await _send(NetumCommand.feedback.ackBeep(enabled: enabled));
  }

  /// Sets how scans are triggered.
  Future<void> setScanMode(ScanMode mode) async {
    await _send(NetumCommand.scan.mode(mode));
  }

  /// Sets the idle time before the scanner sleeps. A sleeping scanner drops
  /// the link; pressing its trigger wakes it.
  Future<void> setSleepTimeout(SleepTimeout timeout) async {
    await _send(NetumCommand.power.setSleepTimeout(timeout));
  }

  /// Sets the characters appended after every barcode. Keep a terminator
  /// (the default is CR): it is what delimits barcodes reliably.
  Future<void> setTerminator(Terminator terminator) async {
    await _send(NetumCommand.format.terminator(terminator));
  }

  /// Turns the scanner off. Completes once the link drops.
  Future<void> powerOff() async {
    await _send(NetumCommand.power.powerOff);
  }

  /// Renames the scanner (printable ASCII, 1–20 characters). The name
  /// persists and applies to BLE and SPP.
  ///
  /// The scanner drops the link at once, restarts its radio and advertises
  /// the new name; this completes when the link drops, and the handle's
  /// [name] is updated. With auto-reconnect on, it reconnects by itself.
  /// Several scanners can share a name: the [id] identifies a device.
  Future<void> setName(String name) async {
    final command = NetumCommand.system.setName(name);
    await _send(command);
    _name = name;
  }

  /// ⚠️ Switches the scanner's Bluetooth mode. The link drops, and the
  /// scanner must then be found again in the new mode:
  ///
  /// - [NetumMode.spp]: Android only; needs OS pairing.
  /// - [NetumMode.hid]: the scanner pairs as a keyboard and **can no longer
  ///   be controlled by this plugin** until it is switched back with the
  ///   `AT+MODE=3` configuration barcode.
  ///
  /// Auto-reconnect is turned off for this handle, since the scanner will
  /// not come back on this transport.
  Future<void> switchMode(NetumMode mode) async {
    await _send(NetumCommand.dangerous.mode(mode));
  }

  // endregion

  // region Typed queries

  /// Reads the decode-engine model, e.g. `SE4750`.
  Future<String> getEngineModel() => _query(NetumCommand.system.decodeEngine);

  /// Reads the idle time before the scanner sleeps; `null` = never.
  Future<Duration?> getSleepTimeout() async {
    final reply = await _query(NetumCommand.power.sleepTimeout);
    final timeout = parseSleepTimeout(reply);
    if (timeout != null) return timeout == Duration.zero ? null : timeout;
    if (reply.toLowerCase().contains('never')) return null;
    throw NetumUnexpectedReply(reply);
  }

  /// Reads the Bluetooth module's name, Classic MAC and firmware (three
  /// queued queries). Works over BLE and SPP.
  Future<BluetoothInfo> getBluetoothInfo() async {
    final nameReply = await _query(NetumCommand.system.bluetoothName);
    final addressReply = await _query(NetumCommand.system.bluetoothAddress);
    final versionReply = await _query(NetumCommand.system.bluetoothFirmware);
    return BluetoothInfo(
      name:
          parseBluetoothName(nameReply) ??
          (throw NetumUnexpectedReply(nameReply)),
      classicAddress:
          parseBluetoothAddress(addressReply) ??
          (throw NetumUnexpectedReply(addressReply)),
      firmware:
          parseBluetoothFirmware(versionReply) ??
          (throw NetumUnexpectedReply(versionReply)),
    );
  }

  /// Reads how many scans are stored on the scanner (inventory mode).
  Future<int> getStoredCount() async {
    final reply = await _query(NetumCommand.workMode.storedCount);
    return parseStoredCount(reply) ?? (throw NetumUnexpectedReply(reply));
  }

  // endregion

  // region Inventory mode (experimental)

  /// Sends scans at once ([WorkMode.normal]) or stores them on the scanner
  /// ([WorkMode.store]). Experimental.
  Future<void> setWorkMode(WorkMode mode) async {
    await _send(NetumCommand.workMode.mode(mode));
  }

  /// Uploads the stored scans; they arrive on [scans] like live scans.
  /// Experimental.
  Future<void> uploadStored({bool clearAfter = false}) async {
    await _send(
      clearAfter
          ? NetumCommand.workMode.uploadAndClear
          : NetumCommand.workMode.upload,
    );
  }

  /// Deletes the stored scans. Experimental.
  Future<void> clearStored() async {
    await _send(NetumCommand.workMode.clearStored);
  }

  // endregion

  /// Reads the scanner's identity. BLE: the Device Information Service (no
  /// scanner command). SPP: `AT+ADDR` and `AT+VER`. Fields the scanner does
  /// not expose are `null`.
  Future<DeviceInfo> getDeviceInfo() async {
    _ensureConnected();
    if (transport == NetumTransport.spp) {
      final info = await getBluetoothInfo();
      return DeviceInfo(
        serial: info.classicAddress.replaceAll(':', ''),
        firmwareRevision: info.firmware,
        classicAddress: info.classicAddress,
      );
    }
    Future<String?> read(String characteristic) async {
      try {
        final bytes = await _host.transport.readCharacteristic(
          id,
          '180A',
          characteristic,
        );
        final text = String.fromCharCodes(bytes.where((b) => b != 0)).trim();
        return text.isEmpty ? null : text;
      } on NetumNotConnected {
        rethrow;
      } on NetumException {
        return null;
      }
    }

    final manufacturer = await read('2A29');
    final model = await read('2A24');
    final serial = await read('2A25');
    final hardware = await read('2A27');
    final firmware = await read('2A26') ?? await read('2A28');
    final mac = serial != null && RegExp(r'^[0-9A-F]{12}$').hasMatch(serial)
        ? [for (var i = 0; i < 12; i += 2) serial.substring(i, i + 2)].join(':')
        : null;
    return DeviceInfo(
      manufacturer: manufacturer,
      model: model,
      serial: serial,
      hardwareRevision: hardware,
      firmwareRevision: firmware,
      classicAddress: mac,
    );
  }

  /// Sends a catalog or custom [command], framed. Commands run one at a time
  /// per device. Throws [NetumNotConnected] or [NetumCommandTimeout].
  Future<CommandResult> send(NetumCommand command) => _send(command);

  /// Sends free text, framed (default) or raw. The first ACK, echo or
  /// prompt reply answers it; a raw send with no response completes as
  /// [CommandOutcome.sentRaw].
  Future<CommandResult> sendRaw(
    String ascii, {
    bool framed = true,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    _ensureConnected();
    return _session.sendRaw(ascii, framed: framed, timeout: timeout);
  }

  /// Reads the current signal strength in dBm.
  Future<int> readRssi() async {
    _ensureConnected();
    return _host.transport.readRssi(id);
  }

  Future<String> _query(NetumCommand command) async {
    final result = await _send(command);
    return result.reply ?? (throw NetumUnexpectedReply(''));
  }

  Future<CommandResult> _send(NetumCommand command) async {
    _ensureConnected();
    return _session.send(command);
  }

  void _ensureConnected() {
    if (_state != NetumConnectionState.connected) {
      throw const NetumNotConnected();
    }
  }

  // region Router input (NetumScanner)

  /// Feeds a native data chunk.
  @internal
  void handleData(Uint8List bytes) => _session.handleData(bytes);

  /// Applies a native link event.
  @internal
  void handleLinkEvent(LinkStateMsgEvent event) {
    switch (event.state) {
      case LinkStateMsg.connecting:
        _setState(NetumConnectionState.connecting);
      case LinkStateMsg.connected:
        _markConnected();
      case LinkStateMsg.disconnecting:
        _setState(NetumConnectionState.disconnecting);
      case LinkStateMsg.disconnected:
        _onDisconnected(
          userInitiated: event.userInitiated,
          platformCode: event.platformCode,
          message: event.message,
        );
    }
  }

  /// Marks a link that native reports as already up (hot restart).
  @internal
  void adoptConnectedLink({String? name}) {
    _name = name ?? _name;
    _markConnected();
  }

  /// Updates the last known name.
  @internal
  void updateName(String? value) => _name = value ?? _name;

  // endregion

  void _markConnected() {
    if (_state == NetumConnectionState.connected) return;
    _session.handleConnected();
    _setState(NetumConnectionState.connected);
  }

  void _onDisconnected({
    required bool userInitiated,
    int? platformCode,
    String? message,
  }) {
    if (_state == NetumConnectionState.disconnected) return;
    final expectedBy = _session.pendingDisconnectCommand;
    final DisconnectReason reason;
    if (expectedBy != null) {
      reason = ExpectedAfterCommand(expectedBy);
    } else if (_state == NetumConnectionState.connecting) {
      reason = ConnectFailed(platformCode: platformCode, message: message);
    } else if (userInitiated) {
      reason = const UserRequested();
    } else if (_host.currentAdapterState == AdapterState.poweredOff) {
      reason = const BluetoothOff();
    } else if (platformCode == _remoteTerminatedCode) {
      reason = RemoteTerminated(platformCode);
    } else {
      reason = LinkLost(platformCode);
    }
    _session.handleDisconnected();
    _setState(NetumConnectionState.disconnected, reason: reason);
  }

  void _setState(NetumConnectionState state, {DisconnectReason? reason}) {
    if (_state == state) return;
    _state = state;
    _states.add(state);
    _host.onConnectionEvent(
      ConnectionEvent(device: this, state: state, reason: reason),
    );
  }

  void _onPacket(SessionPacket packet) {
    if (packet.kind != InboundKind.barcode) return;
    final event = ScanEvent(
      device: this,
      text: packet.text ?? '',
      raw: packet.bytes,
      timestamp: packet.timestamp,
    );
    _scans.add(event);
    _host.onScan(event);
  }

  /// Android GATT 19 / iOS CBError 7: the scanner closed the connection.
  static int get _remoteTerminatedCode =>
      defaultTargetPlatform == TargetPlatform.iOS ? 7 : 19;

  @override
  String toString() => 'NetumDevice($id, ${_state.name})';
}
