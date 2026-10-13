import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';

import '../helpers/fake_transport.dart';

DiscoveredDeviceMsg _spp(
  String id, {
  String? name,
  List<String> uuids = const [],
  bool bonded = false,
}) => DiscoveredDeviceMsg(
  id: id,
  transport: TransportMsg.spp,
  name: name,
  bonded: bonded,
  serviceUuids: uuids,
);

class _SppTransport extends FakeTransport {
  List<DiscoveredDeviceMsg> bonded = [];

  @override
  Future<List<DiscoveredDeviceMsg>> bondedDevices() async => bonded;
}

void main() {
  late _SppTransport transport;
  late NetumScanner netum;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    transport = _SppTransport();
    netum = NetumScanner.withTransport(transport);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await netum.dispose();
  });

  test(
    'SPP likelyNetum: DC:0D:30 prefix, SPP UUID or a NETUM-like name',
    () async {
      final found = <DiscoveredScanner>[];
      netum.discover(transport: NetumTransport.spp).listen(found.add);
      await pumpEventQueue();

      [
        _spp('DC:0D:30:60:B5:1D', name: 'Netum-02'),
        _spp('11:22:33:44:55:66', name: 'DS barcode scanner'),
        _spp(
          '22:33:44:55:66:77',
          uuids: ['00001101-0000-1000-8000-00805F9B34FB'],
        ),
        _spp('00:1A:7D:DA:71:15', name: 'LAPTOP-MARCELO'),
        _spp('33:44:55:66:77:88', name: 'Dell Mouse'),
      ].forEach(transport.discoveryController.add);
      await pumpEventQueue();

      expect(found.map((d) => d.id), [
        'DC:0D:30:60:B5:1D',
        '11:22:33:44:55:66',
        '22:33:44:55:66:77',
      ]);
      expect(found.every((d) => d.transport == NetumTransport.spp), isTrue);
      expect(transport.discoveryStarts.single.transport, TransportMsg.spp);
    },
  );

  test('bondedScanners filters and marks bonded', () async {
    transport.bonded = [
      _spp('DC:0D:30:60:B4:2C', name: 'Netum-01', bonded: true),
      _spp('33:44:55:66:77:88', name: 'Dell Mouse', bonded: true),
    ];

    final likely = await netum.bondedScanners();
    final all = await netum.bondedScanners(filter: DiscoveryFilter.all);

    expect(likely.single.name, 'Netum-01');
    expect(likely.single.bonded, isTrue);
    expect(all, hasLength(2));
    expect(all.last.likelyNetum, isFalse);
  });

  test('bondedScanners is empty on iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    transport.bonded = [_spp('DC:0D:30:60:B4:2C', bonded: true)];

    expect(await netum.bondedScanners(), isEmpty);
  });
}
