import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/transport/pigeon_transport.dart';

class _MockHostApi extends Mock implements NetumHostApi {}

/// A fake native event stream that counts subscriptions.
class _FakeNativeStream<T> {
  late final _controller = StreamController<T>.broadcast(
    onCancel: () => cancelled = true,
  );
  int opens = 0;
  bool cancelled = false;

  Stream<T> open() {
    opens++;
    cancelled = false;
    return _controller.stream;
  }

  void add(T value) => _controller.add(value);
}

void main() {
  late _MockHostApi host;
  late _FakeNativeStream<AdapterStateMsg> nativeAdapterStates;
  late PigeonTransport transport;

  setUp(() {
    host = _MockHostApi();
    nativeAdapterStates = _FakeNativeStream();
    transport = PigeonTransport(
      hostApi: host,
      adapterStates: nativeAdapterStates.open,
      discoveries: () => const Stream.empty(),
      linkStates: () => const Stream.empty(),
      data: () => const Stream.empty(),
    );
  });

  group('host calls', () {
    test('delegate to the Pigeon host API', () async {
      when(() => host.initialize()).thenAnswer((_) async => []);
      when(
        () => host.adapterState(),
      ).thenAnswer((_) async => AdapterStateMsg.poweredOn);

      expect(await transport.initialize(), isEmpty);
      expect(await transport.adapterState(), AdapterStateMsg.poweredOn);
    });

    test('setAutoReconnect passes the flag through', () async {
      when(
        () => host.setAutoReconnect(any(), any()),
      ).thenAnswer((_) async {});

      await transport.setAutoReconnect('AA', enabled: true);

      verify(() => host.setAutoReconnect('AA', true)).called(1);
    });
  });

  group('event streams', () {
    test('share one native subscription between listeners', () async {
      final a = <AdapterStateMsg>[];
      final b = <AdapterStateMsg>[];
      final subA = transport.adapterStates.listen(a.add);
      final subB = transport.adapterStates.listen(b.add);

      nativeAdapterStates.add(AdapterStateMsg.poweredOff);
      await pumpEventQueue();

      expect(nativeAdapterStates.opens, 1);
      expect(a, [AdapterStateMsg.poweredOff]);
      expect(b, [AdapterStateMsg.poweredOff]);

      await subA.cancel();
      await subB.cancel();
    });

    test('cancel the native subscription after the last listener', () async {
      final subA = transport.adapterStates.listen((_) {});
      final subB = transport.adapterStates.listen((_) {});

      await subA.cancel();
      expect(nativeAdapterStates.cancelled, isFalse);

      await subB.cancel();
      expect(nativeAdapterStates.cancelled, isTrue);
    });

    test('resubscribe natively when listened to again', () async {
      await transport.adapterStates.listen((_) {}).cancel();
      final sub = transport.adapterStates.listen((_) {});

      expect(nativeAdapterStates.opens, 2);

      await sub.cancel();
    });
  });
}
