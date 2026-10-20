import 'dart:async';

import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';
import 'package:netum_bluetooth_scanner_example/src/pair_page.dart';

/// Discovery and connections in one place, like the OS Bluetooth settings:
/// "My scanners" (connected, saved and, on Android, paired over SPP) above
/// "Available" (what the current scan finds). A scanner that connects moves
/// up into "My scanners".
class ScannersPage extends StatefulWidget {
  const ScannersPage({required this.state, super.key});

  final AppState state;

  @override
  State<ScannersPage> createState() => _ScannersPageState();
}

class _ScannersPageState extends State<ScannersPage> {
  final _found = <String, DiscoveredScanner>{};
  List<SavedScanner> _saved = const [];
  List<DiscoveredScanner> _paired = const [];
  DiscoveryFilter _filter = DiscoveryFilter.likelyNetum;
  NetumTransport _transport = NetumTransport.ble;
  StreamSubscription<DiscoveredScanner>? _discovery;
  StreamSubscription<ConnectionEvent>? _connections;
  late final AppLifecycleListener _lifecycle;

  AppState get _state => widget.state;
  NetumScanner get _netum => _state.netum;
  bool get _sppSupported => _netum.isSupported(NetumTransport.spp);

  @override
  void initState() {
    super.initState();
    // A new connection may add a saved entry or a pairing.
    _connections = _netum.connectionEvents.listen((event) {
      if (event.state == NetumConnectionState.connected) unawaited(_reload());
    });
    // Pairings change outside the app (Settings → Bluetooth).
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_reload()));
    unawaited(_reload());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_discovery?.cancel());
    unawaited(_connections?.cancel());
    super.dispose();
  }

  Future<void> _reload() async {
    final saved = await _netum.savedScanners();
    var paired = const <DiscoveredScanner>[];
    if (_sppSupported) {
      try {
        paired = await _netum.bondedScanners(filter: _filter);
      } on NetumException {
        // No connection permission yet: nothing paired to show.
      }
    }
    if (mounted) {
      setState(() {
        _saved = saved;
        _paired = paired;
      });
    }
  }

  void _scan() {
    unawaited(_reload());
    unawaited(_discovery?.cancel());
    setState(_found.clear);
    _state.log('discover ${_transport.name} ${_filter.name}');
    _discovery = _netum
        .discover(transport: _transport, filter: _filter)
        .listen(
          (scanner) {
            if (!_found.containsKey(scanner.id)) {
              _state.log(
                'found ${scanner.id} "${scanner.name}" rssi=${scanner.rssi} '
                'likelyNetum=${scanner.likelyNetum}',
              );
            }
            setState(() => _found[scanner.id] = scanner);
          },
          onError: (Object error) => _state.log('discover ✗ $error'),
          onDone: () {
            _state.log('discover done (${_found.length} found)');
            if (mounted) setState(() => _discovery = null);
          },
        );
    setState(() {});
  }

  Future<void> _restore(RestoreStrategy strategy) async {
    await _state.run(
      'restore ${strategy.name}',
      () async => (await _netum.restoreSaved(
        strategy: strategy,
      )).map((d) => d.name ?? d.id).toList(),
    );
    await _reload();
  }

  Future<void> _connect(_Entry entry) => _state.run(
    'connect ${entry.name ?? entry.id}',
    () => _netum.connect(
      entry.id,
      transport: entry.transport,
      name: entry.name,
      autoReconnect: entry.saved?.autoReconnect ?? _state.autoReconnect,
      reconnectPolicy: entry.saved?.reconnectPolicy ?? const ReconnectPolicy(),
    ),
  );

  Future<void> _forget(_Entry entry) async {
    await _state.run(
      'forget ${entry.id}',
      () => _netum.forgetScanner(entry.id),
    );
    await _reload();
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
    await _reload();
  }

  /// Connected or busy handles, saved scanners and SPP pairings, one entry
  /// per id.
  List<_Entry> _myScanners() {
    final entries = <String, _Entry>{};
    // A first connect stays under "Available" (with a spinner) until it
    // succeeds; saved and paired scanners are added below either way.
    for (final device in _netum.knownDevices) {
      if (device.state != NetumConnectionState.disconnected &&
          device.state != NetumConnectionState.connecting) {
        entries[device.id] = _Entry.of(device);
      }
    }
    final pairedIds = {for (final paired in _paired) paired.id};
    for (final saved in _saved) {
      // For SPP the OS pairing list is the truth: a saved scanner whose
      // pairing was removed needs the pairing prompt again, so it belongs
      // under "Available" until it is paired.
      if (saved.transport == NetumTransport.spp &&
          !pairedIds.contains(saved.id) &&
          !entries.containsKey(saved.id)) {
        continue;
      }
      entries.update(
        saved.id,
        (entry) => entry.copyWith(saved: saved),
        ifAbsent: () => _Entry(
          id: saved.id,
          transport: saved.transport,
          name: saved.name,
          saved: saved,
        ),
      );
    }
    for (final paired in _paired) {
      entries.update(
        paired.id,
        (entry) => entry.copyWith(paired: true),
        ifAbsent: () => _Entry(
          id: paired.id,
          transport: NetumTransport.spp,
          name: paired.name,
          paired: true,
        ),
      );
    }
    // Attach the live handle (state, last reason) wherever one exists.
    return [
      for (final entry in entries.values)
        entry.copyWith(device: _handle(entry.id) ?? entry.device),
    ]..sort(_byState);
  }

  NetumDevice? _handle(String id) {
    for (final device in _netum.knownDevices) {
      if (device.id == id) return device;
    }
    return null;
  }

  static int _byState(_Entry a, _Entry b) {
    int rank(_Entry e) => e.state == NetumConnectionState.disconnected ? 1 : 0;
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : (a.name ?? a.id).compareTo(b.name ?? b.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final mine = _myScanners();
        final mineIds = {for (final entry in mine) entry.id};
        final available =
            _found.values.where((s) => !mineIds.contains(s.id)).toList()
              ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
        final foundMine = _found.keys.where(mineIds.contains).length;
        return ListView(
          children: [
            _header(),
            if (_discovery != null)
              const LinearProgressIndicator()
            else
              const SizedBox(height: 4),
            _sectionTitle(
              'My scanners (${mine.length})',
              trailing: PopupMenuButton<RestoreStrategy>(
                tooltip: 'Restore saved scanners',
                icon: const Icon(Icons.restore),
                onSelected: _restore,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: RestoreStrategy.firstAvailable,
                    child: Text('Restore first available'),
                  ),
                  PopupMenuItem(
                    value: RestoreStrategy.all,
                    child: Text('Restore all'),
                  ),
                ],
              ),
            ),
            if (mine.isEmpty)
              const _Hint('No scanners yet. Scan, then connect one below.'),
            for (final entry in mine) _myScannerTile(entry),
            _sectionTitle('Available (${available.length})'),
            if (available.isEmpty)
              _Hint(
                _discovery != null
                    ? 'Looking for scanners…'
                    : _found.isEmpty
                    ? 'Tap Scan to look for scanners.'
                    : 'Nothing new found.',
              ),
            for (final scanner in available) _availableTile(scanner),
            if (foundMine > 0)
              _Hint(
                'Also found $foundMine already in My scanners '
                '(marked "in range").',
              ),
          ],
        );
      },
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<NetumTransport>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: NetumTransport.ble,
                label: Text('BLE'),
              ),
              ButtonSegment(
                value: NetumTransport.spp,
                label: const Text('SPP'),
                enabled: _sppSupported,
              ),
            ],
            selected: {_transport},
            onSelectionChanged: (s) => setState(() => _transport = s.first),
          ),
          SegmentedButton<DiscoveryFilter>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: DiscoveryFilter.likelyNetum,
                label: Text('NETUM'),
              ),
              ButtonSegment(value: DiscoveryFilter.all, label: Text('All')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) {
              setState(() => _filter = s.first);
              unawaited(_reload());
            },
          ),
          FilterChip(
            label: const Text('Auto-reconnect'),
            selected: _state.autoReconnect,
            onSelected: (v) => _state.setAutoReconnect(value: v),
          ),
          if (_sppSupported)
            IconButton(
              tooltip: 'Pair by scanning (SPP)',
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PairPage(state: _state),
                ),
              ),
            ),
          if (_discovery == null)
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.search),
              label: const Text('Scan'),
            )
          else
            OutlinedButton(
              onPressed: _netum.stopDiscovery,
              child: const Text('Stop'),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _myScannerTile(_Entry entry) {
    final device = entry.device;
    final connected = entry.state == NetumConnectionState.connected;
    final reason = _state.lastReason[entry.id];
    final colors = Theme.of(context).colorScheme;
    // The current scan found it: it is nearby and ready to connect.
    final found = entry.state == NetumConnectionState.disconnected
        ? _found[entry.id]
        : null;
    return ExpansionTile(
      key: ValueKey('mine-${entry.id}'),
      leading: Icon(
        connected
            ? Icons.bluetooth_connected
            : found != null
            ? Icons.bluetooth_searching
            : Icons.bluetooth,
        color: connected || found != null ? colors.primary : null,
      ),
      title: _TitleWithBadge(entry.name ?? entry.id, entry.transport),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${entry.id}\n'),
            if (found != null)
              TextSpan(
                text: found.rssi == null
                    ? 'in range'
                    : 'in range · ${found.rssi} dBm',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              TextSpan(text: _stateLabel(entry)),
            TextSpan(
              text: [
                '',
                if (entry.saved != null) 'saved',
                if (entry.paired) 'paired',
                if (!connected && reason != null) 'last: $reason',
              ].join(' · '),
            ),
          ],
        ),
      ),
      trailing: _myScannerAction(entry),
      children: [
        if (device != null)
          SwitchListTile(
            dense: true,
            title: const Text('Auto-reconnect'),
            value: device.autoReconnect,
            onChanged: (value) {
              setState(() => device.autoReconnect = value);
              _state.log('${device.id} autoReconnect = $value');
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Wrap(
            spacing: 4,
            children: [
              if (connected && device != null) ...[
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
              if (entry.saved != null)
                TextButton(
                  onPressed: () => _forget(entry),
                  child: const Text('Forget'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _myScannerAction(_Entry entry) {
    final device = entry.device;
    switch (entry.state) {
      case NetumConnectionState.connected:
        return TextButton(
          onPressed: () =>
              _state.run('disconnect ${entry.id}', device!.disconnect),
          child: const Text('Disconnect'),
        );
      case NetumConnectionState.reconnecting:
        // Disconnecting stops the reconnect attempts.
        return TextButton.icon(
          onPressed: () =>
              _state.run('disconnect ${entry.id}', device!.disconnect),
          icon: const _Spinner(),
          label: const Text('Stop'),
        );
      case NetumConnectionState.connecting:
      case NetumConnectionState.disconnecting:
        return const Padding(padding: EdgeInsets.all(12), child: _Spinner());
      case NetumConnectionState.disconnected:
        return FilledButton.tonal(
          onPressed: () => _connect(entry),
          child: const Text('Connect'),
        );
    }
  }

  Widget _availableTile(DiscoveredScanner scanner) {
    final busy = _handle(scanner.id)?.state == NetumConnectionState.connecting;
    return ListTile(
      key: ValueKey('available-${scanner.id}'),
      leading: Icon(
        scanner.likelyNetum ? Icons.qr_code_scanner : Icons.devices_other,
      ),
      title: _TitleWithBadge(scanner.name ?? '(no name)', scanner.transport),
      subtitle: Text(
        [
          scanner.id,
          if (scanner.rssi != null) '${scanner.rssi} dBm',
          if (scanner.bonded) 'paired',
        ].join(' · '),
      ),
      trailing: busy
          ? const Padding(padding: EdgeInsets.all(12), child: _Spinner())
          : FilledButton.tonal(
              onPressed: () => _connect(
                _Entry(
                  id: scanner.id,
                  transport: scanner.transport,
                  name: scanner.name,
                ),
              ),
              child: const Text('Connect'),
            ),
    );
  }

  static String _stateLabel(_Entry entry) => switch (entry.state) {
    NetumConnectionState.connected => 'connected',
    NetumConnectionState.connecting => 'connecting…',
    NetumConnectionState.reconnecting => 'reconnecting…',
    NetumConnectionState.disconnecting => 'disconnecting…',
    NetumConnectionState.disconnected => 'not connected',
  };
}

/// One row of "My scanners".
class _Entry {
  const _Entry({
    required this.id,
    required this.transport,
    this.name,
    this.device,
    this.saved,
    this.paired = false,
  });

  factory _Entry.of(NetumDevice device) => _Entry(
    id: device.id,
    transport: device.transport,
    name: device.name,
    device: device,
  );

  final String id;
  final NetumTransport transport;
  final String? name;
  final NetumDevice? device;
  final SavedScanner? saved;
  final bool paired;

  NetumConnectionState get state =>
      device?.state ?? NetumConnectionState.disconnected;

  _Entry copyWith({NetumDevice? device, SavedScanner? saved, bool? paired}) =>
      _Entry(
        id: id,
        transport: transport,
        // The live handle knows the newest name (e.g. after a rename).
        name: device?.name ?? name,
        device: device ?? this.device,
        saved: saved ?? this.saved,
        paired: paired ?? this.paired,
      );
}

/// The scanner's name with a coloured BLE / SPP badge in front, so two
/// entries for the same scanner are easy to tell apart.
class _TitleWithBadge extends StatelessWidget {
  const _TitleWithBadge(this.title, this.transport);

  final String title;
  final NetumTransport transport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = transport == NetumTransport.ble
        ? (colors.primaryContainer, colors.onPrimaryContainer)
        : (colors.tertiaryContainer, colors.onTertiaryContainer);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            transport.name.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
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
