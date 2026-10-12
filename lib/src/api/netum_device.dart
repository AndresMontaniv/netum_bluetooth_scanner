import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:netum_bluetooth_scanner/src/api/models.dart';
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
  /// Throws [NetumDeviceBusy] while already connecting,
  /// [NetumMaxConnectionsReached], [NetumPermissionDenied],
  /// [NetumBluetoothUnavailable] or [NetumConnectionFailed].
  Future<void> connect({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _host.initialize();
    if (_state == NetumConnectionState.connected) return;
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
  Future<String> getFirmwareVersion() async {
    final result = await _send(NetumCommand.system.firmwareVersion);
    return result.reply ?? (throw NetumUnexpectedReply(''));
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
