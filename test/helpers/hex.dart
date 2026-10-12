import 'dart:typed_data';

/// Parses space-separated hex bytes, e.g. `'02 0B 0A'`.
Uint8List hex(String bytes) => Uint8List.fromList([
  for (final byte in bytes.trim().split(RegExp(r'\s+')))
    if (byte.isNotEmpty) int.parse(byte, radix: 16),
]);

/// Formats bytes as uppercase space-separated hex.
String toHex(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');
