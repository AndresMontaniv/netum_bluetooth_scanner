import 'package:flutter/services.dart';
import 'package:netum_bluetooth_scanner/src/errors.dart';
import 'package:netum_bluetooth_scanner/src/models/adapter_state.dart';

/// Maps a native error (codes shared by Android and iOS, DEF-10 B4) to its
/// [NetumException].
NetumException mapPlatformException(PlatformException error) {
  final message = error.message ?? error.code;
  final details = error.details;
  return switch (error.code) {
    'not-connected' => NetumNotConnected(message),
    'connection-failed' => NetumConnectionFailed(
      message,
      platformCode: details is int ? details : null,
    ),
    'permission-denied' => NetumPermissionDenied([
      if (details is List)
        for (final permission in details) '$permission',
    ]),
    'bluetooth-unavailable' => NetumBluetoothUnavailable(AdapterState.unknown),
    'location-off' => const NetumLocationServicesOff(),
    'unsupported' || 'unimplemented' => NetumUnsupportedTransport(message),
    'busy' => const NetumDeviceBusy(),
    'max-connections' => const NetumMaxConnectionsReached(),
    'invalid-argument' => NetumInvalidArgument(message),
    _ => NetumPlatformError(error.code, message, details: details),
  };
}

/// Runs [call], turning native errors into [NetumException]s.
Future<T> guardPlatform<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (error) {
    throw mapPlatformException(error);
  }
}
