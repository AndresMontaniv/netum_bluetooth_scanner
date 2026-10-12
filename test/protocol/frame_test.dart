import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

import '../helpers/hex.dart';

void main() {
  group('encodeFrame', () {
    // doc/protocol.md §3.2 and the handoff's B3.1, recomputed independently.
    const vectors = {
      '%#INVMD': '02 0B 0A 25 23 49 4E 56 4D 44 F8 F3 03',
      '%BAT_VOL#': '02 0D 0A 25 42 41 54 5F 56 4F 4C 23 F3 16 03',
      r'$SW#VER': '02 0B 0A 24 53 57 23 56 45 52 F8 42 03',
      '%#+TCNT': '02 0B 0A 25 23 2B 54 43 4E 54 F9 98 03',
      '%SCANTM#1#': '02 0E 0A 25 53 43 41 4E 54 4D 23 31 23 F1 14 03',
      '%SCANTM#3#': '02 0E 0A 25 53 43 41 4E 54 4D 23 33 23 F1 10 03',
      r'$BUZZ#B:': '02 0C 0A 24 42 55 5A 5A 23 42 3A F5 F1 03',
      r'$MOTO#1': '02 0B 0A 24 4D 4F 54 4F 23 31 F8 44 03',
      'AT+NAME=Netum-01':
          '02 14 0A 41 54 2B 4E 41 4D 45 3D 4E 65 74 75 6D 2D 30 31 D6 70 03',
    };

    for (final MapEntry(key: command, value: frame) in vectors.entries) {
      test('encodes $command', () {
        expect(encodeFrame(command), hex(frame));
      });
    }

    test('rejects non-ASCII input', () {
      expect(() => encodeFrame('AT+NAME=Ñandú'), throwsArgumentError);
    });

    test('rejects empty input', () {
      expect(() => encodeFrame(''), throwsArgumentError);
    });

    test('rejects payloads whose LEN byte would overflow', () {
      expect(() => encodeFrame('A' * maxPayloadLength), returnsNormally);
      expect(
        () => encodeFrame('A' * (maxPayloadLength + 1)),
        throwsArgumentError,
      );
    });
  });

  group('isAck', () {
    test('matches [LEN, 0x0B] only', () {
      expect(isAck(hex('0E 0B')), isTrue);
      expect(isAck(hex('0E 0C')), isFalse);
      expect(isAck(hex('0E 0B 0D')), isFalse);
    });
  });

  group('isFrame', () {
    test('matches a well-formed frame', () {
      expect(isFrame(encodeFrame(r'$BUZZ#BK650dc')), isTrue);
    });

    test('rejects a LEN byte that does not match the length', () {
      expect(isFrame(hex('02 06 0A 41 00 00 03')), isFalse);
    });

    test('rejects text', () {
      expect(isFrame('7771609001660\r'.codeUnits), isFalse);
    });
  });
}
