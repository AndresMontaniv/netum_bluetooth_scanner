import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

const SystemCommands _system = NetumCommand.system;
const WorkModeCommands _workMode = NetumCommand.workMode;
const PowerCommands _power = NetumCommand.power;
const FeedbackCommands _feedback = NetumCommand.feedback;
const ScanCommands _scan = NetumCommand.scan;
const FormatCommands _format = NetumCommand.format;
const KeyboardCommands _keyboard = NetumCommand.keyboard;
const DangerousCommands _dangerous = NetumCommand.dangerous;

/// Every catalog command with a fixed text, against `doc/commands.md`.
final _fixed = <NetumCommand, String>{
  _system.firmwareVersion: r'$SW#VER',
  _system.interfaceSetting: r'%#IFSNO$',
  _system.decodeEngine: '%MODULESN#',
  _system.bluetoothName: 'AT+NAME',
  _system.bluetoothAddress: 'AT+ADDR',
  _system.bluetoothFirmware: 'AT+VER',
  _system.disconnect: 'AT+DISC',
  _workMode.normal: '%#NORMD',
  _workMode.inventory: '%#INVMD',
  _workMode.upload: '%#TXMEM',
  _workMode.uploadAndClear: '%#TXMEM#C',
  _workMode.storedCount: '%#+TCNT',
  _workMode.storedCountAndUsage: '%#+TCNT#',
  _workMode.clearStored: '%#*NEW*',
  _power.battery: '%BAT_VOL#',
  _power.sleepTimeout: r'$RF#ST',
  _power.powerOff: r'$POWER#OFF',
  _feedback.baseConnectBeepToggle: '%ACKBEEP#2',
  _format.clear: r'$DATA#0',
  _format.enableSuffix: r'$DATA#1',
  _format.enablePrefix: r'$DATA#2',
  _format.enableHideTail: r'$DATA#3',
  _format.enableHideMiddle: r'$DATA#4',
  _format.enableHideHead: r'$DATA#5',
  _keyboard.toggleOnScreenKeyboard: '%%0S',
  _keyboard.holdTriggerTogglesKeyboard: '%%0H3',
  _keyboard.doubleClickTogglesKeyboard: '%%0HH',
  _keyboard.capsLockIgnoreToggle: '%%0HL',
  _keyboard.holdTriggerSwitchesRadio: '%%0H8',
  _keyboard.charset: '%CHARSET#',
  _keyboard.hostOs: r'$KB#OS',
  _keyboard.language: r'$LAN#',
  _keyboard.hidKeyDelay: 'AT+HIDDLY',
  _dangerous.factoryReset: r'%#IFSNO$B',
  _dangerous.bluetoothOutput: r'%#IFSNO$4',
  _dangerous.moduleReboot: 'AT+REBOOT',
  _dangerous.moduleFactoryReset: 'AT+RESTORE',
  _dangerous.clearPairing: '%%ALL-CH',
  _dangerous.usbKeyboard: r'%#IFSNO$2',
  _dangerous.usbVirtualCom: r'%#IFSNO$3',
};

/// Every enum-parameter builder output, against `doc/commands.md`.
final _built = <NetumCommand, String>{
  for (final (mode, code) in [
    (NetumMode.spp, '1'),
    (NetumMode.hid, '2'),
    (NetumMode.ble, '3'),
  ])
    _dangerous.mode(mode): 'AT+MODE=$code',
  for (final (volume, code) in [
    (BeepVolume.mute, '0'),
    (BeepVolume.high, '1'),
    (BeepVolume.medium, '2'),
    (BeepVolume.low, '3'),
  ])
    _feedback.volume(volume): '\$BUZZ#$code',
  _feedback.tone(BeepTone.high): r'$BUZZ#4',
  _feedback.tone(BeepTone.low): r'$BUZZ#5',
  _feedback.vibration(enabled: true): r'$MOTO#1',
  _feedback.vibration(enabled: false): r'$MOTO#0',
  _feedback.ackBeep(enabled: true): '%ACKBEEP#1',
  _feedback.ackBeep(enabled: false): '%ACKBEEP#0',
  _workMode.autoSave(enabled: true): '%AutoSav#On',
  _workMode.autoSave(enabled: false): '%AutoSav#Off',
  for (final (timeout, code) in [
    (SleepTimeout.never, '00'),
    (SleepTimeout.minutes1, '02'),
    (SleepTimeout.minutes3, '06'),
    (SleepTimeout.minutes5, '10'),
    (SleepTimeout.minutes10, '20'),
    (SleepTimeout.minutes30, '60'),
    (SleepTimeout.hours1, '<0'),
    (SleepTimeout.hours2, 'H0'),
  ])
    _power.setSleepTimeout(timeout): '\$RF#ST$code',
  _scan.mode(ScanMode.trigger): '%SCMD#00#',
  _scan.mode(ScanMode.continuous): '%SCMD#01#',
  _scan.mode(ScanMode.pulse): '%SCMD#02#',
  _scan.mode(ScanMode.host): '%SCMD#03#',
  _scan.decodeTimeout(DecodeTimeout.seconds3): '%SCMD#3000D',
  _scan.decodeTimeout(DecodeTimeout.seconds6): '%SCMD#6000D',
  _scan.interval(ScanInterval.milliseconds500): '%SCMD#0500I',
  _scan.interval(ScanInterval.seconds1): '%SCMD#1000I',
  for (final (terminator, code) in [
    (Terminator.none, '0'),
    (Terminator.cr, '1'),
    (Terminator.tab, '2'),
    (Terminator.crlf, '3'),
    (Terminator.lf, '4'),
  ])
    _format.terminator(terminator): '\$TERM#$code',
  for (final mode in CaseMode.values)
    _keyboard.caseMode(mode): '%LKLED#${mode.index}',
  for (final (charset, code) in [
    (Charset.auto, '0'),
    (Charset.ansi, '1'),
    (Charset.utf8Word, '2'),
    (Charset.utf8Text, '21'),
    (Charset.iso8859, '3'),
    (Charset.normal, '4'),
  ])
    _keyboard.setCharset(charset): '%CHARSET#$code',
  _keyboard.setHostOs(HostOs.windows): r'$KB#OS0',
  _keyboard.setHostOs(HostOs.apple): r'$KB#OS1',
  _keyboard.setHostOs(HostOs.android): r'$KB#OS2',
  _keyboard.setLanguage(KeyboardLanguage.latinAmericanSpanish): r'$LAN#EL',
  _keyboard.setLanguage(KeyboardLanguage.swissGerman): r'$LAN#DS',
  _keyboard.setHidKeyDelay(HidKeyDelay.low): 'AT+HIDDLY=2',
  _keyboard.setHidKeyDelay(HidKeyDelay.medium): 'AT+HIDDLY=10',
  _keyboard.setHidKeyDelay(HidKeyDelay.high): 'AT+HIDDLY=30',
  _keyboard.controlCombos(enabled: true): r'$KEY#M1',
  _keyboard.controlCombos(enabled: false): r'$KEY#M0',
  _keyboard.autoWiredWireless(enabled: true): '%000604',
  _keyboard.autoWiredWireless(enabled: false): '%000605',
  _keyboard.wiredLatency(WiredLatency.low): '%KB#SP0',
  _keyboard.wiredLatency(WiredLatency.medium): '%KB#SP7',
  _keyboard.wiredLatency(WiredLatency.high): '%KB#SP?',
  _dangerous.wiredMultiKey(enabled: true): r'%#IFSNO$6',
  _dangerous.wiredMultiKey(enabled: false): r'%#IFSNO$7',
};

void main() {
  group('catalog text', () {
    for (final MapEntry(key: command, value: ascii) in {
      ..._fixed,
      ..._built,
    }.entries) {
      test(ascii, () {
        expect(command.ascii, ascii);
        expect(() => encodeFrame(command.ascii), returnsNormally);
      });
    }

    test('all 30 keyboard languages have distinct two-letter codes', () {
      final codes = KeyboardLanguage.values.map((l) => l.code).toSet();
      expect(codes, hasLength(30));
      expect(codes.every(RegExp(r'^[A-Z]{2}$').hasMatch), isTrue);
    });
  });

  group('kinds', () {
    test('prefixed queries carry their reply prefix', () {
      expect(_power.battery.replyPrefix, 'BAT_VOL=');
      expect(_workMode.storedCount.replyPrefix, 'Total Counters=');
      expect(_power.sleepTimeout.replyPrefix, 'Sleeptime=');
      expect(_system.bluetoothName.replyPrefix, '+NAME=');
      expect(_system.bluetoothAddress.replyPrefix, '+ADDR=');
      expect(_system.bluetoothFirmware.replyPrefix, '+VER=');
    });

    test('firmware version and decode engine are unprefixed queries', () {
      for (final command in [_system.firmwareVersion, _system.decodeEngine]) {
        expect(command.kind, CommandKind.query);
        expect(command.replyPrefix, isNull);
      }
    });

    test('actions have no reply prefix', () {
      final actions = {..._fixed.keys, ..._built.keys}.where(
        (c) => c.kind == CommandKind.action,
      );
      expect(actions, isNotEmpty);
      expect(actions.every((c) => c.replyPrefix == null), isTrue);
    });

    test('link-dropping commands expect a disconnect', () {
      for (final command in [
        _system.setName('Netum-01'),
        _system.disconnect,
        _power.powerOff,
        _dangerous.mode(NetumMode.spp),
        _dangerous.moduleReboot,
        _dangerous.moduleFactoryReset,
        _dangerous.clearPairing,
      ]) {
        expect(command.expectsDisconnect, isTrue, reason: command.ascii);
      }
      expect(_feedback.beep(10).expectsDisconnect, isFalse);
    });
  });

  group('builders', () {
    test('beep encodes level as a character from 0x30', () {
      expect(_feedback.beep(0).ascii, r'$BUZZ#B0');
      expect(_feedback.beep(10).ascii, r'$BUZZ#B:');
      expect(_feedback.beep(20).ascii, r'$BUZZ#BD');
      expect(_feedback.beep(26).ascii, r'$BUZZ#BJ');
    });

    test('customBeep matches the verified vendor bytes', () {
      // 1000 ms, beep + vibration, 4500 Hz → $BUZZ#BK650dc (echoed by the
      // DS5000).
      final command = _feedback.customBeep(
        duration: const Duration(milliseconds: 1000),
        frequencyHz: 4500,
      );
      expect(command.ascii, r'$BUZZ#BK650dc');
      expect(command.experimental, isTrue);
    });

    test('customBeep pads short values to two digits', () {
      final command = _feedback.customBeep(
        duration: const Duration(milliseconds: 100),
        frequencyHz: 100,
        type: BeepType.vibrateOnly,
      );
      expect(command.ascii, r'$BUZZ#BK0b200');
    });

    test('trigger', () {
      expect(_scan.trigger(1).ascii, '%SCANTM#1#');
      expect(_scan.trigger(7).ascii, '%SCANTM#7#');
    });

    test('setName', () {
      expect(_system.setName('Netum-01').ascii, 'AT+NAME=Netum-01');
    });

    test('prefix and suffix use a two-digit hex length', () {
      expect(_format.prefix('NETUM12345').ascii, r'$DATA#200ANETUM12345#');
      expect(_format.suffix('abcd\x03').ascii, '\$DATA#1005abcd\x03#');
    });

    test('hide commands use two-digit hex counts', () {
      expect(_format.hideTail(8).ascii, r'$DATA#3008#');
      expect(_format.hideMiddle(5, 10).ascii, r'$DATA#40050A#');
      expect(_format.hideHead(17).ascii, r'$DATA#5011#');
    });

    test('setClock sends the local wall-clock time as epoch seconds', () {
      final command = _system.setClock(DateTime(2026, 10, 7, 9, 51));
      final expected =
          DateTime.utc(2026, 10, 7, 9, 51).millisecondsSinceEpoch ~/ 1000;
      expect(command.ascii, '%RTCSTAMP#$expected');
    });

    test('timestamp', () {
      expect(_system.timestamp(enabled: true).ascii, '%RTCSTAMP#1');
      expect(_system.timestamp(enabled: false).ascii, '%RTCSTAMP#0');
    });

    test('setDecodeEngine', () {
      expect(_dangerous.setDecodeEngine(3).ascii, '%MODULESN#3#');
    });
  });

  group('validation', () {
    final invalid = throwsA(isA<NetumInvalidArgument>());

    test('trigger is 1–7 seconds', () {
      expect(() => _scan.trigger(0), invalid);
      expect(() => _scan.trigger(8), invalid);
    });

    test('beep is 0–26', () {
      expect(() => _feedback.beep(-1), invalid);
      expect(() => _feedback.beep(27), invalid);
    });

    test('customBeep ranges', () {
      expect(
        () => _feedback.customBeep(
          duration: const Duration(milliseconds: 9),
          frequencyHz: 1000,
        ),
        invalid,
      );
      expect(
        () => _feedback.customBeep(
          duration: const Duration(milliseconds: 100),
          frequencyHz: 5201,
        ),
        invalid,
      );
    });

    test('setName is printable ASCII, 1–20 characters', () {
      expect(() => _system.setName(''), invalid);
      expect(() => _system.setName('A' * 21), invalid);
      expect(() => _system.setName('Escáner'), invalid);
      expect(() => _system.setName('Tab\there'), invalid);
      expect(_system.setName('A' * 20).ascii, 'AT+NAME=${'A' * 20}');
    });

    test('prefix rejects empty and non-ASCII text', () {
      expect(() => _format.prefix(''), invalid);
      expect(() => _format.prefix('Ñ'), invalid);
    });

    test('hide counts are 0–255', () {
      expect(() => _format.hideTail(256), invalid);
      expect(() => _format.hideMiddle(-1, 1), invalid);
    });

    test('setDecodeEngine is 0–5', () {
      expect(() => _dangerous.setDecodeEngine(6), invalid);
    });

    test('custom commands must be ASCII', () {
      expect(() => NetumCommand.custom(''), invalid);
      expect(() => NetumCommand.custom('%Ñ#'), invalid);
      expect(NetumCommand.custom('%BAT_VOL#').kind, CommandKind.unknown);
    });
  });

  test('commands compare by value', () {
    expect(_feedback.beep(10), _feedback.beep(10));
    expect(_feedback.beep(10), isNot(_feedback.beep(11)));
  });
}
