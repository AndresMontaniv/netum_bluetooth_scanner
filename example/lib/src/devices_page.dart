import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final netum = state.netum;
    return StreamBuilder<List<NetumDevice>>(
      stream: netum.devices,
      initialData: netum.knownDevices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? const <NetumDevice>[];
        if (devices.isEmpty) {
          return const Center(child: Text('Connect a scanner from Discover.'));
        }
        return ListView(
          children: [
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
