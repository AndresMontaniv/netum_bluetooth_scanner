import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:netum_bluetooth_scanner/src/commands/command_result.dart';
import 'package:netum_bluetooth_scanner/src/commands/netum_command.dart';
import 'package:netum_bluetooth_scanner/src/errors.dart';
import 'package:netum_bluetooth_scanner/src/protocol/classifier.dart';
import 'package:netum_bluetooth_scanner/src/protocol/decoder.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';
import 'package:netum_bluetooth_scanner/src/protocol/reassembler.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

/// Direction of a [SessionPacket].
enum PacketDirection {
  /// Phone → scanner.
  outbound,

  /// Scanner → phone.
  inbound,
}

/// A packet seen by a [DeviceSession]: every command written and every
/// reassembled inbound payload, classified.
class SessionPacket {
  /// An outbound packet carrying [command].
  SessionPacket.outbound(this.bytes, {required NetumCommand this.command})
    : direction = PacketDirection.outbound,
      kind = null,
      text = null,
      timestamp = DateTime.now();

  /// An inbound payload of [kind]; [text] is set for barcodes and replies.
  SessionPacket.inbound(this.bytes, {required InboundKind this.kind, this.text})
    : direction = PacketDirection.inbound,
      command = null,
      timestamp = DateTime.now();

  /// Phone → scanner or scanner → phone.
  final PacketDirection direction;

  /// The bytes as written or as reassembled (terminator included).
  final Uint8List bytes;

  /// Inbound only: what the payload is.
  final InboundKind? kind;

  /// Inbound barcodes and replies: the decoded text.
  final String? text;

  /// Outbound only: the command written.
  final NetumCommand? command;

  /// When the packet was seen.
  final DateTime timestamp;
}

/// The protocol state of one connected scanner: inbound pipeline
/// (reassembler → classifier → decoder) and a FIFO command queue with one
/// command in flight.
///
/// The session writes through [NetumTransportApi.write]. It does not
/// subscribe to the transport: one router feeds it with [handleData],
/// [handleConnected] and [handleDisconnected].
class DeviceSession {
  /// Creates a session for [deviceId]. It starts disconnected.
  DeviceSession({
    required this.deviceId,
    required NetumTransportApi transport,
    this.commandTimeout = const Duration(milliseconds: 1500),
    this.disconnectTimeout = const Duration(seconds: 3),
    this.replyWindow = const Duration(milliseconds: 300),
    Duration idleTimeout = const Duration(milliseconds: 100),
  }) : _transport = transport {
    _reassembler = Reassembler(
      onPayload: _onPayload,
      idleTimeout: idleTimeout,
    );
  }

  /// The platform id of the device.
  final String deviceId;

  /// Default time to wait for a command's ACK, echo or reply.
  final Duration commandTimeout;

  /// Time to wait for the link to drop after a command that expects it.
  final Duration disconnectTimeout;

  /// How long after its write completes an unprefixed reply is accepted.
  final Duration replyWindow;

  final NetumTransportApi _transport;
  late final Reassembler _reassembler;
  final _packets = StreamController<SessionPacket>.broadcast();
  final _queue = Queue<_Job>();
  _InFlight? _inFlight;
  bool _connected = false;
  bool _closed = false;

  /// Every packet written or received, classified. Barcodes are packets of
  /// kind [InboundKind.barcode].
  Stream<SessionPacket> get packets => _packets.stream;

  /// Whether the link is up.
  bool get isConnected => _connected;

  /// The command in flight, if it expects the link to drop (rename, power
  /// off, mode switch). Read it before [handleDisconnected] to tell an
  /// expected disconnect from a lost link.
  NetumCommand? get pendingDisconnectCommand {
    final command = _inFlight?.job.command;
    return command != null && command.expectsDisconnect ? command : null;
  }

  /// Sends a catalog or custom [command], framed. Commands run one at a
  /// time, in order.
  ///
  /// Throws [NetumNotConnected] if the link is down or drops before the
  /// command is answered, and [NetumCommandTimeout] if the scanner does not
  /// answer within [timeout] (default [commandTimeout], or
  /// [disconnectTimeout] for commands that expect the link to drop).
  Future<CommandResult> send(NetumCommand command, {Duration? timeout}) =>
      _enqueue(command, framed: true, timeout: timeout);

  /// Sends free text, framed or raw. The response is not known in advance:
  /// the first ACK, echo, or payload within the reply window answers it. A
  /// raw send with no response resolves as [CommandOutcome.sentRaw] when the
  /// window closes.
  Future<CommandResult> sendRaw(
    String ascii, {
    bool framed = true,
    Duration? timeout,
  }) => _enqueue(
    NetumCommand.custom(ascii, description: 'sendRaw'),
    framed: framed,
    timeout: timeout,
  );

  /// The link is ready.
  void handleConnected() {
    if (_closed) return;
    _connected = true;
    _pump();
  }

  /// A native data chunk arrived.
  void handleData(Uint8List chunk) {
    if (_closed) return;
    _reassembler.add(chunk);
  }

  /// The link dropped. The pending command fails with [NetumNotConnected]
  /// (or succeeds, if it expected the drop) and so do all queued commands.
  void handleDisconnected() {
    _connected = false;
    _reassembler.reset();

    final flight = _inFlight;
    if (flight != null) {
      if (flight.job.command.expectsDisconnect) {
        _resolve(flight, const CommandResult(CommandOutcome.disconnected));
      } else {
        _fail(flight, const NetumNotConnected());
      }
    }
    while (_queue.isNotEmpty) {
      _queue.removeFirst().completer.completeError(const NetumNotConnected());
    }
  }

  /// Fails everything outstanding and closes [packets].
  Future<void> close() async {
    if (_closed) return;
    handleDisconnected();
    _closed = true;
    await _packets.close();
  }

  Future<CommandResult> _enqueue(
    NetumCommand command, {
    required bool framed,
    Duration? timeout,
  }) {
    if (!_connected || _closed) {
      return Future.error(const NetumNotConnected());
    }
    final job = _Job(
      command,
      framed: framed,
      timeout:
          timeout ??
          (command.expectsDisconnect ? disconnectTimeout : commandTimeout),
    );
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  void _pump() {
    if (!_connected || _inFlight != null || _queue.isEmpty) return;
    _start(_queue.removeFirst());
  }

  void _start(_Job job) {
    final command = job.command;
    final bytes = job.framed
        ? encodeFrame(command.ascii)
        : Uint8List.fromList(command.ascii.codeUnits);
    final expectation = _expectationOf(command, framed: job.framed);
    final pending = PendingResponse(
      sentBytes: bytes,
      framed: job.framed,
      expectation: expectation,
      replyPrefix: command.replyPrefix,
    );
    // The reply can arrive before the write callback, so the window opens
    // when the write is issued.
    final windowed =
        expectation == ResponseExpectation.unprefixedReply ||
        expectation == ResponseExpectation.any;
    pending.replyWindowOpen = windowed;

    final flight = _InFlight(job, pending);
    _inFlight = flight;
    flight.timeoutTimer = Timer(job.timeout, () {
      _fail(flight, NetumCommandTimeout(command));
    });

    _packets.add(SessionPacket.outbound(bytes, command: command));
    unawaited(
      _transport
          .write(deviceId, bytes)
          .then(
            (_) {
              if (!identical(_inFlight, flight) || !windowed) return;
              flight.windowTimer = Timer(replyWindow, () {
                pending.replyWindowOpen = false;
                if (!job.framed) {
                  _resolve(flight, const CommandResult(CommandOutcome.sentRaw));
                }
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              _fail(flight, error, stackTrace);
            },
          ),
    );
  }

  void _onPayload(Uint8List payload) {
    final flight = _inFlight;
    final kind = classifyPayload(payload, flight?.pending);
    final text = kind == InboundKind.barcode || kind == InboundKind.reply
        ? decodePayload(payload)
        : null;
    _packets.add(SessionPacket.inbound(payload, kind: kind, text: text));

    if (flight == null) return;
    switch (kind) {
      case InboundKind.ack:
        _resolve(flight, const CommandResult(CommandOutcome.ack));
      case InboundKind.echo:
        _resolve(flight, const CommandResult(CommandOutcome.echo));
      case InboundKind.reply:
        _resolve(
          flight,
          CommandResult(CommandOutcome.reply, reply: text, rawReply: payload),
        );
      case InboundKind.strayAck:
      case InboundKind.strayFrame:
      case InboundKind.barcode:
        break;
    }
  }

  void _resolve(_InFlight flight, CommandResult result) {
    if (!_finish(flight)) return;
    flight.job.completer.complete(result);
    _pump();
  }

  void _fail(_InFlight flight, Object error, [StackTrace? stackTrace]) {
    if (!_finish(flight)) return;
    flight.job.completer.completeError(error, stackTrace);
    _pump();
  }

  /// Clears [flight] if it is still the one in flight.
  bool _finish(_InFlight flight) {
    if (!identical(_inFlight, flight)) return false;
    flight.timeoutTimer?.cancel();
    flight.windowTimer?.cancel();
    _inFlight = null;
    return true;
  }

  static ResponseExpectation _expectationOf(
    NetumCommand command, {
    required bool framed,
  }) {
    if (!framed) return ResponseExpectation.any;
    return switch (command.kind) {
      CommandKind.action => ResponseExpectation.ackOrEcho,
      CommandKind.query when command.replyPrefix != null =>
        ResponseExpectation.prefixedReply,
      CommandKind.query => ResponseExpectation.unprefixedReply,
      CommandKind.unknown => ResponseExpectation.any,
    };
  }
}

class _Job {
  _Job(this.command, {required this.framed, required this.timeout});

  final NetumCommand command;
  final bool framed;
  final Duration timeout;
  final completer = Completer<CommandResult>();
}

class _InFlight {
  _InFlight(this.job, this.pending);

  final _Job job;
  final PendingResponse pending;
  Timer? timeoutTimer;
  Timer? windowTimer;
}
