import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/src/protocol/reassembler.dart';

import '../helpers/fixtures.dart';
import '../helpers/hex.dart';

void main() {
  late List<Uint8List> payloads;
  late Reassembler reassembler;

  setUp(() {
    payloads = [];
    reassembler = Reassembler(onPayload: payloads.add);
  });

  Uint8List ascii(String text) => Uint8List.fromList(text.codeUnits);

  test('every captured inbound packet comes out as exactly one payload', () {
    for (final packet in loadInboundFixtures()) {
      payloads.clear();
      reassembler.add(packet.bytes);
      expect(payloads, [packet.bytes], reason: toHex(packet.bytes));
    }
  });

  test('the misread with an embedded CR stays one payload', () {
    reassembler.add(hex('3C 0D 2A 45 4D 4E 4F 3B 0D'));

    expect(payloads, [hex('3C 0D 2A 45 4D 4E 4F 3B 0D')]);
  });

  test('an ACK passes through unbuffered', () {
    reassembler.add(hex('0E 0B'));

    expect(payloads, [hex('0E 0B')]);
  });

  test('two halves without a terminator join on the idle flush', () {
    fakeAsync((async) {
      reassembler
        ..add(ascii('NETUM-DS5000'))
        ..add(ascii('-LONG'));
      async.elapse(const Duration(milliseconds: 99));
      expect(payloads, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      expect(payloads, [ascii('NETUM-DS5000-LONG')]);
    });
  });

  test('the idle timer restarts with every chunk', () {
    fakeAsync((async) {
      reassembler.add(ascii('ABC'));
      async.elapse(const Duration(milliseconds: 80));
      reassembler.add(ascii('DEF'));
      async.elapse(const Duration(milliseconds: 80));
      expect(payloads, isEmpty);

      async.elapse(const Duration(milliseconds: 20));
      expect(payloads, [ascii('ABCDEF')]);
    });
  });

  test('a terminated chunk completes a buffered payload at once', () {
    fakeAsync((async) {
      reassembler
        ..add(ascii('NETUM-DS5000'))
        ..add(ascii('-LONG\r'));

      expect(payloads, [ascii('NETUM-DS5000-LONG\r')]);
      async.elapse(const Duration(seconds: 1));
      expect(payloads, hasLength(1));
    });
  });

  test('CRLF, LF and TAB also terminate', () {
    reassembler
      ..add(ascii('A\r\n'))
      ..add(ascii('B\n'))
      ..add(ascii('C\t'));

    expect(payloads, [ascii('A\r\n'), ascii('B\n'), ascii('C\t')]);
  });

  test('buffered bytes are flushed before an ACK, keeping order', () {
    fakeAsync((async) {
      reassembler
        ..add(ascii('PARTIAL'))
        ..add(hex('0E 0B'));

      expect(payloads, [ascii('PARTIAL'), hex('0E 0B')]);
    });
  });

  test('buffered bytes are flushed before a frame, keeping order', () {
    fakeAsync((async) {
      final echo = hex('02 0F 0A 25 52 54 43 53 54 41 4D 50 23 30 EC D2 03');
      reassembler
        ..add(ascii('PARTIAL'))
        ..add(echo);

      expect(payloads, [ascii('PARTIAL'), echo]);
    });
  });

  test('reset drops buffered bytes and the pending flush', () {
    fakeAsync((async) {
      reassembler
        ..add(ascii('PARTIAL'))
        ..reset();
      async.elapse(const Duration(seconds: 1));

      expect(payloads, isEmpty);
    });
  });

  test('empty chunks are ignored', () {
    reassembler.add(Uint8List(0));

    expect(payloads, isEmpty);
  });
}
