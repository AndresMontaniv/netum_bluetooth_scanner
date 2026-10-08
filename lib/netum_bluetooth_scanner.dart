
import 'netum_bluetooth_scanner_platform_interface.dart';

class NetumBluetoothScanner {
  Future<String?> getPlatformVersion() {
    return NetumBluetoothScannerPlatform.instance.getPlatformVersion();
  }
}
