// The S0 smoke screen uses the internal transport directly; it is replaced by
// the public NetumScanner API in S2.
// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:netum_bluetooth_scanner/src/generated/netum_api.g.dart';
import 'package:netum_bluetooth_scanner/src/transport/pigeon_transport.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

void main() {
  runApp(ExampleApp(transport: PigeonTransport()));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({required this.transport, super.key});

  final NetumTransportApi transport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NETUM scanner example',
      home: SmokeScreen(transport: transport),
    );
  }
}

/// Exercises both channel directions: host calls and the adapter-state event
/// stream.
class SmokeScreen extends StatefulWidget {
  const SmokeScreen({required this.transport, super.key});

  final NetumTransportApi transport;

  @override
  State<SmokeScreen> createState() => _SmokeScreenState();
}

class _SmokeScreenState extends State<SmokeScreen> {
  final _log = <String>[];
  StreamSubscription<AdapterStateMsg>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.transport.adapterStates.listen(
      (state) => _record('adapterStates event: ${state.name}'),
      onError: (Object error) => _record('adapterStates error: $error'),
    );
    unawaited(_callHost());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _callHost() async {
    try {
      final links = await widget.transport.initialize();
      _record('initialize(): ${links.length} active links');
      final state = await widget.transport.adapterState();
      _record('adapterState(): ${state.name}');
    } on Exception catch (error) {
      _record('host call failed: $error');
    }
  }

  void _record(String message) {
    final time = TimeOfDay.now().format(context);
    debugPrint('NETUM $message');
    if (!mounted) return;
    setState(() => _log.insert(0, '$time  $message'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NETUM scanner example')),
      floatingActionButton: FloatingActionButton(
        onPressed: _callHost,
        tooltip: 'Call adapterState()',
        child: const Icon(Icons.refresh),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _log.length,
        itemBuilder: (context, index) => Text(_log[index]),
      ),
    );
  }
}
