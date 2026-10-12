import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({required this.state, super.key});

  final AppState state;

  /// A scanner id passed with `--dart-define=NETUM_SAVED_ID=<id>`, to test
  /// connecting a saved device without discovery (saved devices: S4).
  static const _savedId = String.fromEnvironment('NETUM_SAVED_ID');

  @override
  Widget build(BuildContext context) {
    final netum = state.netum;
    return StreamBuilder<List<NetumDevice>>(
      stream: netum.devices,
      initialData: netum.knownDevices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? const <NetumDevice>[];
        final saved = _savedId.isEmpty
            ? null
            : ListTile(
                leading: const Icon(Icons.bookmark),
                title: const Text('Saved scanner (no discovery)'),
                subtitle: const Text(_savedId),
                trailing: TextButton(
                  onPressed: () => state.run(
                    'connect saved $_savedId',
                    () =>
                        netum.connect(_savedId, transport: NetumTransport.ble),
                  ),
                  child: const Text('Connect'),
                ),
              );
        if (devices.isEmpty) {
          return ListView(
            children: [
              ?saved,
              const ListTile(title: Text('Connect a scanner from Discover.')),
            ],
          );
        }
        return ListView(
          children: [
            ?saved,
            ListTile(
              title: Text(
                '${netum.connectedDevices.length} connected · '
                '${devices.length} known',
              ),
            ),
            for (final device in devices)
              ListTile(
                leading: Icon(
                  device.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                ),
                title: Text(device.name ?? device.id),
                subtitle: Text(
                  [
                    device.id,
                    device.state.name,
                    if (state.lastReason[device.id] case final reason?)
                      'last: $reason',
                  ].join(' · '),
                ),
                trailing: device.isConnected
                    ? TextButton(
                        onPressed: () => state.run(
                          'disconnect ${device.id}',
                          device.disconnect,
                        ),
                        child: const Text('Disconnect'),
                      )
                    : TextButton(
                        onPressed: () => state.run(
                          'connect ${device.id}',
                          device.connect,
                        ),
                        child: const Text('Connect'),
                      ),
              ),
          ],
        );
      },
    );
  }
}
