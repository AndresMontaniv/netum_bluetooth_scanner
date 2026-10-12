import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/src/protocol/classifier.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

import '../helpers/fixtures.dart';
import '../helpers/hex.dart';

/// Reply prefixes of the prefixed queries seen in the fixtures.
const _prefixed = {
  '%BAT_VOL#': 'BAT_VOL=',
  '%#+TCNT': 'Total Counters=',
  r'$RF#ST': 'Sleeptime=',
  'AT+NAME': '+NAME=',
  'AT+ADDR': '+ADDR=',
  'AT+VER': '+VER=',
};

/// Queries whose replies have no prefix.
const _unprefixed = {r'$SW#VER', '%MODULESN#'};

const _replyWindowMs = 300;

PendingResponse _pendingFor(
  FixturePending pending, {
  required bool windowOpen,
}) {
  final ascii = pending.ascii;
  final ResponseExpectation expectation;
  if (!pending.framed) {
    expectation = ResponseExpectation.any; // sendRaw
  } else if (_prefixed.containsKey(ascii)) {
    expectation = ResponseExpectation.prefixedReply;
  } else if (_unprefixed.contains(ascii)) {
    expectation = ResponseExpectation.unprefixedReply;
  } else {
    expectation = ResponseExpectation.ackOrEcho;
  }
  return PendingResponse(
    sentBytes: pending.framed
        ? encodeFrame(ascii)
        : Uint8List.fromList(ascii.codeUnits),
    framed: pending.framed,
    expectation: expectation,
    replyPrefix: _prefixed[ascii],
  )..replyWindowOpen = windowOpen;
}

PendingResponse _action(String ascii) => PendingResponse(
  sentBytes: encodeFrame(ascii),
  framed: true,
  expectation: ResponseExpectation.ackOrEcho,
);

Uint8List _ascii(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  group('over all captured packets', () {
    for (final packet in loadInboundFixtures()) {
      final pending = packet.pending;
      final description =
          '${toHex(packet.bytes)} (pending: ${pending?.ascii ?? 'none'})';
      test(description, () {
        // The iOS log has no timestamps; its responses follow their writes
        // directly, so the window counts as open.
        final since = packet.sinceWriteMs;
        final windowOpen = since == null || since <= _replyWindowMs;
        final expected = InboundKind.values.byName(packet.kind!);

        final actual = classifyPayload(
          packet.bytes,
          pending == null ? null : _pendingFor(pending, windowOpen: windowOpen),
        );

        expect(actual, expected);
      });
    }
  });

  group('ACKs', () {
    test('an ACK matching the pending frame LEN is an ack', () {
      expect(
        classifyPayload(hex('0E 0B'), _action('%SCANTM#3#')),
        InboundKind.ack,
      );
    });

    test('an ACK with nothing pending is stray, not a barcode', () {
      expect(classifyPayload(hex('0E 0B'), null), InboundKind.strayAck);
    });

    test('a late ACK with a different LEN is stray, not a barcode', () {
      // 0B 0B would acknowledge a 7-character command; %SCANTM#3# has LEN 0E.
      expect(
        classifyPayload(hex('0B 0B'), _action('%SCANTM#3#')),
        InboundKind.strayAck,
      );
    });

    test('an ACK while a query is pending is stray', () {
      final query = PendingResponse(
        sentBytes: encodeFrame('%BAT_VOL#'),
        framed: true,
        expectation: ResponseExpectation.prefixedReply,
        replyPrefix: 'BAT_VOL=',
      );
      expect(classifyPayload(hex('0D 0B'), query), InboundKind.strayAck);
    });

    test('a raw send never gets an ack', () {
      final raw = PendingResponse(
        sentBytes: _ascii('%SCANTM#1#'),
        framed: false,
        expectation: ResponseExpectation.any,
      );
      expect(classifyPayload(hex('0E 0B'), raw), InboundKind.strayAck);
    });
  });

  group('echoes', () {
    test('the pending frame echoed back is an echo', () {
      final frame = encodeFrame(r'$BUZZ#BK650dc');
      expect(
        classifyPayload(frame, _action(r'$BUZZ#BK650dc')),
        InboundKind.echo,
      );
    });

    test('a frame matching nothing pending is stray, not a barcode', () {
      expect(
        classifyPayload(encodeFrame(r'$BUZZ#BK650dc'), null),
        InboundKind.strayFrame,
      );
    });
  });

  group('replies', () {
    test('a prefixed reply is accepted outside the window', () {
      final query = PendingResponse(
        sentBytes: encodeFrame('%BAT_VOL#'),
        framed: true,
        expectation: ResponseExpectation.prefixedReply,
        replyPrefix: 'BAT_VOL=',
      );
      expect(
        classifyPayload(_ascii('BAT_VOL=3.81V 37%\r'), query),
        InboundKind.reply,
      );
    });

    test('a barcode during a prefixed query stays a barcode', () {
      final query = PendingResponse(
        sentBytes: encodeFrame('%BAT_VOL#'),
        framed: true,
        expectation: ResponseExpectation.prefixedReply,
        replyPrefix: 'BAT_VOL=',
      )..replyWindowOpen = true;
      expect(
        classifyPayload(_ascii('7771609001660\r'), query),
        InboundKind.barcode,
      );
    });

    test('an unprefixed reply needs the window open', () {
      final query = PendingResponse(
        sentBytes: encodeFrame(r'$SW#VER'),
        framed: true,
        expectation: ResponseExpectation.unprefixedReply,
      );
      final reply = _ascii('bn0HDS_RFSBTD43bc_CB071\r');

      expect(classifyPayload(reply, query), InboundKind.barcode);
      query.replyWindowOpen = true;
      expect(classifyPayload(reply, query), InboundKind.reply);
    });

    test('a sendRaw takes text within the window as its reply', () {
      final raw = PendingResponse(
        sentBytes: _ascii('%BAT_VOL#'),
        framed: false,
        expectation: ResponseExpectation.any,
      )..replyWindowOpen = true;
      expect(
        classifyPayload(_ascii('BAT_VOL=3.76V 30%\r'), raw),
        InboundKind.reply,
      );
    });
  });

  group('barcodes', () {
    test('text with nothing pending is a barcode', () {
      expect(
        classifyPayload(_ascii('7771609001660\r'), null),
        InboundKind.barcode,
      );
    });

    test('text while an action is pending is a barcode', () {
      expect(
        classifyPayload(_ascii('7771609001660\r'), _action('%SCANTM#3#')),
        InboundKind.barcode,
      );
    });
  });
}
