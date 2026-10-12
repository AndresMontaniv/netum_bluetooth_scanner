import 'dart:convert';
import 'dart:typed_data';

/// Decodes a payload to text: drops the trailing terminators (CR, LF, TAB)
/// and every NUL byte, then decodes strict UTF-8, falling back to Latin-1.
///
/// [raw] is not modified; callers keep it as the original bytes.
String decodePayload(Uint8List raw) {
  var end = raw.length;
  while (end > 0 && _isTerminator(raw[end - 1])) {
    end--;
  }
  final bytes = [
    for (var i = 0; i < end; i++)
      if (raw[i] != 0x00) raw[i],
  ];
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

bool _isTerminator(int byte) => byte == 0x0D || byte == 0x0A || byte == 0x09;
