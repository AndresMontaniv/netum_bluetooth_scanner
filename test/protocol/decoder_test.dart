import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/src/protocol/decoder.dart';

import '../helpers/hex.dart';

void main() {
  Uint8List ascii(String text) => Uint8List.fromList(text.codeUnits);

  test('strips the trailing CR of a barcode', () {
    expect(decodePayload(ascii('7771609001660\r')), '7771609001660');
  });

  test('strips NUL bytes and the CR of a +VER reply', () {
    expect(decodePayload(ascii('+VER=1.6.2\x00\r')), '+VER=1.6.2');
  });

  test('strips CRLF, LF and TAB terminators', () {
    expect(decodePayload(ascii('A\r\n')), 'A');
    expect(decodePayload(ascii('B\n')), 'B');
    expect(decodePayload(ascii('C\t')), 'C');
  });

  test('keeps inner terminators of a misread', () {
    expect(
      decodePayload(hex('3C 0D 2A 45 4D 4E 4F 3B 0D')),
      '<\r*EMNO;',
    );
  });

  test('decodes UTF-8', () {
    final raw = Uint8List.fromList([...utf8.encode('Ñandú'), 0x0D]);
    expect(decodePayload(raw), 'Ñandú');
  });

  test('falls back to Latin-1 for invalid UTF-8', () {
    // 0xD1 alone is "Ñ" in Latin-1 but an incomplete UTF-8 sequence.
    expect(decodePayload(hex('D1 41 0D')), 'ÑA');
  });

  test('leaves the raw bytes unchanged', () {
    final raw = ascii('+VER=1.6.2\x00\r');
    final copy = Uint8List.fromList(raw);

    decodePayload(raw);

    expect(raw, copy);
  });

  test('decodes a payload that is only a terminator to an empty string', () {
    expect(decodePayload(ascii('\r')), isEmpty);
  });
}
