import 'dart:async';

import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({required this.state, super.key});

  final AppState state;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<SavedScanner> _saved = const [];

  AppState get _state => widget.state;
  NetumScanner get _netum => _state.netum;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadSaved());
  }

  Future<void> _reloadSaved() async {
    final saved = await _netum.savedScanners();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _restore(RestoreStrategy strategy) async {
    await _state.run(
      'restore ${strategy.name}',
      () async => (await _netum.restoreSaved(
        strategy: strategy,
      )).map((d) => d.name ?? d.id).toList(),
    );
    await _reloadSaved();
  }

  Future<void> _rename(NetumDevice device) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: device.name),
    );
    if (name == null || name.isEmpty) return;
    await _state.run(
      '${device.id} setName "$name"',
      () => device.setName(name),
    );
    await _reloadSaved();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NetumDevice>>(
      stream: _netum.devices,
      initialData: _netum.knownDevices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? const <NetumDevice>[];
        return ListView(
          children: [
            ListTile(
              title: Text(
                '${_netum.connectedDevices.length} connected · '
                '${devices.length} known',
              ),
            ),
            for (final device in devices) _deviceTile(device),
            const Divider(),
            ListTile(
              title: Text('Saved scanners (${_saved.length})'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _reloadSaved,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _restore(RestoreStrategy.firstAvailable),
                    child: const Text('Restore first available'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _restore(RestoreStrategy.all),
                    child: const Text('Restore all'),
                  ),
                ],
              ),
            ),
            for (final saved in _saved)
              ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(saved.name ?? saved.id),
                subtitle: Text(
                  '${saved.id}\nlast ${saved.lastConnected.toLocal()} · '
                  'auto-reconnect ${saved.autoReconnect ? 'on' : 'off'}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _state.run(
                      'forget ${saved.id}',
                      () => _netum.forgetScanner(saved.id),
                    );
                    await _reloadSaved();
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _deviceTile(NetumDevice device) {
    final connected = device.isConnected;
    final active =
        connected || device.state == NetumConnectionState.reconnecting;
    return ExpansionTile(
      leading: Icon(
        connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
      ),
      title: Text(device.name ?? device.id),
      subtitle: Text(
        [
          device.id,
          device.state.name,
          if (_state.lastReason[device.id] case final reason?) 'last: $reason',
        ].join(' · '),
      ),
      children: [
        SwitchListTile(
          title: const Text('Auto-reconnect'),
          value: device.autoReconnect,
          onChanged: (value) {
            setState(() => device.autoReconnect = value);
            _state.log('${device.id} autoReconnect = $value');
          },
        ),
        Wrap(
          spacing: 8,
          children: [
            if (active)
              TextButton(
                onPressed: () =>
                    _state.run('disconnect ${device.id}', device.disconnect),
                child: const Text('Disconnect'),
              )
            else
              TextButton(
                onPressed: () => _state.run(
                  'connect ${device.id}',
                  () => device.connect(autoReconnect: _state.autoReconnect),
                ),
                child: const Text('Connect'),
              ),
            if (connected) ...[
              TextButton(
                onPressed: () => _rename(device),
                child: const Text('Rename'),
              ),
              TextButton(
                onPressed: () => _state.run(
                  '${device.id} getDeviceInfo',
                  device.getDeviceInfo,
                ),
                child: const Text('Device info'),
              ),
              TextButton(
                onPressed: () => _state.run(
                  '${device.id} getBluetoothInfo',
                  device.getBluetoothInfo,
                ),
                child: const Text('Bluetooth info'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Owns its text controller, so it is disposed only after the dialog's exit
/// animation (disposing it right after `showDialog` returns crashes).
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({this.initialName});

  final String? initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename scanner'),
      content: TextField(controller: _controller, maxLength: 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
