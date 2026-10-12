import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netum_bluetooth_scanner_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('example app starts', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('NETUM scanner example'), findsOneWidget);
  });
}
