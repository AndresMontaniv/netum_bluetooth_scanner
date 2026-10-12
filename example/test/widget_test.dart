import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner_example/main.dart';

void main() {
  testWidgets('renders the example app', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('NETUM scanner example'), findsOneWidget);
  });
}
