import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';
import 'package:netum_bluetooth_scanner_example/main.dart';

class _FakeTransport extends Fake implements NetumTransportApi {
  @override
  Stream<AdapterStateMsg> get adapterStates => const Stream.empty();

  @override
  Stream<LinkStateMsgEvent> get linkStates => const Stream.empty();

  @override
  Stream<DataMsg> get data => const Stream.empty();

  @override
  Future<AdapterStateMsg> adapterState() async => AdapterStateMsg.poweredOn;

  @override
  Future<List<ActiveLinkMsg>> initialize() async => [];
}

void main() {
  testWidgets('shows the five tabs and the adapter state', (tester) async {
    await tester.pumpWidget(
      ExampleApp(netum: NetumScanner.withTransport(_FakeTransport())),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Status', 'Discover', 'Devices', 'Scans', 'Console']) {
      expect(find.text(tab), findsOneWidget);
    }
    expect(find.text('poweredOn'), findsOneWidget);
  });
}
