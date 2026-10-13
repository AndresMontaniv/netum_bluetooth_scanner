// Calls run under fake_async and are driven by elapsing time, not awaited.
// ignore_for_file: discarded_futures

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';

import '../helpers/fake_transport.dart';

const _id = 'DD:0D:30:60:B4:2C';
final List<int> _barcode = '7771609001660\r'.codeUnits;

void main() {
  late FakeTransport transport;
  late NetumScanner netum;
  late NetumDevice device;
  late List<ConnectionEvent> events;

  /// Native's report of an unexpected drop while auto-reconnecting.
  void dropAndRetry({int? code = 8}) {
    transport
      ..link(_id, LinkStateMsg.disconnected, code: code)
      ..link(_id, LinkStateMsg.connecting);
  }

  void setUpConnected(FakeAsync async, {ReconnectPolicy? policy}) {
    transport = FakeTransport();
    netum = NetumScanner.withTransport(transport);
    events = [];
    netum.connectionEvents.listen(events.add);
    netum
        .connect(
          _id,
          transport: NetumTransport.ble,
          autoReconnect: true,
          reconnectPolicy: policy ?? const ReconnectPolicy(),
        )
        .then((d) => device = d);
    async.flushMicrotasks();
  }

  test('connect passes autoReconnect to native', () {
    fakeAsync((async) {
      setUpConnected(async);
      expect(transport.connectOptions.single.autoReconnect, isTrue);
      expect(device.autoReconnect, isTrue);
    });
  });

  test('a drop → reconnecting with the reason → connected, same handle', () {
    fakeAsync((async) {
      setUpConnected(async);
      final scans = <ScanEvent>[];
      device.scans.listen(scans.add);

      dropAndRetry();
      async.flushMicrotasks();
      expect(device.state, NetumConnectionState.reconnecting);
      expect(events.last.reason, isA<LinkLost>());

      transport.link(_id, LinkStateMsg.connected);
      async.flushMicrotasks();
      expect(device.state, NetumConnectionState.connected);

      transport.receive(_id, _barcode);
      async.flushMicrotasks();
      expect(scans.single.text, '7771609001660');
      expect(
        events.map((e) => e.state).toList().sublist(2),
        [NetumConnectionState.reconnecting, NetumConnectionState.connected],
      );
    });
  });

  test('commands throw NetumNotConnected while reconnecting', () {
    fakeAsync((async) {
      setUpConnected(async);
      dropAndRetry();
      async.flushMicrotasks();

      Object? error;
      device.beep().catchError((Object e) => error = e);
      async.flushMicrotasks();

      expect(error, isA<NetumNotConnected>());
    });
  });

  test('disconnect() while reconnecting ends UserRequested', () {
    fakeAsync((async) {
      setUpConnected(async);
      dropAndRetry();
      async.flushMicrotasks();

      device.disconnect();
      async.flushMicrotasks();

      expect(transport.disconnects, [_id]);
      expect(device.state, NetumConnectionState.disconnected);
      expect(events.last.reason, isA<UserRequested>());
    });
  });

  test('gives up after the policy and ends ReconnectGaveUp', () {
    fakeAsync((async) {
      setUpConnected(
        async,
        policy: const ReconnectPolicy(giveUpAfter: Duration(minutes: 5)),
      );
      dropAndRetry();
      async.elapse(const Duration(minutes: 4, seconds: 59));
      expect(device.state, NetumConnectionState.reconnecting);

      async.elapse(const Duration(seconds: 1));
      expect(transport.autoReconnectCalls.last, (_id, false));
      // Native confirms by reporting the end of the link.
      transport.link(_id, LinkStateMsg.disconnected, user: true);
      async.flushMicrotasks();

      expect(device.state, NetumConnectionState.disconnected);
      expect(events.last.reason, isA<ReconnectGaveUp>());
    });
  });

  test('the default policy gives up after 30 minutes', () {
    fakeAsync((async) {
      setUpConnected(async);
      dropAndRetry();
      async.elapse(const Duration(minutes: 29));
      expect(transport.autoReconnectCalls, isEmpty);

      async.elapse(const Duration(minutes: 1));
      expect(transport.autoReconnectCalls.last, (_id, false));
    });
  });

  test('ReconnectPolicy.unlimited never gives up', () {
    fakeAsync((async) {
      setUpConnected(async, policy: ReconnectPolicy.unlimited);
      dropAndRetry();
      async.elapse(const Duration(hours: 5));

      expect(device.state, NetumConnectionState.reconnecting);
      expect(transport.autoReconnectCalls, isEmpty);
    });
  });

  test('reconnecting in time cancels the give-up timer', () {
    fakeAsync((async) {
      setUpConnected(async);
      dropAndRetry();
      async.elapse(const Duration(minutes: 10));
      transport.link(_id, LinkStateMsg.connected);
      async.elapse(const Duration(hours: 1));

      expect(device.state, NetumConnectionState.connected);
      expect(transport.autoReconnectCalls, isEmpty);
    });
  });

  test('without autoReconnect a drop ends disconnected', () {
    fakeAsync((async) {
      transport = FakeTransport();
      netum = NetumScanner.withTransport(transport);
      netum.connect(_id, transport: NetumTransport.ble).then((d) => device = d);
      async.flushMicrotasks();

      transport.link(_id, LinkStateMsg.disconnected, code: 8);
      async.flushMicrotasks();

      expect(device.state, NetumConnectionState.disconnected);
    });
  });

  test('the autoReconnect setter updates native at runtime', () {
    fakeAsync((async) {
      setUpConnected(async);

      device.autoReconnect = false;
      async.flushMicrotasks();

      expect(transport.autoReconnectCalls.single, (_id, false));
      expect(device.autoReconnect, isFalse);
    });
  });

  test('switchMode turns auto-reconnect off before switching', () {
    fakeAsync((async) {
      setUpConnected(async);

      device.switchMode(NetumMode.hid);
      async.flushMicrotasks();

      expect(transport.autoReconnectCalls.single, (_id, false));
      expect(device.autoReconnect, isFalse);
      // The mode command goes out after.
      expect(transport.writes, hasLength(1));
    });
  });

  test('an expected disconnect with auto-reconnect reconnects', () {
    fakeAsync((async) {
      setUpConnected(async);

      device.setName('Netum-02');
      async.flushMicrotasks();
      dropAndRetry(code: 19);
      async.flushMicrotasks();
      expect(device.state, NetumConnectionState.reconnecting);
      expect(events.last.reason, isA<ExpectedAfterCommand>());

      transport.link(_id, LinkStateMsg.connected);
      async.flushMicrotasks();
      expect(device.state, NetumConnectionState.connected);
      expect(device.name, 'Netum-02');
    });
  });
}
