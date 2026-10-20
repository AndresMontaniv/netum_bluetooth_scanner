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

  @override
  Future<String?> loadSavedScanners() async => null;

  @override
  Future<List<DiscoveredDeviceMsg>> bondedDevices() async => [];
}

void main() {
  testWidgets('shows the four tabs and the adapter state', (tester) async {
    await tester.pumpWidget(
      ExampleApp(netum: NetumScanner.withTransport(_FakeTransport())),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Status', 'Scanners', 'Scans', 'Console']) {
      expect(find.text(tab), findsOneWidget);
    }
    expect(find.text('poweredOn'), findsOneWidget);
  });

  testWidgets('the Scanners tab shows both sections', (tester) async {
    await tester.pumpWidget(
      ExampleApp(netum: NetumScanner.withTransport(_FakeTransport())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scanners'));
    await tester.pumpAndSettle();

    expect(find.text('My scanners (0)'), findsOneWidget);
    expect(find.text('Available (0)'), findsOneWidget);
    expect(find.text('Tap Scan to look for scanners.'), findsOneWidget);
  });
}
