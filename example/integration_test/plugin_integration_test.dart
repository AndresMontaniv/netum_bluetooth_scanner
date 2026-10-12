import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/transport/pigeon_transport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host calls reach the platform', (tester) async {
    final transport = PigeonTransport();

    expect(await transport.initialize(), isEmpty);
    expect(await transport.adapterState(), isA<AdapterStateMsg>());
  });
}
