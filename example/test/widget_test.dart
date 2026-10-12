import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';
import 'package:netum_bluetooth_scanner_example/main.dart';

class _FakeTransport extends Fake implements NetumTransportApi {
  @override
  Future<List<ActiveLinkMsg>> initialize() async => [];

  @override
  Future<AdapterStateMsg> adapterState() async => AdapterStateMsg.poweredOn;

  @override
  Stream<AdapterStateMsg> get adapterStates =>
      Stream.value(AdapterStateMsg.poweredOff);
}

void main() {
  testWidgets('shows host call results and adapter events', (tester) async {
    await tester.pumpWidget(ExampleApp(transport: _FakeTransport()));
    await tester.pumpAndSettle();

    expect(find.textContaining('initialize(): 0 active links'), findsOneWidget);
    expect(find.textContaining('adapterState(): poweredOn'), findsOneWidget);
    expect(
      find.textContaining('adapterStates event: poweredOff'),
      findsOneWidget,
    );
  });
}
