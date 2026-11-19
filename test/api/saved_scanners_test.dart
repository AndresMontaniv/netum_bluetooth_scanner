import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';

import '../helpers/fake_transport.dart';

const _a = 'DD:0D:30:60:B4:2C';
const _b = 'DD:0D:30:60:B5:1D';
const _c = 'DD:0D:30:53:36:AF';
const _sppA = 'DC:0D:30:60:B4:2C';
const _sppB = 'DC:0D:30:60:B5:1D';

/// A transport where only [reachable] devices connect.
class _PickyTransport extends FakeTransport {
  _PickyTransport(this.reachable);

  final Set<String> reachable;

  /// SPP devices the phone is paired with.
  final paired = <String>{};

  @override
  Future<List<DiscoveredDeviceMsg>> bondedDevices() async => [
    for (final id in paired)
      DiscoveredDeviceMsg(
        id: id,
        transport: TransportMsg.spp,
        bonded: true,
        serviceUuids: const [],
      ),
  ];

  @override
  Future<void> connect(String id, ConnectOptionsMsg options) async {
    if (!reachable.contains(id)) {
      connects.add(id);
      throw const NetumConnectionFailed('Connect timed out');
    }
    return super.connect(id, options);
  }
}

class _MemoryStore implements NetumStore {
  String? json;
  int saves = 0;

  @override
  Future<String?> load() async => json;

  @override
  Future<void> save(String json) async {
    saves++;
    this.json = json;
  }
}

void main() {
  late FakeTransport transport;
  late NetumScanner netum;

  setUp(() {
    transport = FakeTransport();
    netum = NetumScanner.withTransport(transport);
  });

  tearDown(() => netum.dispose());

  test('connect remembers the device, most recent first', () async {
    await netum.connect(_a, transport: NetumTransport.ble, name: 'Netum-01');
    await netum.connect(
      _b,
      transport: NetumTransport.ble,
      autoReconnect: true,
      reconnectPolicy: const ReconnectPolicy(giveUpAfter: Duration(minutes: 5)),
    );

    final saved = await netum.savedScanners();
    expect(saved.map((s) => s.id), [_b, _a]);
    expect(saved.first.autoReconnect, isTrue);
    expect(
      saved.first.reconnectPolicy.giveUpAfter,
      const Duration(minutes: 5),
    );
    expect(saved.last.name, 'Netum-01');
    expect(transport.savedJson, isNotNull);
  });

  test('reconnecting a saved device moves it to the top', () async {
    await netum.connect(_a, transport: NetumTransport.ble);
    await netum.connect(_b, transport: NetumTransport.ble);
    await netum.device(_a, transport: NetumTransport.ble).disconnect();
    await netum.connect(_a, transport: NetumTransport.ble);

    expect((await netum.savedScanners()).map((s) => s.id), [_a, _b]);
  });

  test('setName updates the saved name without reordering', () async {
    await netum.connect(_a, transport: NetumTransport.ble);
    final b = await netum.connect(_b, transport: NetumTransport.ble);

    final rename = b.setName('Netum-02');
    await pumpEventQueue();
    transport.link(_b, LinkStateMsg.disconnected, code: 19);
    await rename;

    final saved = await netum.savedScanners();
    expect(saved.map((s) => s.id), [_b, _a]);
    expect(saved.first.name, 'Netum-02');
  });

  group('getBluetoothInfo reads the real name', () {
    late _MemoryStore store;

    setUp(() => netum.store = store = _MemoryStore());

    /// Answers the `AT+NAME`, `AT+ADDR`, `AT+VER` queries of [device].
    Future<BluetoothInfo> bluetoothInfo(NetumDevice device, String name) async {
      final info = device.getBluetoothInfo();
      for (final reply in ['+NAME=$name', '+ADDR=DC0D3060B42C', '+VER=1.6.2']) {
        await pumpEventQueue();
        transport.receive(device.id, '$reply\r'.codeUnits);
      }
      return info;
    }

    test(
      'a new name updates the handle, the saved entry and devices',
      () async {
        await netum.connect(_a, transport: NetumTransport.ble);
        final b = await netum.connect(
          _b,
          transport: NetumTransport.ble,
          name: 'Old name',
        );
        final lists = <List<NetumDevice>>[];
        final sub = netum.devices.listen(lists.add);

        final info = await bluetoothInfo(b, 'New name');
        await pumpEventQueue();

        expect(info.name, 'New name');
        expect(b.name, 'New name');
        final saved = await netum.savedScanners();
        expect(saved.map((s) => s.id), [_b, _a]);
        expect(saved.first.name, 'New name');
        expect(lists, isNotEmpty);
        await sub.cancel();
      },
    );

    test('the same name writes nothing and emits nothing', () async {
      final a = await netum.connect(
        _a,
        transport: NetumTransport.ble,
        name: 'Netum-01',
      );
      await pumpEventQueue();
      final saves = store.saves;
      final lists = <List<NetumDevice>>[];
      final sub = netum.devices.listen(lists.add);

      await bluetoothInfo(a, 'Netum-01');
      await pumpEventQueue();

      expect(store.saves, saves);
      expect(lists, isEmpty);
      await sub.cancel();
    });

    test('an unsaved device stays unsaved', () async {
      final a = await netum.connect(
        _a,
        transport: NetumTransport.ble,
        name: 'Old name',
        remember: false,
      );

      await bluetoothInfo(a, 'New name');

      expect(a.name, 'New name');
      expect(await netum.savedScanners(), isEmpty);
      expect(store.saves, 0);
    });
  });

  test('remember: false skips saving', () async {
    await netum.connect(_a, transport: NetumTransport.ble, remember: false);

    expect(await netum.savedScanners(), isEmpty);
  });

  test('forgetScanner removes an entry', () async {
    await netum.connect(_a, transport: NetumTransport.ble);
    await netum.connect(_b, transport: NetumTransport.ble);

    await netum.forgetScanner(_a);

    expect((await netum.savedScanners()).map((s) => s.id), [_b]);
  });

  test('a custom store replaces native storage', () async {
    final store = _MemoryStore();
    netum.store = store;

    await netum.connect(_a, transport: NetumTransport.ble);

    expect(store.json, contains(_a));
    expect(transport.savedJson, isNull);
  });

  test('corrupt stored data reads as an empty list', () async {
    transport.savedJson = '{not json';

    expect(await netum.savedScanners(), isEmpty);
  });

  test('SavedScanner JSON round-trip keeps the unlimited policy', () {
    final scanner = SavedScanner(
      id: _a,
      transport: NetumTransport.ble,
      name: 'Netum-01',
      lastConnected: DateTime.utc(2026, 10, 13, 9),
      autoReconnect: true,
      reconnectPolicy: ReconnectPolicy.unlimited,
    );

    expect(SavedScanner.fromJson(scanner.toJson()), scanner);
  });

  group('restoreSaved', () {
    Future<void> save(List<String> mostRecentFirst) async {
      for (final id in mostRecentFirst.reversed) {
        await netum.connect(
          id,
          transport: NetumTransport.ble,
          autoReconnect: true,
        );
        await netum.device(id, transport: NetumTransport.ble).disconnect();
      }
    }

    test('firstAvailable tries the most recent, then the next', () async {
      final picky = _PickyTransport({_a, _b, _c});
      netum = NetumScanner.withTransport(picky);
      await save([_a, _b, _c]);
      picky.connects.clear();

      // _a is off: the car radio falls back to _b and stops there.
      picky.reachable.remove(_a);
      final restored = await netum.restoreSaved();

      expect(restored.map((d) => d.id), [_b]);
      expect(picky.connects, [_a, _b]);
      expect(restored.single.autoReconnect, isTrue);
    });

    test('all reconnects every reachable saved scanner', () async {
      final picky = _PickyTransport({_a, _b, _c});
      netum = NetumScanner.withTransport(picky);
      await save([_a, _b, _c]);
      picky.reachable.remove(_b);

      final restored = await netum.restoreSaved(strategy: RestoreStrategy.all);

      expect(restored.map((d) => d.id).toSet(), {_a, _c});
    });

    test('skips saved SPP scanners that are no longer paired', () async {
      final picky = _PickyTransport({_a, _sppA, _sppB});
      netum = NetumScanner.withTransport(picky);
      for (final (id, transport) in [
        (_sppA, NetumTransport.spp),
        (_sppB, NetumTransport.spp),
        (_a, NetumTransport.ble),
      ]) {
        await netum.connect(id, transport: transport);
        await netum.device(id, transport: transport).disconnect();
      }
      picky
        ..connects.clear()
        // The user forgot _sppB in the Bluetooth settings.
        ..paired.add(_sppA);

      final restored = await netum.restoreSaved(strategy: RestoreStrategy.all);

      expect(restored.map((d) => d.id).toSet(), {_a, _sppA});
      expect(picky.connects, isNot(contains(_sppB)));
      // Still saved: restored again once it is paired.
      expect((await netum.savedScanners()).map((s) => s.id), contains(_sppB));
    });

    test('nothing saved restores nothing', () async {
      expect(await netum.restoreSaved(), isEmpty);
    });
  });
}
