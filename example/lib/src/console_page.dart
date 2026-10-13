import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

class ConsolePage extends StatefulWidget {
  const ConsolePage({required this.state, super.key});

  final AppState state;

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final _raw = TextEditingController(text: '%BAT_VOL#');
  String? _deviceId;
  double _beep = 10;

  AppState get _state => widget.state;

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final connected = _state.netum.connectedDevices;
        final device = connected
            .where((d) => d.id == _deviceId)
            .followedBy(connected)
            .firstOrNull;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: device == null
                  ? const Text('No connected scanner.')
                  : DropdownButton<String>(
                      value: device.id,
                      isExpanded: true,
                      items: [
                        for (final d in connected)
                          DropdownMenuItem(
                            value: d.id,
                            child: Text('${d.name ?? ''} ${d.id}'),
                          ),
                      ],
                      onChanged: (id) => setState(() => _deviceId = id),
                    ),
            ),
            if (device != null) ..._controls(device),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final line in _state.lines)
                    Text(line, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// A menu button that applies one value of an enum setting.
  Widget _setting<T extends Enum>(
    String label,
    List<T> values,
    Future<void> Function(T value) apply,
  ) {
    return PopupMenuButton<T>(
      onSelected: (value) =>
          _state.run('$label ${value.name}', () => apply(value)),
      itemBuilder: (context) => [
        for (final value in values)
          PopupMenuItem(value: value, child: Text(value.name)),
      ],
      child: Chip(label: Text(label)),
    );
  }

  List<Widget> _controls(NetumDevice device) {
    final name = device.name ?? device.id;
    return [
      Wrap(
        spacing: 6,
        children: [
          _setting('Volume', BeepVolume.values, device.setVolume),
          _setting('Tone', BeepTone.values, device.setTone),
          _setting('Scan mode', ScanMode.values, device.setScanMode),
          _setting('Sleep', SleepTimeout.values, device.setSleepTimeout),
          _setting('Terminator', Terminator.values, device.setTerminator),
          _setting('Work mode', WorkMode.values, device.setWorkMode),
          _setting('Switch mode', NetumMode.values, device.switchMode),
          for (final enabled in [true, false]) ...[
            ActionChip(
              label: Text('Vibration ${enabled ? 'on' : 'off'}'),
              onPressed: () => _state.run(
                '$name setVibration($enabled)',
                () => device.setVibration(enabled: enabled),
              ),
            ),
            ActionChip(
              label: Text('ACK beep ${enabled ? 'on' : 'off'}'),
              onPressed: () => _state.run(
                '$name setCommandConfirmationBeep($enabled)',
                () => device.setCommandConfirmationBeep(enabled: enabled),
              ),
            ),
          ],
        ],
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final (label, query) in <(String, Future<Object?> Function())>[
            ('Sleep?', device.getSleepTimeout),
            ('Engine?', device.getEngineModel),
            ('Stored?', device.getStoredCount),
            ('Upload', device.uploadStored),
            ('Upload+clear', () => device.uploadStored(clearAfter: true)),
            ('Clear stored', device.clearStored),
          ])
            ActionChip(
              label: Text(label),
              onPressed: () => _state.run('$name $label', query),
            ),
          FilterChip(
            label: const Text('Traffic log'),
            selected: _state.trafficLogEnabled,
            onSelected: (value) =>
                setState(() => _state.trafficLogEnabled = value),
          ),
        ],
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final seconds in [1, 3])
            OutlinedButton(
              onPressed: () => _state.run(
                '$name triggerScan($seconds)',
                () => device.triggerScan(seconds: seconds),
              ),
              child: Text('Scan ${seconds}s'),
            ),
          OutlinedButton(
            onPressed: () => _state.run('$name getBattery', device.getBattery),
            child: const Text('Battery'),
          ),
          OutlinedButton(
            onPressed: () => _state.run(
              '$name getFirmwareVersion',
              device.getFirmwareVersion,
            ),
            child: const Text('Firmware'),
          ),
          OutlinedButton(
            onPressed: () => _state.run('$name readRssi', device.readRssi),
            child: const Text('RSSI'),
          ),
          OutlinedButton(
            onPressed: () =>
                _state.run('$name getDeviceInfo', device.getDeviceInfo),
            child: const Text('Info'),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: Slider(
              value: _beep,
              max: 26,
              divisions: 26,
              label: '${_beep.round()}',
              onChanged: (v) => setState(() => _beep = v),
            ),
          ),
          OutlinedButton(
            onPressed: () => _state.run(
              '$name beep(${_beep.round()})',
              () => device.beep(_beep.round()),
            ),
            child: Text('Beep ${_beep.round()}'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(child: TextField(controller: _raw)),
            TextButton(
              onPressed: () => _state.run(
                '$name sendRaw "${_raw.text}" framed',
                () => device.sendRaw(_raw.text),
              ),
              child: const Text('Framed'),
            ),
            TextButton(
              onPressed: () => _state.run(
                '$name sendRaw "${_raw.text}" raw',
                () => device.sendRaw(_raw.text, framed: false),
              ),
              child: const Text('Raw'),
            ),
          ],
        ),
      ),
    ];
  }
}
