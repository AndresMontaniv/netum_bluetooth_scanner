import 'dart:async';

import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';
import 'package:netum_bluetooth_scanner_example/src/pair_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({required this.state, super.key});

  final AppState state;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _found = <String, DiscoveredScanner>{};
  DiscoveryFilter _filter = DiscoveryFilter.likelyNetum;
  NetumTransport _transport = NetumTransport.ble;
  StreamSubscription<DiscoveredScanner>? _subscription;

  NetumScanner get _netum => widget.state.netum;

  void _start() {
    unawaited(_subscription?.cancel());
    setState(_found.clear);
    widget.state.log('discover ${_transport.name} ${_filter.name}');
    _subscription = _netum
        .discover(transport: _transport, filter: _filter)
        .listen(
          (scanner) {
            if (!_found.containsKey(scanner.id)) {
              widget.state.log(
                'found ${scanner.id} "${scanner.name}" rssi=${scanner.rssi} '
                'likelyNetum=${scanner.likelyNetum}',
              );
            }
            setState(() => _found[scanner.id] = scanner);
          },
          onError: (Object error) => widget.state.log('discover ✗ $error'),
          onDone: () {
            widget.state.log('discover done (${_found.length} found)');
            if (mounted) setState(() => _subscription = null);
          },
        );
    setState(() {});
  }

  Future<void> _showBonded() async {
    try {
      final bonded = await _netum.bondedScanners();
      widget.state.log(
        'bondedScanners → ${bonded.map((s) => '${s.name} ${s.id}').toList()}',
      );
      setState(() {
        for (final scanner in bonded) {
          _found[scanner.id] = scanner;
        }
      });
    } on NetumException catch (error) {
      widget.state.log('bondedScanners ✗ $error');
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _found.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SegmentedButton<DiscoveryFilter>(
                segments: const [
                  ButtonSegment(
                    value: DiscoveryFilter.likelyNetum,
                    label: Text('NETUM'),
                  ),
                  ButtonSegment(value: DiscoveryFilter.all, label: Text('All')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              const Spacer(),
              if (_subscription == null)
                FilledButton(onPressed: _start, child: const Text('Scan'))
              else
                OutlinedButton(
                  onPressed: _netum.stopDiscovery,
                  child: const Text('Stop'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<NetumTransport>(
                segments: [
                  const ButtonSegment(
                    value: NetumTransport.ble,
                    label: Text('BLE'),
                  ),
                  ButtonSegment(
                    value: NetumTransport.spp,
                    label: const Text('SPP'),
                    enabled: _netum.isSupported(NetumTransport.spp),
                  ),
                ],
                selected: {_transport},
                onSelectionChanged: (s) => setState(() => _transport = s.first),
              ),
              if (_netum.isSupported(NetumTransport.spp)) ...[
                IconButton(
                  tooltip: 'Bonded scanners',
                  icon: const Icon(Icons.link),
                  onPressed: _showBonded,
                ),
                IconButton(
                  tooltip: 'Pair by scanning',
                  icon: const Icon(Icons.qr_code_2),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PairPage(state: widget.state),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) => SwitchListTile(
            dense: true,
            title: const Text('Auto-reconnect new connections'),
            value: widget.state.autoReconnect,
            onChanged: (v) => widget.state.setAutoReconnect(value: v),
          ),
        ),
        if (_subscription != null) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            children: [
              for (final scanner in results)
                ListTile(
                  leading: Icon(
                    scanner.likelyNetum
                        ? Icons.qr_code_scanner
                        : Icons.devices_other,
                  ),
                  title: Text(scanner.name ?? '(no name)'),
                  subtitle: Text(
                    [
                      scanner.id,
                      scanner.transport.name.toUpperCase(),
                      if (scanner.rssi != null) '${scanner.rssi} dBm',
                      if (scanner.bonded) 'bonded',
                    ].join(' · '),
                  ),
                  trailing: TextButton(
                    onPressed: () => widget.state.run(
                      'connect ${scanner.name ?? scanner.id}',
                      () => _netum.connect(
                        scanner.id,
                        transport: scanner.transport,
                        name: scanner.name,
                        autoReconnect: widget.state.autoReconnect,
                      ),
                    ),
                    child: const Text('Connect'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
