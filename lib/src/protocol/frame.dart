import 'dart:typed_data';

/// Start-of-frame byte.
const int stx = 0x02;

/// End-of-frame byte.
const int etx = 0x03;

/// Frame type byte for commands.
const int commandType = 0x0A;

/// Second byte of a 2-byte ACK `[LEN, 0x0B]`.
const int ackMarker = 0x0B;

/// Largest payload whose LEN byte (`n + 4`) still fits in one byte.
const int maxPayloadLength = 0xFF - 4;

/// Wraps an ASCII command in a NETUM frame:
/// `02 | n+4 | 0A | payload | ck_hi ck_lo | 03`.
///
/// The checksum is a weighted sum in 16-bit two's complement (see
/// `doc/protocol.md` §3.1).
///
/// Throws an [ArgumentError] if [ascii] is empty, longer than
/// [maxPayloadLength], or contains a byte above 0x7F.
Uint8List encodeFrame(String ascii) {
  final n = ascii.length;
  if (n == 0 || n > maxPayloadLength) {
    throw ArgumentError.value(
      ascii,
      'ascii',
      'must be 1–$maxPayloadLength characters',
    );
  }
  final payload = ascii.codeUnits;
  if (payload.any((unit) => unit > 0x7F)) {
    throw ArgumentError.value(ascii, 'ascii', 'must be ASCII only');
  }

  var sum = (n + 4) * (n + 2) + commandType * (n + 1);
  for (var i = 0; i < n; i++) {
    sum += payload[i] * (n - i);
  }
  final checksum = (0x10000 - (sum & 0xFFFF)) & 0xFFFF;

  return Uint8List.fromList([
    stx,
    n + 4,
    commandType,
    ...payload,
    checksum >> 8,
    checksum & 0xFF,
    etx,
  ]);
}

/// Whether [bytes] is a 2-byte ACK `[LEN, 0x0B]`.
bool isAck(List<int> bytes) => bytes.length == 2 && bytes[1] == ackMarker;

/// Whether [bytes] has the shape of a frame: `02 … 03` with a LEN byte that
/// matches its length.
bool isFrame(List<int> bytes) =>
    bytes.length >= 6 &&
    bytes.first == stx &&
    bytes.last == etx &&
    bytes[1] == bytes.length - 2;
