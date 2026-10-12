import 'package:netum_bluetooth_scanner/src/commands/netum_command.dart';
import 'package:netum_bluetooth_scanner/src/models/adapter_state.dart';

/// Base class of every error thrown by the plugin's public API.
sealed class NetumException implements Exception {
  const NetumException(this.message);

  /// A human-readable description.
  final String message;

  @override
  String toString() => 'NetumException: $message';
}

/// Bluetooth is off, unsupported or not authorized.
final class NetumBluetoothUnavailable extends NetumException {
  /// Creates the error for adapter [state].
  NetumBluetoothUnavailable(this.state)
    : super('Bluetooth is not available (${state.name})');

  /// The adapter state at the time of the call.
  final AdapterState state;
}

/// Required runtime permissions are missing.
final class NetumPermissionDenied extends NetumException {
  /// Creates the error listing the [missing] permissions.
  NetumPermissionDenied(this.missing)
    : super('Missing permissions: ${missing.join(', ')}');

  /// Platform names of the missing permissions.
  final List<String> missing;
}

/// Location services are off, which blocks discovery on Android.
final class NetumLocationServicesOff extends NetumException {
  /// Creates the error.
  const NetumLocationServicesOff() : super('Location services are off');
}

/// The transport is not supported on this platform (SPP on iOS).
final class NetumUnsupportedTransport extends NetumException {
  /// Creates the error.
  const NetumUnsupportedTransport([
    super.message = 'Transport not supported on this platform',
  ]);
}

/// The device is not connected.
final class NetumNotConnected extends NetumException {
  /// Creates the error.
  const NetumNotConnected([super.message = 'The device is not connected']);
}

/// Connecting failed.
final class NetumConnectionFailed extends NetumException {
  /// Creates the error with the platform's [platformCode], if any.
  const NetumConnectionFailed(super.message, {this.platformCode});

  /// The platform status code, such as Android's GATT status 133.
  final int? platformCode;
}

/// The maximum number of simultaneous connections is reached.
final class NetumMaxConnectionsReached extends NetumException {
  /// Creates the error.
  const NetumMaxConnectionsReached()
    : super('Maximum number of connections reached');
}

/// The scanner did not answer a command in time.
final class NetumCommandTimeout extends NetumException {
  /// Creates the error for [command].
  NetumCommandTimeout(this.command) : super('No response to ${command.ascii}');

  /// The command that timed out.
  final NetumCommand command;
}

/// The device is already connecting.
final class NetumDeviceBusy extends NetumException {
  /// Creates the error.
  const NetumDeviceBusy() : super('The device is already connecting');
}

/// An argument is out of range or malformed.
final class NetumInvalidArgument extends NetumException {
  /// Creates the error.
  const NetumInvalidArgument(super.message);
}

/// The scanner answered with a reply the plugin could not parse.
final class NetumUnexpectedReply extends NetumException {
  /// Creates the error for [reply].
  NetumUnexpectedReply(this.reply) : super('Unexpected reply: "$reply"');

  /// The reply text as received.
  final String reply;
}

/// A platform failure without a more specific type, such as a failed BLE
/// scan.
final class NetumPlatformError extends NetumException {
  /// Creates the error with the platform's [code] and [details].
  const NetumPlatformError(this.code, super.message, {this.details});

  /// The error code, e.g. `discovery-failed`.
  final String code;

  /// Platform details, such as Android's scan failure code.
  final Object? details;
}
