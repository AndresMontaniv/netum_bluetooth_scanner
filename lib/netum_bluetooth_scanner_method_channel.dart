import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'netum_bluetooth_scanner_platform_interface.dart';

/// An implementation of [NetumBluetoothScannerPlatform] that uses method channels.
class MethodChannelNetumBluetoothScanner extends NetumBluetoothScannerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('netum_bluetooth_scanner');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
