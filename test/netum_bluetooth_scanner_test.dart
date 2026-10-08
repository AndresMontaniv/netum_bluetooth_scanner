import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner_platform_interface.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNetumBluetoothScannerPlatform
    with MockPlatformInterfaceMixin
    implements NetumBluetoothScannerPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NetumBluetoothScannerPlatform initialPlatform = NetumBluetoothScannerPlatform.instance;

  test('$MethodChannelNetumBluetoothScanner is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNetumBluetoothScanner>());
  });

  test('getPlatformVersion', () async {
    NetumBluetoothScanner netumBluetoothScannerPlugin = NetumBluetoothScanner();
    MockNetumBluetoothScannerPlatform fakePlatform = MockNetumBluetoothScannerPlatform();
    NetumBluetoothScannerPlatform.instance = fakePlatform;

    expect(await netumBluetoothScannerPlugin.getPlatformVersion(), '42');
  });
}
