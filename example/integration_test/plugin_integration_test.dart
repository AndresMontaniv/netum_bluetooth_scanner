import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initialize and adapter state reach the platform', (
    tester,
  ) async {
    final netum = NetumScanner.instance;

    await netum.initialize();

    expect(netum.currentAdapterState, isNot(AdapterState.unknown));
  });
}
