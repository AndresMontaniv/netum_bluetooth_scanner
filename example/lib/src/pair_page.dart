import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner_example/src/app_state.dart';

/// SPP "pair by scanning": shows `AT+SPPCONN=<phone MAC>` as Code 128 and
/// connects to the scanner that dials in after scanning it.
class PairPage extends StatefulWidget {
  const PairPage({required this.state, super.key});

  final AppState state;

  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final _mac = TextEditingController(
    text: const String.fromEnvironment('NETUM_PHONE_MAC'),
  );
  StreamSubscription<DiscoveredScanner>? _listening;
  String _status =
      'Enter this phone’s Bluetooth MAC '
      '(Settings → About phone → Status → Bluetooth address).';

  AppState get _state => widget.state;

  String? get _data {
    try {
      return NetumScanner.sppPairingBarcodeData(_mac.text);
    } on NetumInvalidArgument {
      return null;
    }
  }

  void _listen() {
    unawaited(_listening?.cancel());
    setState(() => _status = 'Listening… scan the barcode with the scanner.');
    _state.log('listenForSppScanner');
    _listening = _state.netum.listenForSppScanner().listen(
      (scanner) {
        _state.log('scanner dialled in: ${scanner.id} "${scanner.name}"');
        setState(
          () => _status = 'Connecting to ${scanner.name ?? scanner.id}…',
        );
        unawaited(
          _state.run(
            'connect ${scanner.name ?? scanner.id}',
            () => _state.netum.connect(
              scanner.id,
              transport: NetumTransport.spp,
              name: scanner.name,
              autoReconnect: _state.autoReconnect,
            ),
          ),
        );
      },
      onError: (Object error) {
        _state.log('listenForSppScanner ✗ $error');
        if (mounted) setState(() => _status = 'Error: $error');
      },
      onDone: () {
        if (mounted) setState(() => _listening = null);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_listening?.cancel());
    _mac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Pair by scanning (SPP)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _mac,
            decoration: const InputDecoration(
              labelText: 'Phone Bluetooth MAC',
              hintText: 'AA:BB:CC:DD:EE:FF',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          if (data != null) ...[
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: data,
              height: 120,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            if (_listening == null)
              FilledButton(onPressed: _listen, child: const Text('Listen'))
            else
              OutlinedButton(
                onPressed: _state.netum.stopListeningForSppScanner,
                child: const Text('Stop listening'),
              ),
          ],
          const SizedBox(height: 16),
          Text(_status),
        ],
      ),
    );
  }
}
