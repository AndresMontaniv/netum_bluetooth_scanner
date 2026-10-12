import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

class StatusPage extends StatelessWidget {
  const StatusPage({required this.state, super.key});

  final AppState state;

  NetumScanner get _netum => state.netum;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<AdapterState>(
          stream: _netum.adapterState,
          builder: (context, snapshot) => ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Adapter'),
            subtitle: Text(snapshot.data?.name ?? '…'),
          ),
        ),
        for (final scope in PermissionScope.values) ...[
          ListTile(
            leading: const Icon(Icons.verified_user),
            title: Text('Permissions: ${scope.name}'),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => state.run(
                  'check ${scope.name}',
                  () => _netum.checkPermissions(scope: scope),
                ),
                child: const Text('Check'),
              ),
              OutlinedButton(
                onPressed: () => state.run(
                  'request ${scope.name}',
                  () => _netum.requestPermissions(scope: scope),
                ),
                child: const Text('Request'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: () => state.run(
            'request enable Bluetooth',
            _netum.requestEnableBluetooth,
          ),
          child: const Text('Ask to turn Bluetooth on'),
        ),
        const SizedBox(height: 16),
        Text(
          'Max connections: ${_netum.maxConnections}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
