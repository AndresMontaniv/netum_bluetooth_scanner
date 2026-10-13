import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/transport/pigeon_transport.dart';

class _MockHostApi extends Mock implements NetumHostApi {}

void main() {
  final platformError = PlatformException(code: 'some-native-code');

  setUpAll(() {
    registerFallbackValue(PermissionScopeMsg.discovery);
    registerFallbackValue(
      DiscoveryOptionsMsg(
        transport: TransportMsg.ble,
        filterNetum: true,
        timeoutMs: 1,
      ),
    );
    registerFallbackValue(
      ConnectOptionsMsg(
        transport: TransportMsg.ble,
        timeoutMs: 1,
        autoReconnect: false,
        sppInsecureFallback: false,
      ),
    );
    registerFallbackValue(Uint8List(0));
  });

  test('no host call leaks a PlatformException', () async {
    final host = _MockHostApi();
    when(host.initialize).thenThrow(platformError);
    when(host.adapterState).thenThrow(platformError);
    when(() => host.checkPermissions(any())).thenThrow(platformError);
    when(() => host.requestPermissions(any())).thenThrow(platformError);
    when(host.requestEnableBluetooth).thenThrow(platformError);
    when(() => host.startDiscovery(any())).thenThrow(platformError);
    when(host.stopDiscovery).thenThrow(platformError);
    when(host.bondedDevices).thenThrow(platformError);
    when(() => host.connect(any(), any())).thenThrow(platformError);
    when(() => host.disconnect(any())).thenThrow(platformError);
    when(() => host.setAutoReconnect(any(), any())).thenThrow(platformError);
    when(() => host.write(any(), any())).thenThrow(platformError);
    when(
      () => host.readCharacteristic(any(), any(), any()),
    ).thenThrow(platformError);
    when(() => host.readRssi(any())).thenThrow(platformError);
    when(() => host.startSppListener(any())).thenThrow(platformError);
    when(host.stopSppListener).thenThrow(platformError);
    when(host.loadSavedScanners).thenThrow(platformError);
    when(() => host.saveSavedScanners(any())).thenThrow(platformError);

    final transport = PigeonTransport(
      hostApi: host,
      adapterStates: () => Stream.error(platformError),
      discoveries: () => Stream.error(platformError),
      linkStates: () => Stream.error(platformError),
      data: () => Stream.error(platformError),
    );
    final calls = <String, Future<Object?> Function()>{
      'initialize': transport.initialize,
      'adapterState': transport.adapterState,
      'checkPermissions': () =>
          transport.checkPermissions(PermissionScopeMsg.discovery),
      'requestPermissions': () =>
          transport.requestPermissions(PermissionScopeMsg.discovery),
      'requestEnableBluetooth': transport.requestEnableBluetooth,
      'startDiscovery': () => transport.startDiscovery(
        DiscoveryOptionsMsg(
          transport: TransportMsg.ble,
          filterNetum: true,
          timeoutMs: 1,
        ),
      ),
      'stopDiscovery': transport.stopDiscovery,
      'bondedDevices': transport.bondedDevices,
      'connect': () => transport.connect(
        'id',
        ConnectOptionsMsg(
          transport: TransportMsg.ble,
          timeoutMs: 1,
          autoReconnect: false,
          sppInsecureFallback: false,
        ),
      ),
      'disconnect': () => transport.disconnect('id'),
      'setAutoReconnect': () => transport.setAutoReconnect('id', enabled: true),
      'write': () => transport.write('id', Uint8List(1)),
      'readCharacteristic': () =>
          transport.readCharacteristic('id', '180A', '2A25'),
      'readRssi': () => transport.readRssi('id'),
      'startSppListener': () => transport.startSppListener(1),
      'stopSppListener': transport.stopSppListener,
      'loadSavedScanners': transport.loadSavedScanners,
      'saveSavedScanners': () => transport.saveSavedScanners('[]'),
    };
    for (final MapEntry(key: name, value: call) in calls.entries) {
      await expectLater(
        call(),
        throwsA(isA<NetumException>()),
        reason: name,
      );
    }

    for (final stream in <Stream<Object?>>[
      transport.adapterStates,
      transport.discoveries,
      transport.linkStates,
      transport.data,
    ]) {
      await expectLater(stream, emitsError(isA<NetumException>()));
    }
  });
}
