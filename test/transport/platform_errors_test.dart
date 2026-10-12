import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/transport/platform_errors.dart';

void main() {
  NetumException map(String code, {Object? details}) => mapPlatformException(
    PlatformException(code: code, message: 'msg', details: details),
  );

  test('maps every shared error code', () {
    expect(map('not-connected'), isA<NetumNotConnected>());
    expect(map('connection-failed'), isA<NetumConnectionFailed>());
    expect(map('bluetooth-unavailable'), isA<NetumBluetoothUnavailable>());
    expect(map('location-off'), isA<NetumLocationServicesOff>());
    expect(map('unsupported'), isA<NetumUnsupportedTransport>());
    expect(map('unimplemented'), isA<NetumUnsupportedTransport>());
    expect(map('busy'), isA<NetumDeviceBusy>());
    expect(map('max-connections'), isA<NetumMaxConnectionsReached>());
    expect(map('invalid-argument'), isA<NetumInvalidArgument>());
  });

  test('connection-failed keeps the platform status', () {
    final error = map('connection-failed', details: 133);
    expect((error as NetumConnectionFailed).platformCode, 133);
  });

  test('permission-denied lists the missing permissions', () {
    final error = map(
      'permission-denied',
      details: ['android.permission.BLUETOOTH_SCAN'],
    );
    expect(
      (error as NetumPermissionDenied).missing,
      ['android.permission.BLUETOOTH_SCAN'],
    );
  });

  test('other codes become NetumPlatformError', () {
    final error = map('discovery-failed', details: 2);
    expect(error, isA<NetumPlatformError>());
    expect((error as NetumPlatformError).code, 'discovery-failed');
    expect(error.details, 2);
  });
}
