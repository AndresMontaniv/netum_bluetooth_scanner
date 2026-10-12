import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

class ScansPage extends StatelessWidget {
  const ScansPage({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Column(
        children: [
          ListTile(
            title: Text('${state.scans.length} scans'),
            trailing: TextButton(
              onPressed: state.clearScans,
              child: const Text('Clear'),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final scan in state.scans)
                  ListTile(
                    dense: true,
                    title: Text(scan.text),
                    subtitle: Text(
                      '${scan.device.name ?? scan.deviceId} · '
                      '${scan.timestamp.toIso8601String().substring(11, 23)}\n'
                      '${AppState.hex(scan.raw)}',
                    ),
                    isThreeLine: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
