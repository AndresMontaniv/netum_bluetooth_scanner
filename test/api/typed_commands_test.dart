import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

import '../helpers/fake_transport.dart';

const _id = 'DD:0D:30:60:B4:2C';

void main() {
  late FakeTransport transport;
  late NetumScanner netum;
  late NetumDevice device;

  setUp(() async {
    transport = FakeTransport();
    netum = NetumScanner.withTransport(transport);
    device = await netum.connect(_id, transport: NetumTransport.ble);
    await pumpEventQueue();
  });

  tearDown(() => netum.dispose());

  /// Runs [call], answers its write with an ACK, and returns the ASCII sent.
  Future<String> acked(Future<void> Function() call) async {
    final done = call();
    await pumpEventQueue();
    final frame = transport.writes.last.$2;
    transport.receive(_id, [frame[1], 0x0B]);
    await done;
    return String.fromCharCodes(frame.sublist(3, frame.length - 3));
  }

  /// Runs [call], answers with [reply], and returns its result.
  Future<T> replied<T>(Future<T> Function() call, String reply) async {
    final result = call();
    await pumpEventQueue();
    transport.receive(_id, '$reply\r'.codeUnits);
    return result;
  }

  group('settings send the catalog command', () {
    final cases = <String, Future<void> Function(NetumDevice)>{
      r'$BUZZ#2': (d) => d.setVolume(BeepVolume.medium),
      r'$BUZZ#5': (d) => d.setTone(BeepTone.low),
      r'$MOTO#0': (d) => d.setVibration(enabled: false),
      '%ACKBEEP#0': (d) => d.setCommandConfirmationBeep(enabled: false),
      '%SCMD#03#': (d) => d.setScanMode(ScanMode.hostTrigger),
      r'$RF#ST00': (d) => d.setSleepTimeout(SleepTimeout.never),
      r'$TERM#1': (d) => d.setTerminator(Terminator.cr),
      '%#INVMD': (d) => d.setWorkMode(WorkMode.store),
      '%#NORMD': (d) => d.setWorkMode(WorkMode.normal),
      '%#TXMEM': (d) => d.uploadStored(),
      '%#TXMEM#C': (d) => d.uploadStored(clearAfter: true),
      '%#*NEW*': (d) => d.clearStored(),
    };
    for (final MapEntry(key: ascii, value: call) in cases.entries) {
      test(ascii, () async {
        expect(await acked(() => call(device)), ascii);
      });
    }
  });

  test('powerOff completes when the link drops', () async {
    final done = device.powerOff();
    await pumpEventQueue();
    expect(transport.writes.last.$2, encodeFrame(r'$POWER#OFF'));
    transport.link(_id, LinkStateMsg.disconnected, code: 19);

    await done;
    expect(device.state, NetumConnectionState.disconnected);
  });

  group('queries', () {
    test('getEngineModel', () async {
      expect(await replied(device.getEngineModel, 'SE4750'), 'SE4750');
    });

    test('getSleepTimeout parses minutes', () async {
      expect(
        await replied(device.getSleepTimeout, 'Sleeptime=30min'),
        const Duration(minutes: 30),
      );
    });

    test('getSleepTimeout maps zero and "never" to null', () async {
      expect(await replied(device.getSleepTimeout, 'Sleeptime=0min'), isNull);
      expect(await replied(device.getSleepTimeout, 'Sleeptime=Never'), isNull);
    });

    test('getStoredCount', () async {
      expect(await replied(device.getStoredCount, 'Total Counters=3'), 3);
    });

    test(
      'an unexpected stored-count reply throws NetumUnexpectedReply',
      () async {
        final result = expectLater(
          device.getStoredCount(),
          throwsA(isA<NetumUnexpectedReply>()),
        );
        await pumpEventQueue();
        transport.receive(_id, 'Total Counters=?\r'.codeUnits);
        await result;
      },
    );
  });

  group('identity', () {
    test('setName sends AT+NAME= and updates the handle name', () async {
      final done = device.setName('Netum-02');
      await pumpEventQueue();
      expect(transport.writes.last.$2, encodeFrame('AT+NAME=Netum-02'));
      transport.link(_id, LinkStateMsg.disconnected, code: 19);
      await done;

      expect(device.name, 'Netum-02');
    });

    test('setName validates the name', () async {
      await expectLater(
        device.setName(''),
        throwsA(isA<NetumInvalidArgument>()),
      );
    });

    test('switchMode sends AT+MODE= and completes on the drop', () async {
      final done = device.switchMode(NetumMode.spp);
      await pumpEventQueue();
      expect(transport.writes.last.$2, encodeFrame('AT+MODE=1'));
      transport.link(_id, LinkStateMsg.disconnected, code: 19);
      await done;
    });

    test('getBluetoothInfo runs the three AT queries', () async {
      final info = device.getBluetoothInfo();
      for (final reply in [
        '+NAME=Netum-01',
        '+ADDR=DC0D3060B42C',
        '+VER=1.6.2\x00',
      ]) {
        await pumpEventQueue();
        transport.receive(_id, '$reply\r'.codeUnits);
      }

      final result = await info;
      expect(result.name, 'Netum-01');
      expect(result.classicAddress, 'DC:0D:30:60:B4:2C');
      expect(result.firmware, '1.6.2');
      expect(
        transport.writes.map((w) => w.$2).toList(),
        [encodeFrame('AT+NAME'), encodeFrame('AT+ADDR'), encodeFrame('AT+VER')],
      );
    });
  });
}
