import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'hex.dart';

/// A command that was awaiting a response when a packet arrived.
class FixturePending {
  const FixturePending({required this.ascii, required this.framed});

  final String ascii;
  final bool framed;
}

/// One captured packet.
class FixturePacket {
  const FixturePacket({
    required this.inbound,
    required this.bytes,
    this.tMs,
    this.kind,
    this.pending,
    this.sinceWriteMs,
    this.ascii,
    this.framed,
    this.note,
  });

  factory FixturePacket.fromJson(Map<String, Object?> json) {
    final pending = json['pending'] as Map<String, Object?>?;
    return FixturePacket(
      inbound: json['dir'] == 'in',
      bytes: hex(json['hex']! as String),
      tMs: (json['tMs'] as num?)?.toDouble(),
      kind: json['kind'] as String?,
      pending: pending == null
          ? null
          : FixturePending(
              ascii: pending['ascii']! as String,
              framed: pending['framed']! as bool,
            ),
      sinceWriteMs: (json['sinceWriteMs'] as num?)?.toDouble(),
      ascii: json['ascii'] as String?,
      framed: json['framed'] as bool?,
      note: json['note'] as String?,
    );
  }

  final bool inbound;
  final Uint8List bytes;
  final double? tMs;

  /// Inbound only: `ack`, `echo`, `reply` or `barcode`.
  final String? kind;
  final FixturePending? pending;
  final double? sinceWriteMs;

  /// Outbound only: the command text and whether it was framed.
  final String? ascii;
  final bool? framed;
  final String? note;
}

/// One device's traffic from one log.
class FixtureSession {
  const FixtureSession({
    required this.source,
    required this.transport,
    required this.device,
    required this.packets,
  });

  final String source;
  final String transport;
  final String device;
  final List<FixturePacket> packets;

  Iterable<FixturePacket> get inbound => packets.where((p) => p.inbound);
}

/// Loads `test/fixtures/packets.json`.
List<FixtureSession> loadFixtureSessions() {
  final json =
      jsonDecode(File('test/fixtures/packets.json').readAsStringSync())
          as Map<String, Object?>;
  return [
    for (final session in json['sessions']! as List<Object?>)
      if (session case final Map<String, Object?> s)
        FixtureSession(
          source: s['source']! as String,
          transport: s['transport']! as String,
          device: s['device']! as String,
          packets: [
            for (final packet in s['packets']! as List<Object?>)
              FixturePacket.fromJson(packet! as Map<String, Object?>),
          ],
        ),
  ];
}

/// Every inbound packet across all sessions.
List<FixturePacket> loadInboundFixtures() => [
  for (final session in loadFixtureSessions()) ...session.inbound,
];
