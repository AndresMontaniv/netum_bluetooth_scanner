import 'dart:typed_data';

import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

/// What an inbound payload is.
enum InboundKind {
  /// `[LEN, 0x0B]` acknowledging the pending framed command.
  ack,

  /// `[x, 0x0B]` matching nothing pending (for example a late ACK after a
  /// timeout). Traffic only, never a scan.
  strayAck,

  /// The pending frame echoed back: an alternative acknowledgement.
  echo,

  /// A frame matching nothing pending. Traffic only, never a scan.
  strayFrame,

  /// The answer to the pending query.
  reply,

  /// A scanned barcode.
  barcode,
}

/// How the pending command is answered.
enum ResponseExpectation {
  /// An action: answered by an ACK or an echo.
  ackOrEcho,

  /// A query whose reply starts with a known prefix.
  prefixedReply,

  /// A query whose reply has no prefix, so only timing identifies it.
  unprefixedReply,

  /// Unknown (`sendRaw`): an ACK, an echo, or a reply within the window.
  any,
}

/// The command awaiting a response, as the classifier sees it.
class PendingResponse {
  /// Describes a pending command.
  PendingResponse({
    required this.sentBytes,
    required this.framed,
    required this.expectation,
    this.replyPrefix,
  }) : assert(
         expectation != ResponseExpectation.prefixedReply ||
             replyPrefix != null,
         'a prefixed reply needs a prefix',
       );

  /// The bytes written: the frame, or the bare ASCII for a raw send.
  final Uint8List sentBytes;

  /// Whether [sentBytes] is a frame (only frames get ACKs and echoes).
  final bool framed;

  /// How the command is answered.
  final ResponseExpectation expectation;

  /// The reply prefix of a [ResponseExpectation.prefixedReply] query.
  final String? replyPrefix;

  /// Whether an unprefixed reply is currently accepted. The session opens
  /// the window when the write is issued and closes it a fixed time after
  /// the write completes.
  bool replyWindowOpen = false;
}

/// Classifies one reassembled payload given the [pending] command, if any.
///
/// See the rules in `doc/protocol.md` §4.1. ACKs and frames never become
/// barcodes: a real barcode ends with its terminator.
InboundKind classifyPayload(Uint8List payload, PendingResponse? pending) {
  final acceptsAck =
      pending != null &&
      pending.framed &&
      (pending.expectation == ResponseExpectation.ackOrEcho ||
          pending.expectation == ResponseExpectation.any);

  if (isAck(payload)) {
    return acceptsAck && payload[0] == pending.sentBytes[1]
        ? InboundKind.ack
        : InboundKind.strayAck;
  }

  if (isFrame(payload)) {
    return acceptsAck && _equal(payload, pending.sentBytes)
        ? InboundKind.echo
        : InboundKind.strayFrame;
  }

  if (pending == null) return InboundKind.barcode;

  switch (pending.expectation) {
    case ResponseExpectation.prefixedReply:
      if (_startsWith(payload, pending.replyPrefix!)) return InboundKind.reply;
    case ResponseExpectation.unprefixedReply:
    case ResponseExpectation.any:
      if (pending.replyWindowOpen) return InboundKind.reply;
    case ResponseExpectation.ackOrEcho:
      break;
  }
  return InboundKind.barcode;
}

bool _startsWith(Uint8List bytes, String prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix.codeUnitAt(i)) return false;
  }
  return true;
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
