import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';

import '../helpers/fake_transport.dart';

class _ListenerTransport extends FakeTransport {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> startSppListener(int timeoutMs) async => starts++;

  @override
  Future<void> stopSppListener() async => stops++;
}

void main() {
  group('sppPairingBarcodeData', () {
    test('accepts colon and bare forms', () {
      expect(
        NetumScanner.sppPairingBarcodeData('BC:10:7B:D4:9B:C5'),
        'AT+SPPCONN=BC107BD49BC5',
      );
      expect(
        NetumScanner.sppPairingBarcodeData('bc107bd49bc5'),
        'AT+SPPCONN=BC107BD49BC5',
      );
    });

    test('rejects anything else', () {
      for (final bad in ['', 'BC:10:7B:D4:9B', 'GG:10:7B:D4:9B:C5', '02:00']) {
        expect(
          () => NetumScanner.sppPairingBarcodeData(bad),
          throwsA(isA<NetumInvalidArgument>()),
          reason: bad,
        );
      }
    });
  });

  group('listenForSppScanner', () {
    late _ListenerTransport transport;
    late NetumScanner netum;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      transport = _ListenerTransport();
      netum = NetumScanner.withTransport(transport);
    });

    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      await netum.dispose();
    });

    test('emits the scanner that dialled in once, then closes', () async {
      final scanners = <DiscoveredScanner>[];
      var done = false;
      netum.listenForSppScanner().listen(
        scanners.add,
        onDone: () => done = true,
      );
      await pumpEventQueue();
      expect(transport.starts, 1);

      transport.discoveryController.add(
        DiscoveredDeviceMsg(
          id: 'DC:0D:30:53:36:AF',
          transport: TransportMsg.spp,
          name: 'Netum-03',
          bonded: true,
          serviceUuids: const [],
        ),
      );
      await pumpEventQueue();

      expect(scanners.single.id, 'DC:0D:30:53:36:AF');
      expect(done, isTrue);
      expect(transport.stops, 1);
    });

    test('stopListeningForSppScanner closes it', () async {
      var done = false;
      netum.listenForSppScanner().listen(null, onDone: () => done = true);
      await pumpEventQueue();

      await netum.stopListeningForSppScanner();
      await pumpEventQueue();

      expect(done, isTrue);
      expect(transport.stops, greaterThanOrEqualTo(1));
    });

    test('is unsupported on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await expectLater(
        netum.listenForSppScanner(),
        emitsError(isA<NetumUnsupportedTransport>()),
      );
    });
  });
}
