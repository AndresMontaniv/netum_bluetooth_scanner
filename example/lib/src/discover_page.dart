import 'dart:async';

import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({required this.state, super.key});

  final AppState state;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _found = <String, DiscoveredScanner>{};
  DiscoveryFilter _filter = DiscoveryFilter.likelyNetum;
  StreamSubscription<DiscoveredScanner>? _subscription;

  NetumScanner get _netum => widget.state.netum;

  void _start() {
    unawaited(_subscription?.cancel());
    setState(_found.clear);
    widget.state.log('discover ${_filter.name}');
    _subscription = _netum
        .discover(filter: _filter)
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
                  subtitle: Text('${scanner.id} · ${scanner.rssi} dBm'),
                  trailing: TextButton(
                    onPressed: () => widget.state.run(
                      'connect ${scanner.id}',
                      () => _netum.connect(
                        scanner.id,
                        transport: scanner.transport,
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
