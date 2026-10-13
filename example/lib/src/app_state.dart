import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';

/// Long-lived listener: keeps the scan log and connection history across
/// tabs, and mirrors everything to the console as `NETUM …` lines.
class AppState extends ChangeNotifier {
  AppState(this.netum) {
    _subscriptions
      ..add(netum.scans.listen(_onScan))
      ..add(netum.connectionEvents.listen(_onConnection))
      ..add(netum.adapterState.listen((s) => log('adapter ${s.name}')))
      ..add(
        netum.traffic.listen(
          (t) => log(
            'traffic ${t.device.name ?? t.deviceId} ${t.direction.name} '
            '${t.kind.name} [${hex(t.bytes)}]'
            '${t.text == null ? '' : ' "${t.text}"'}',
          ),
        ),
      );
  }

  final NetumScanner netum;

  /// Auto-reconnect for new connections (Discover tab).
  bool autoReconnect = true;

  bool get trafficLogEnabled => netum.trafficLogEnabled;

  set trafficLogEnabled(bool value) {
    netum.trafficLogEnabled = value;
    log('traffic log ${value ? 'on' : 'off'}');
  }

  void setAutoReconnect({required bool value}) {
    autoReconnect = value;
    notifyListeners();
  }

  final scans = <ScanEvent>[];
  final lines = <String>[];
  final lastReason = <String, DisconnectReason>{};
  final _subscriptions = <StreamSubscription<Object?>>[];

  void log(String message) {
    debugPrint('NETUM $message');
    lines.insert(0, '${_time(DateTime.now())}  $message');
    if (lines.length > 300) lines.removeLast();
    notifyListeners();
  }

  /// Runs [action], logging its result or error.
  Future<void> run(String label, Future<Object?> Function() action) async {
    try {
      final result = await action();
      log('$label → ${result ?? 'ok'}');
    } on NetumException catch (error) {
      log('$label ✗ $error');
    }
  }

  void clearScans() {
    scans.clear();
    notifyListeners();
  }

  void _onScan(ScanEvent scan) {
    scans.insert(0, scan);
    if (scans.length > 200) scans.removeLast();
    log(
      'scan ${scan.device.name ?? scan.deviceId}: "${scan.text}" '
      '[${hex(scan.raw)}]',
    );
  }

  void _onConnection(ConnectionEvent event) {
    if (event.reason case final reason?) lastReason[event.deviceId] = reason;
    log(
      '${event.device.name ?? event.deviceId} ${event.state.name}'
      '${event.reason == null ? '' : ' (${event.reason})'}',
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  static String hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
