import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'netum_bluetooth_scanner_method_channel.dart';

abstract class NetumBluetoothScannerPlatform extends PlatformInterface {
  /// Constructs a NetumBluetoothScannerPlatform.
  NetumBluetoothScannerPlatform() : super(token: _token);

  static final Object _token = Object();

  static NetumBluetoothScannerPlatform _instance = MethodChannelNetumBluetoothScanner();

  /// The default instance of [NetumBluetoothScannerPlatform] to use.
  ///
  /// Defaults to [MethodChannelNetumBluetoothScanner].
  static NetumBluetoothScannerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NetumBluetoothScannerPlatform] when
  /// they register themselves.
  static set instance(NetumBluetoothScannerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
