import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';
import 'package:netum_bluetooth_scanner_example/src/console_page.dart';
import 'package:netum_bluetooth_scanner_example/src/scanners_page.dart';
import 'package:netum_bluetooth_scanner_example/src/scans_page.dart';
import 'package:netum_bluetooth_scanner_example/src/status_page.dart';

void main() {
  runApp(ExampleApp(netum: NetumScanner.instance));
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({required this.netum, super.key});

  final NetumScanner netum;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final AppState _state = AppState(widget.netum);

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, IconData, Widget)>[
      ('Status', Icons.info_outline, StatusPage(state: _state)),
      ('Scanners', Icons.bluetooth_searching, ScannersPage(state: _state)),
      ('Scans', Icons.qr_code, ScansPage(state: _state)),
      ('Console', Icons.terminal, ConsolePage(state: _state)),
    ];
    return MaterialApp(
      title: 'NETUM scanner example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('NETUM scanner example'),
            actions: [
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'About',
                  icon: const Icon(Icons.help_outline),
                  onPressed: () => _showAbout(context),
                ),
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabs: [
                for (final (label, icon, _) in tabs)
                  Tab(text: label, icon: Icon(icon)),
              ],
            ),
          ),
          // Android 15+ draws edge to edge: keep the content clear of the
          // navigation bar.
          body: SafeArea(
            top: false,
            child: TabBarView(
              children: [for (final (_, _, page) in tabs) page],
            ),
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) => showAboutDialog(
    context: context,
    applicationName: 'NETUM scanner example',
    applicationLegalese:
        'MIT license. Not affiliated with or endorsed by NETUM.',
    children: const [
      SizedBox(height: 16),
      Text(
        'Demonstrates the netum_bluetooth_scanner plugin.\n\n'
        'Status: Bluetooth, permissions and Location.\n'
        'Scanners: your scanners (connected, saved, paired) and the ones '
        'nearby; connect, rename, auto-reconnect, pair by scanning.\n'
        'Scans: every barcode, from every scanner.\n'
        'Console: settings, queries and the traffic log.',
      ),
    ],
  );
}
