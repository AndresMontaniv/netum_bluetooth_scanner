import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

import '../helpers/fake_transport.dart';

const _id1 = 'DD:0D:30:60:B4:2C';
const _id2 = 'DD:0D:30:53:36:AF';
final List<int> _barcode = '7771609001660\r'.codeUnits;

void main() {
  late FakeTransport transport;
  late NetumScanner netum;

  setUp(() {
    transport = FakeTransport();
    netum = NetumScanner.withTransport(transport);
  });

  tearDown(() => netum.dispose());

  /// Connects [id] and lets the link events settle.
  Future<NetumDevice> connected(String id) async {
    final device = await netum.connect(id, transport: NetumTransport.ble);
    await pumpEventQueue();
    return device;
  }

  group('handles', () {
    test('device() returns the same instance per id', () {
      final a = netum.device(_id1, transport: NetumTransport.ble);
      final b = netum.device(_id1, transport: NetumTransport.ble);

      expect(identical(a, b), isTrue);
      expect(netum.knownDevices, [a]);
    });

    test('connect() keeps the name for display', () async {
      final device = await netum.connect(
        _id1,
        transport: NetumTransport.ble,
        name: 'Netum-01',
      );

      expect(device.name, 'Netum-01');
    });

    test('device() rejects the same id with another transport', () {
      netum.device(_id1, transport: NetumTransport.ble);

      expect(
        () => netum.device(_id1, transport: NetumTransport.spp),
        throwsA(isA<NetumInvalidArgument>()),
      );
    });

    test('initialize is idempotent and re-adopts live links', () async {
      transport.activeLinks = [
        ActiveLinkMsg(id: _id1, transport: TransportMsg.ble, name: 'Netum-01'),
      ];

      await netum.initialize();
      await netum.initialize();

      expect(transport.initializeCalls, 1);
      final device = netum.connectedDevices.single;
      expect(device.id, _id1);
      expect(device.name, 'Netum-01');

      // Scans flow without a new connect.
      final scans = <ScanEvent>[];
      netum.scans.listen(scans.add);
      transport.receive(_id1, _barcode);
      await pumpEventQueue();
      expect(scans.single.text, '7771609001660');
    });
  });

  group('connecting', () {
    test('goes connecting → connected and lists the device', () async {
      final states = <NetumConnectionState>[];
      final device = netum.device(_id1, transport: NetumTransport.ble)
        ..stateChanges.listen(states.add);

      await device.connect();
      await pumpEventQueue();

      expect(states, [
        NetumConnectionState.connecting,
        NetumConnectionState.connected,
      ]);
      expect(netum.connectedDevices, [device]);
    });

    test(
      'a failure reports ConnectFailed and rethrows the mapped error',
      () async {
        transport.connectError = const NetumConnectionFailed(
          'Connect failed (status 133)',
          platformCode: 133,
        );
        final events = <ConnectionEvent>[];
        netum.connectionEvents.listen(events.add);
        final device = netum.device(_id1, transport: NetumTransport.ble);

        await expectLater(
          device.connect(),
          throwsA(isA<NetumConnectionFailed>()),
        );
        await pumpEventQueue();

        expect(device.state, NetumConnectionState.disconnected);
        final reason = events.last.reason;
        expect(reason, isA<ConnectFailed>());
        expect((reason! as ConnectFailed).platformCode, 133);
      },
    );

    test('connecting twice at once throws NetumDeviceBusy', () async {
      transport.emitLinkEvents = false;
      final device = netum.device(_id1, transport: NetumTransport.ble);
      final completer = Completer<void>();
      unawaited(device.connect().then(completer.complete));

      await expectLater(device.connect(), throwsA(isA<NetumDeviceBusy>()));
      await completer.future;
    });

    test('fails fast while Bluetooth is off, without a state change', () async {
      transport.currentAdapterState = AdapterStateMsg.poweredOff;
      final device = netum.device(_id1, transport: NetumTransport.ble);
      final states = <NetumConnectionState>[];
      device.stateChanges.listen(states.add);

      await expectLater(
        device.connect(),
        throwsA(
          isA<NetumBluetoothUnavailable>().having(
            (e) => e.state,
            'state',
            AdapterState.poweredOff,
          ),
        ),
      );
      expect(transport.connects, isEmpty);
      expect(states, isEmpty);
    });

    test('maxConnections is enforced', () async {
      netum.maxConnections = 1;
      await connected(_id1);

      await expectLater(
        netum.connect(_id2, transport: NetumTransport.ble),
        throwsA(isA<NetumMaxConnectionsReached>()),
      );
    });

    test('maxConnections must be 1–7', () {
      expect(
        () => netum.maxConnections = 0,
        throwsA(isA<NetumInvalidArgument>()),
      );
      expect(
        () => netum.maxConnections = 8,
        throwsA(isA<NetumInvalidArgument>()),
      );
    });

    test('devices emits when membership or state changes', () async {
      final lists = <List<NetumDevice>>[];
      netum.devices.listen(lists.add);

      await connected(_id1);

      expect(lists, isNotEmpty);
      expect(lists.last.single.state, NetumConnectionState.connected);
    });
  });

  group('routing', () {
    test('each scan carries its device, globally and per device', () async {
      final d1 = await connected(_id1);
      final d2 = await connected(_id2);
      final global = <ScanEvent>[];
      final perDevice1 = <ScanEvent>[];
      final perDevice2 = <ScanEvent>[];
      netum.scans.listen(global.add);
      d1.scans.listen(perDevice1.add);
      d2.scans.listen(perDevice2.add);

      transport
        ..receive(_id1, _barcode)
        ..receive(_id2, 'ABC\r'.codeUnits);
      await pumpEventQueue();

      expect(global.map((e) => (e.deviceId, e.text)), [
        (_id1, '7771609001660'),
        (_id2, 'ABC'),
      ]);
      expect(perDevice1.single.device, same(d1));
      expect(perDevice2.single.raw, 'ABC\r'.codeUnits);
      expect(netum.connectedDevices, hasLength(2));
    });

    test('device streams survive a reconnect', () async {
      final device = await connected(_id1);
      final scans = <ScanEvent>[];
      device.scans.listen(scans.add);

      transport.link(_id1, LinkStateMsg.disconnected, code: 8);
      await pumpEventQueue();
      await device.connect();
      await pumpEventQueue();
      transport.receive(_id1, _barcode);
      await pumpEventQueue();

      expect(scans, hasLength(1));
    });

    test('ACKs and replies are not scans', () async {
      final device = await connected(_id1);
      final scans = <ScanEvent>[];
      netum.scans.listen(scans.add);

      final battery = device.getBattery();
      await pumpEventQueue();
      transport.receive(_id1, 'BAT_VOL=3.81V 37%\r'.codeUnits);
      expect((await battery).percent, 37);

      transport.receive(_id1, [0x0E, 0x0B]);
      await pumpEventQueue();
      expect(scans, isEmpty);
    });
  });

  group('disconnect reasons', () {
    Future<DisconnectReason?> reasonAfter(
      Future<void> Function(NetumDevice device) action,
    ) async {
      final device = await connected(_id1);
      final events = <ConnectionEvent>[];
      netum.connectionEvents.listen(events.add);
      await action(device);
      await pumpEventQueue();
      return events
          .lastWhere((e) => e.state == NetumConnectionState.disconnected)
          .reason;
    }

    test('user disconnect → UserRequested', () async {
      expect(await reasonAfter((d) => d.disconnect()), isA<UserRequested>());
    });

    test('status 8 → LinkLost(8)', () async {
      final reason = await reasonAfter((_) async {
        transport.link(_id1, LinkStateMsg.disconnected, code: 8);
      });
      expect(reason, isA<LinkLost>());
      expect((reason! as LinkLost).platformCode, 8);
    });

    test('status 19 → RemoteTerminated(19)', () async {
      final reason = await reasonAfter((_) async {
        transport.link(_id1, LinkStateMsg.disconnected, code: 19);
      });
      expect(reason, isA<RemoteTerminated>());
    });

    test('Bluetooth off → BluetoothOff', () async {
      final reason = await reasonAfter((_) async {
        transport.adapterStateController.add(AdapterStateMsg.poweredOff);
        await pumpEventQueue();
        transport.link(_id1, LinkStateMsg.disconnected, code: 8);
      });
      expect(reason, isA<BluetoothOff>());
    });

    test('a link-dropping command → ExpectedAfterCommand', () async {
      final reason = await reasonAfter((device) async {
        final result = device.send(NetumCommand.power.powerOff);
        await pumpEventQueue();
        transport.link(_id1, LinkStateMsg.disconnected, code: 19);
        expect((await result).outcome, CommandOutcome.disconnected);
      });
      expect(reason, isA<ExpectedAfterCommand>());
    });
  });

  group('commands', () {
    test('triggerScan writes the frame and completes on the ACK', () async {
      final device = await connected(_id1);

      final trigger = device.triggerScan(seconds: 3);
      await pumpEventQueue();
      expect(transport.writes.single.$2, encodeFrame('%SCANTM#3#'));
      transport.receive(_id1, [0x0E, 0x0B]);

      await trigger;
    });

    test('triggerScan validates its range', () async {
      final device = await connected(_id1);

      await expectLater(
        device.triggerScan(seconds: 8),
        throwsA(isA<NetumInvalidArgument>()),
      );
    });

    test('getFirmwareVersion returns the unprefixed reply', () async {
      final device = await connected(_id1);

      final version = device.getFirmwareVersion();
      await pumpEventQueue();
      transport.receive(_id1, 'bn0HDS_RFSBTD43bc_CB071\r'.codeUnits);

      expect(await version, 'bn0HDS_RFSBTD43bc_CB071');
    });

    test('an unparseable battery reply throws NetumUnexpectedReply', () async {
      final device = await connected(_id1);

      final battery = expectLater(
        device.getBattery(),
        throwsA(isA<NetumUnexpectedReply>()),
      );
      await pumpEventQueue();
      transport.receive(_id1, 'BAT_VOL=?\r'.codeUnits);

      await battery;
    });

    test('commands while disconnected throw NetumNotConnected', () async {
      final device = netum.device(_id1, transport: NetumTransport.ble);

      await expectLater(device.beep(), throwsA(isA<NetumNotConnected>()));
      await expectLater(device.readRssi(), throwsA(isA<NetumNotConnected>()));
    });

    test('getDeviceInfo reads 180A and derives the Classic MAC', () async {
      final device = await connected(_id1);

      final info = await device.getDeviceInfo();

      expect(info.manufacturer, 'Feasycom');
      expect(info.model, 'FSC-BT825');
      expect(info.serial, 'DC0D3060B42C');
      expect(info.classicAddress, 'DC:0D:30:60:B4:2C');
      expect(info.hardwareRevision, '1.1');
      // No 2A26 on the DS5000: falls back to the software revision.
      expect(info.firmwareRevision, '1.6.2');
    });

    test('readRssi', () async {
      final device = await connected(_id1);
      expect(await device.readRssi(), -48);
    });
  });

  group('discovery', () {
    test('de-duplicates and re-emits on RSSI changes', () async {
      final found = <DiscoveredScanner>[];
      netum.discover().listen(found.add);
      await pumpEventQueue();

      transport
        ..found(_id1, name: 'Netum-01', rssi: -50)
        ..found(_id1, name: 'Netum-01', rssi: -50)
        ..found(_id1, name: 'Netum-01', rssi: -48);
      await pumpEventQueue();

      expect(found.map((d) => d.rssi), [-50, -48]);
      expect(found.first.likelyNetum, isTrue);
      expect(transport.discoveryStarts.single.filterNetum, isTrue);
    });

    test('filtered discovery drops non-NETUM results in flight', () async {
      final found = <DiscoveredScanner>[];
      netum.discover().listen(found.add);
      await pumpEventQueue();

      transport
        ..found('34:89:0E:C0:E5:B5', uuids: [])
        ..found(_id1);
      await pumpEventQueue();

      expect(found.map((d) => d.id), [_id1]);
    });

    test('computes likelyNetum for unfiltered results', () async {
      final found = <DiscoveredScanner>[];
      netum.discover(filter: DiscoveryFilter.all).listen(found.add);
      await pumpEventQueue();

      transport
        ..found(_id1)
        ..found(
          'A8:A2:37:E7:F7:A9',
          uuids: ['0000FEB9-0000-1000-8000-00805F9B34FB'],
        );
      await pumpEventQueue();

      expect(found.map((d) => d.likelyNetum), [true, false]);
      expect(transport.discoveryStarts.single.filterNetum, isFalse);
    });

    test('closes after the timeout and stops native discovery', () {
      fakeAsync((async) {
        var done = false;
        netum
            .discover(timeout: const Duration(seconds: 5))
            .listen(null, onDone: () => done = true);
        async.elapse(const Duration(milliseconds: 4999));
        expect(done, isFalse);
        expect(netum.isDiscovering, isTrue);

        async.elapse(const Duration(milliseconds: 1));
        expect(done, isTrue);
        expect(netum.isDiscovering, isFalse);
        expect(transport.discoveryStops, 1);
      });
    });

    test('start errors arrive on the stream, which then closes', () async {
      transport.discoveryError = NetumPermissionDenied(['BLUETOOTH_SCAN']);

      await expectLater(
        netum.discover(),
        emitsInOrder([emitsError(isA<NetumPermissionDenied>()), emitsDone]),
      );
    });

    test('a new discovery ends the previous one', () async {
      var firstDone = false;
      netum.discover().listen(null, onDone: () => firstDone = true);
      await pumpEventQueue();

      netum.discover().listen(null);
      await pumpEventQueue();

      expect(firstDone, isTrue);
      expect(transport.discoveryStarts, hasLength(2));
    });

    test('stopDiscovery closes the stream', () async {
      var done = false;
      netum.discover().listen(null, onDone: () => done = true);
      await pumpEventQueue();

      await netum.stopDiscovery();

      expect(done, isTrue);
      expect(transport.discoveryStops, 1);
    });
  });

  group('environment', () {
    test(
      'adapterState emits the current state on listen, then changes',
      () async {
        await netum.initialize();
        final states = <AdapterState>[];
        netum.adapterState.listen(states.add);
        await pumpEventQueue();

        transport.adapterStateController.add(AdapterStateMsg.poweredOff);
        await pumpEventQueue();

        expect(states, [AdapterState.poweredOn, AdapterState.poweredOff]);
        expect(netum.currentAdapterState, AdapterState.poweredOff);
      },
    );

    test('adapterState does not emit unknown before initialization', () async {
      final states = <AdapterState>[];
      netum.adapterState.listen(states.add);
      await pumpEventQueue();

      expect(states, [AdapterState.poweredOn]);
    });

    test('permissions map to the public enums', () async {
      expect(await netum.checkPermissions(), PermissionStatus.denied);
      expect(await netum.requestPermissions(), PermissionStatus.granted);
    });
  });
}
