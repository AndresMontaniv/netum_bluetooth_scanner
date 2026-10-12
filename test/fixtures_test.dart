import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';
import 'helpers/hex.dart';

void main() {
  final inbound = loadInboundFixtures();

  test('fixtures cover every packet kind', () {
    final kinds = inbound.map((p) => p.kind).toSet();
    expect(kinds, containsAll(<String>['ack', 'echo', 'reply', 'barcode']));
  });

  test('fixtures include prefixed and unprefixed replies', () {
    final replies = inbound.where((p) => p.kind == 'reply');
    expect(
      replies.map((p) => String.fromCharCodes(p.bytes)),
      containsAll(<String>[
        'BAT_VOL=3.81V 37%\r',
        'SE4750\r',
        '+VER=1.6.2\x00\r',
      ]),
    );
  });

  test('fixtures include the misread with an embedded CR', () {
    expect(
      inbound.where((p) => toHex(p.bytes) == '3C 0D 2A 45 4D 4E 4F 3B 0D'),
      isNotEmpty,
    );
  });

  test('fixtures include BLE and SPP traffic', () {
    expect(
      loadFixtureSessions().map((s) => s.transport).toSet(),
      {'ble', 'spp'},
    );
  });
}
