import 'dart:async';
import 'dart:typed_data';

import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

/// Turns native data chunks (BLE notifications or SPP reads) into complete
/// payloads for one device.
///
/// - An ACK `[x, 0x0B]` or a frame `02 … 03` is emitted as-is, never
///   buffered.
/// - A chunk ending in a terminator (CR, LF or TAB) completes a payload. It is
///   never split on inner terminators: a misread can contain an embedded CR.
/// - Anything else is buffered until a terminated chunk arrives or the line
///   has been idle for [idleTimeout] (scanners without a terminator, payloads
///   above the MTU).
///
/// Payloads keep their original order: buffered bytes are flushed before an
/// ACK or frame is emitted.
class Reassembler {
  /// Creates a reassembler that reports payloads to [onPayload].
  Reassembler({
    required void Function(Uint8List payload) onPayload,
    this.idleTimeout = const Duration(milliseconds: 100),
  }) : _onPayload = onPayload;

  /// How long a partial payload waits for more bytes before it is flushed.
  final Duration idleTimeout;

  final void Function(Uint8List payload) _onPayload;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Timer? _idleTimer;

  /// Feeds one native chunk.
  void add(Uint8List chunk) {
    if (chunk.isEmpty) return;

    if (isAck(chunk) || isFrame(chunk)) {
      flush();
      _onPayload(chunk);
      return;
    }

    _buffer.add(chunk);
    if (_isTerminator(chunk.last)) {
      flush();
    } else {
      _idleTimer?.cancel();
      _idleTimer = Timer(idleTimeout, flush);
    }
  }

  /// Emits any buffered bytes as one payload.
  void flush() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_buffer.isEmpty) return;
    _onPayload(_buffer.takeBytes());
  }

  /// Drops buffered bytes without emitting them (on disconnect).
  void reset() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _buffer.clear();
  }

  static bool _isTerminator(int byte) =>
      byte == 0x0D || byte == 0x0A || byte == 0x09;
}
