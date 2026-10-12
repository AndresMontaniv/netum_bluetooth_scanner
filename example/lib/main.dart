import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';
import 'package:netum_bluetooth_scanner_example/src/console_page.dart';
import 'package:netum_bluetooth_scanner_example/src/devices_page.dart';
import 'package:netum_bluetooth_scanner_example/src/discover_page.dart';
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
      ('Discover', Icons.search, DiscoverPage(state: _state)),
      ('Devices', Icons.devices, DevicesPage(state: _state)),
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
            bottom: TabBar(
              isScrollable: true,
              tabs: [
                for (final (label, icon, _) in tabs)
                  Tab(text: label, icon: Icon(icon)),
              ],
            ),
          ),
          body: TabBarView(children: [for (final (_, _, page) in tabs) page]),
        ),
      ),
    );
  }
}
