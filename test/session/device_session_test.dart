import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/protocol/classifier.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';
import 'package:netum_bluetooth_scanner/src/session/device_session.dart';
import 'package:netum_bluetooth_scanner/src/transport/transport.dart';

import '../helpers/fixtures.dart';
import '../helpers/hex.dart';

/// Records writes; each completes after [writeDelay].
class _FakeTransport extends Fake implements NetumTransportApi {
  final writes = <Uint8List>[];
  Duration writeDelay = Duration.zero;
  Error? writeError;

  @override
  Future<void> write(String id, Uint8List bytes) async {
    writes.add(bytes);
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    if (writeError case final error?) throw error;
  }
}

Uint8List _ascii(String text) => Uint8List.fromList(text.codeUnits);

/// Captures a future's outcome inside fake async.
class _Outcome<T> {
  _Outcome(Future<T> future) {
    unawaited(
      future.then<void>(
        (v) {
          value = v;
        },
        onError: (Object e) {
          error = e;
        },
      ),
    );
  }

  T? value;
  Object? error;
}

void main() {
  late _FakeTransport transport;
  late DeviceSession session;
  late List<SessionPacket> packets;

  void setUpSession(FakeAsync async) {
    transport = _FakeTransport();
    session = DeviceSession(deviceId: 'dev1', transport: transport)
      ..handleConnected();
    packets = [];
    session.packets.listen(packets.add);
    async.flushMicrotasks();
  }

  Iterable<SessionPacket> inbound() =>
      packets.where((p) => p.direction == PacketDirection.inbound);

  final scanTrigger = NetumCommand.scan.trigger(3);

  test('queued commands go out strictly one at a time', () {
    fakeAsync((async) {
      setUpSession(async);
      final first = _Outcome(session.send(NetumCommand.scan.trigger(3)));
      final second = _Outcome(session.send(NetumCommand.feedback.beep(10)));
      final third = _Outcome(session.send(NetumCommand.power.battery));
      async.flushMicrotasks();
      expect(transport.writes, [encodeFrame('%SCANTM#3#')]);

      session.handleData(hex('0E 0B'));
      async.flushMicrotasks();
      expect(first.value?.outcome, CommandOutcome.ack);
      expect(transport.writes, hasLength(2));

      session.handleData(hex('0C 0B'));
      async.flushMicrotasks();
      expect(second.value?.outcome, CommandOutcome.ack);
      expect(transport.writes.last, encodeFrame('%BAT_VOL#'));

      session.handleData(_ascii('BAT_VOL=3.81V 37%\r'));
      async.flushMicrotasks();
      expect(third.value?.reply, 'BAT_VOL=3.81V 37%');
      expect(third.value?.rawReply, _ascii('BAT_VOL=3.81V 37%\r'));
    });
  });

  test('an echo resolves a custom beep', () {
    fakeAsync((async) {
      setUpSession(async);
      final command = NetumCommand.feedback.customBeep(
        duration: const Duration(seconds: 1),
        frequencyHz: 4500,
      );
      final result = _Outcome(session.send(command));
      async.flushMicrotasks();

      session.handleData(encodeFrame(command.ascii));
      async.flushMicrotasks();

      expect(result.value?.outcome, CommandOutcome.echo);
    });
  });

  test('a timeout throws NetumCommandTimeout and the queue moves on', () {
    fakeAsync((async) {
      setUpSession(async);
      final first = _Outcome(session.send(scanTrigger));
      final second = _Outcome(session.send(NetumCommand.feedback.beep(10)));
      async.elapse(const Duration(milliseconds: 1499));
      expect(first.error, isNull);

      async.elapse(const Duration(milliseconds: 1));
      expect(first.error, isA<NetumCommandTimeout>());
      expect(transport.writes, hasLength(2));

      // The late ACK of the first command is stray, never a barcode.
      session.handleData(hex('0E 0B'));
      async.flushMicrotasks();
      expect(inbound().last.kind, InboundKind.strayAck);
      expect(second.value, isNull);
    });
  });

  test('a custom timeout applies', () {
    fakeAsync((async) {
      setUpSession(async);
      final result = _Outcome(
        session.send(scanTrigger, timeout: const Duration(milliseconds: 200)),
      );
      async.elapse(const Duration(milliseconds: 200));

      expect(result.error, isA<NetumCommandTimeout>());
    });
  });

  group('replies', () {
    test('a barcode during a prefixed query is still a scan', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(session.send(NetumCommand.power.battery));
        async.flushMicrotasks();

        session.handleData(_ascii('7771609001660\r'));
        async.flushMicrotasks();
        expect(inbound().last.kind, InboundKind.barcode);
        expect(inbound().last.text, '7771609001660');
        expect(result.value, isNull);

        session.handleData(_ascii('BAT_VOL=3.81V 37%\r'));
        async.flushMicrotasks();
        expect(result.value?.outcome, CommandOutcome.reply);
      });
    });

    test('an unprefixed reply within the window answers the query', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(
          session.send(NetumCommand.system.firmwareVersion),
        );
        async.elapse(const Duration(milliseconds: 40));

        session.handleData(_ascii('bn0HDS_RFSBTD43bc_CB071\r'));
        async.flushMicrotasks();

        expect(result.value?.reply, 'bn0HDS_RFSBTD43bc_CB071');
      });
    });

    test('text after the window closes is a barcode', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(
          session.send(NetumCommand.system.firmwareVersion),
        );
        async.elapse(const Duration(milliseconds: 301));

        session.handleData(_ascii('7771609001660\r'));
        async.flushMicrotasks();
        expect(inbound().last.kind, InboundKind.barcode);

        async.elapse(const Duration(seconds: 2));
        expect(result.error, isA<NetumCommandTimeout>());
      });
    });

    test('a reply that beats the write callback still counts', () {
      fakeAsync((async) {
        setUpSession(async);
        transport.writeDelay = const Duration(milliseconds: 50);
        final result = _Outcome(
          session.send(NetumCommand.system.firmwareVersion),
        );
        async.elapse(const Duration(milliseconds: 30));

        session.handleData(_ascii('bn0HDS_RFSBTD43bc_CB071\r'));
        async.elapse(const Duration(milliseconds: 30));

        expect(result.value?.outcome, CommandOutcome.reply);
      });
    });
  });

  group('sendRaw', () {
    test('a framed query is answered by its reply (no ACK needed)', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(session.sendRaw('%BAT_VOL#'));
        async.elapse(const Duration(milliseconds: 30));

        session.handleData(_ascii('BAT_VOL=3.76V 30%\r'));
        async.flushMicrotasks();

        expect(result.value?.reply, 'BAT_VOL=3.76V 30%');
      });
    });

    test('a framed action is answered by its ACK', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(session.sendRaw('%SCANTM#1#'));
        async.flushMicrotasks();

        session.handleData(hex('0E 0B'));
        async.flushMicrotasks();

        expect(result.value?.outcome, CommandOutcome.ack);
      });
    });

    test('a raw send with no response resolves as sentRaw', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(session.sendRaw('%SCANTM#1#', framed: false));
        async.flushMicrotasks();
        expect(transport.writes.single, _ascii('%SCANTM#1#'));

        async.elapse(const Duration(milliseconds: 299));
        expect(result.value, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(result.value?.outcome, CommandOutcome.sentRaw);
      });
    });

    test('a raw query gets its reply', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(session.sendRaw(r'$SW#VER', framed: false));
        async.elapse(const Duration(milliseconds: 40));

        session.handleData(_ascii('bn0HDS_RFSBTD43bc_CB071\r'));
        async.flushMicrotasks();

        expect(result.value?.outcome, CommandOutcome.reply);
      });
    });

    test('rejects non-ASCII text', () {
      fakeAsync((async) {
        setUpSession(async);
        expect(
          () => session.sendRaw('Ñ'),
          throwsA(isA<NetumInvalidArgument>()),
        );
      });
    });
  });

  group('disconnects', () {
    test('an expected disconnect resolves the command', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(
          session.send(NetumCommand.system.setName('Netum-01')),
        );
        async.elapse(const Duration(milliseconds: 100));

        session.handleDisconnected();
        async.flushMicrotasks();

        expect(result.value?.outcome, CommandOutcome.disconnected);
      });
    });

    test('an expected disconnect that never comes times out after 3 s', () {
      fakeAsync((async) {
        setUpSession(async);
        final result = _Outcome(session.send(NetumCommand.power.powerOff));
        async.elapse(const Duration(milliseconds: 2999));
        expect(result.error, isNull);

        async.elapse(const Duration(milliseconds: 1));
        expect(result.error, isA<NetumCommandTimeout>());
      });
    });

    test('a disconnect fails the pending and queued commands', () {
      fakeAsync((async) {
        setUpSession(async);
        final pending = _Outcome(session.send(scanTrigger));
        final queued = _Outcome(session.send(NetumCommand.power.battery));
        async.flushMicrotasks();

        session.handleDisconnected();
        async.flushMicrotasks();

        expect(pending.error, isA<NetumNotConnected>());
        expect(queued.error, isA<NetumNotConnected>());
        expect(transport.writes, hasLength(1));
      });
    });

    test('commands while disconnected throw NetumNotConnected', () {
      fakeAsync((async) {
        setUpSession(async);
        session.handleDisconnected();

        final result = _Outcome(session.send(scanTrigger));
        async.flushMicrotasks();

        expect(result.error, isA<NetumNotConnected>());
        expect(transport.writes, isEmpty);
      });
    });

    test('a disconnect drops partially buffered bytes', () {
      fakeAsync((async) {
        setUpSession(async);
        session
          ..handleData(_ascii('PARTIAL'))
          ..handleDisconnected()
          ..handleConnected();
        async.elapse(const Duration(seconds: 1));

        expect(inbound(), isEmpty);
      });
    });

    test('a failed write fails the command', () {
      fakeAsync((async) {
        setUpSession(async);
        transport.writeError = StateError('write failed');
        final result = _Outcome(session.send(scanTrigger));
        async.flushMicrotasks();

        expect(result.error, isA<StateError>());
      });
    });
  });

  test('packets carry outbound commands and decoded barcodes', () {
    fakeAsync((async) {
      setUpSession(async);
      unawaited(session.send(scanTrigger));
      async.flushMicrotasks();
      session
        ..handleData(hex('0E 0B'))
        ..handleData(_ascii('7771609001660\r'));
      async.flushMicrotasks();

      expect(packets.map((p) => p.direction), [
        PacketDirection.outbound,
        PacketDirection.inbound,
        PacketDirection.inbound,
      ]);
      expect(packets.first.command, scanTrigger);
      expect(packets[1].kind, InboundKind.ack);
      expect(packets[2].kind, InboundKind.barcode);
      expect(packets[2].text, '7771609001660');
      expect(packets[2].bytes, _ascii('7771609001660\r'));
    });
  });

  test('close fails outstanding commands and closes packets', () {
    fakeAsync((async) {
      setUpSession(async);
      final result = _Outcome(session.send(scanTrigger));
      var closed = false;
      session.packets.listen(null, onDone: () => closed = true);
      async.flushMicrotasks();

      unawaited(session.close());
      async.flushMicrotasks();

      expect(result.error, isA<NetumNotConnected>());
      expect(closed, isTrue);
    });
  });

  group('replaying captured Android traffic', () {
    final sessions = loadFixtureSessions().where(
      (s) => s.source.startsWith('android') && s.packets.length > 2,
    );
    for (final fixture in sessions) {
      test('${fixture.source} ${fixture.transport}', () {
        fakeAsync((async) {
          setUpSession(async);
          final start = async.elapsed;
          var expected = <InboundKind>[];
          for (final packet in fixture.packets) {
            final at = Duration(microseconds: (packet.tMs! * 1000).round());
            async.elapse(at - (async.elapsed - start));
            if (packet.inbound) {
              session.handleData(packet.bytes);
              expected = [...expected, InboundKind.values.byName(packet.kind!)];
            } else if (!packet.ascii!.startsWith('AT+NAME=')) {
              // Responses are unknown up front, as with sendRaw.
              unawaited(
                session
                    .sendRaw(packet.ascii!, framed: packet.framed!)
                    .catchError((_) => const CommandResult(CommandOutcome.ack)),
              );
            }
            async.flushMicrotasks();
          }
          expect(inbound().map((p) => p.kind), expected);
        });
      });
    }
  });
}
