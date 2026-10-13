import 'package:meta/meta.dart';
import 'package:netum_bluetooth_scanner/src/commands/command_options.dart';
import 'package:netum_bluetooth_scanner/src/errors.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

/// How the scanner answers a command.
enum CommandKind {
  /// A setting or one-shot action, answered by an ACK or an echo.
  action,

  /// A query, answered by a text reply.
  query,

  /// Not known in advance (custom and raw commands): the first ACK, echo,
  /// or reply that arrives promptly answers it.
  unknown,
}

/// An over-the-air command for a NETUM scanner.
///
/// The catalog is grouped: [system], [workMode], [power], [feedback], [scan],
/// [format], [keyboard] and [dangerous]. Builders validate their arguments
/// and throw [NetumInvalidArgument]. Use [NetumCommand.custom] for anything
/// not covered.
///
/// See `doc/commands.md` for the full command reference and what was
/// verified on hardware.
@immutable
final class NetumCommand {
  const NetumCommand._(
    this.ascii,
    this.description, {
    this.kind = CommandKind.action,
    this.replyPrefix,
    this.expectsDisconnect = false,
    this.experimental = false,
  });

  /// A command not in the catalog.
  ///
  /// [ascii] must be 1–251 ASCII characters. With the default
  /// [CommandKind.unknown], the first ACK, echo or prompt reply answers it.
  factory NetumCommand.custom(
    String ascii, {
    CommandKind kind = CommandKind.unknown,
    String? replyPrefix,
    bool expectsDisconnect = false,
    String description = 'Custom command',
  }) {
    _checkAscii(ascii, 'ascii', maxLength: maxPayloadLength);
    return NetumCommand._(
      ascii,
      description,
      kind: kind,
      replyPrefix: replyPrefix,
      expectsDisconnect: expectsDisconnect,
    );
  }

  /// The command text sent to the scanner.
  final String ascii;

  /// A short description.
  final String description;

  /// How the scanner answers it.
  final CommandKind kind;

  /// The prefix of the reply, for queries whose reply has one (for example
  /// `BAT_VOL=`). Queries without a prefix are matched by timing only.
  final String? replyPrefix;

  /// Whether the scanner drops the link right after accepting it (rename,
  /// power off, mode switch). The link drop then counts as success.
  final bool expectsDisconnect;

  /// Whether the encoding is unverified on hardware.
  final bool experimental;

  /// Firmware, identity and Bluetooth-module commands.
  static const system = SystemCommands._();

  /// Normal vs. inventory (store-and-upload) mode.
  static const workMode = WorkModeCommands._();

  /// Battery, sleep and power.
  static const power = PowerCommands._();

  /// Beeper, vibration and acknowledgement feedback.
  static const feedback = FeedbackCommands._();

  /// Triggering and scan behaviour.
  static const scan = ScanCommands._();

  /// Prefix, suffix, hidden characters and terminator.
  static const format = FormatCommands._();

  /// Settings that only matter in keyboard (HID) or wired mode.
  static const keyboard = KeyboardCommands._();

  /// ⚠️ Commands that reset the scanner, change its transport or break the
  /// current connection. Read each warning before use.
  static const dangerous = DangerousCommands._();

  @override
  bool operator ==(Object other) =>
      other is NetumCommand &&
      other.ascii == ascii &&
      other.kind == kind &&
      other.replyPrefix == replyPrefix &&
      other.expectsDisconnect == expectsDisconnect;

  @override
  int get hashCode => Object.hash(ascii, kind, replyPrefix, expectsDisconnect);

  @override
  String toString() => 'NetumCommand($ascii)';
}

/// Firmware, identity and Bluetooth-module commands.
final class SystemCommands {
  const SystemCommands._();

  /// Reads the scanner firmware version, e.g. `bn0HDS_RFSBTD43bc_CB071`.
  /// The reply has no prefix.
  NetumCommand get firmwareVersion => const NetumCommand._(
    r'$SW#VER',
    'Read firmware version',
    kind: CommandKind.query,
  );

  /// Reads the current interface setting. Reply format unverified.
  NetumCommand get interfaceSetting => const NetumCommand._(
    r'%#IFSNO$',
    'Read interface setting',
    kind: CommandKind.query,
  );

  /// Reads the decode-engine model, e.g. `SE4750`. The reply has no prefix.
  NetumCommand get decodeEngine => const NetumCommand._(
    '%MODULESN#',
    'Read decode-engine model',
    kind: CommandKind.query,
  );

  /// Reads the Bluetooth name: `+NAME=<name>`.
  NetumCommand get bluetoothName => const NetumCommand._(
    'AT+NAME',
    'Read Bluetooth name',
    kind: CommandKind.query,
    replyPrefix: '+NAME=',
  );

  /// Reads the Classic Bluetooth MAC: `+ADDR=DC0D3060B42C`. This address is
  /// the same in BLE and SPP mode, so it identifies the scanner across
  /// transports (the BLE address differs in its first byte).
  NetumCommand get bluetoothAddress => const NetumCommand._(
    'AT+ADDR',
    'Read Classic Bluetooth address',
    kind: CommandKind.query,
    replyPrefix: '+ADDR=',
  );

  /// Reads the Bluetooth-module firmware: `+VER=1.6.2`.
  NetumCommand get bluetoothFirmware => const NetumCommand._(
    'AT+VER',
    'Read Bluetooth-module firmware',
    kind: CommandKind.query,
    replyPrefix: '+VER=',
  );

  /// Renames the scanner (printable ASCII, 1–20 characters).
  ///
  /// The scanner drops the link at once, restarts Bluetooth and advertises
  /// the new name. The name persists and applies to BLE and SPP.
  NetumCommand setName(String name) {
    _checkAscii(name, 'name', maxLength: 20, printable: true);
    return NetumCommand._(
      'AT+NAME=$name',
      'Rename to $name',
      expectsDisconnect: true,
    );
  }

  /// Disconnects, keeping the pairing.
  NetumCommand get disconnect => const NetumCommand._(
    'AT+DISC',
    'Disconnect (keep pairing)',
    expectsDisconnect: true,
  );

  /// Turns the timestamp on scan output on or off. Experimental: no
  /// timestamp was seen on live scans; it may apply to stored scans only.
  NetumCommand timestamp({required bool enabled}) => NetumCommand._(
    '%RTCSTAMP#${enabled ? 1 : 0}',
    'Timestamp ${enabled ? 'on' : 'off'}',
    experimental: true,
  );

  /// Sets the scanner clock to [time]'s local wall-clock time. Experimental.
  NetumCommand setClock(DateTime time) {
    final local = time.toLocal();
    final wallClock = DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
    final seconds = wallClock.millisecondsSinceEpoch ~/ 1000;
    if (seconds < 1000000000 || seconds > 9999999999) {
      throw NetumInvalidArgument('time out of range: $time');
    }
    return NetumCommand._(
      '%RTCSTAMP#$seconds',
      'Set clock',
      experimental: true,
    );
  }
}

/// Normal vs. inventory (store-and-upload) mode.
final class WorkModeCommands {
  const WorkModeCommands._();

  /// Sends each scan immediately (default).
  NetumCommand get normal =>
      const NetumCommand._('%#NORMD', 'Normal mode: send scans immediately');

  /// Keeps scans in the scanner's memory until uploaded.
  NetumCommand get inventory =>
      const NetumCommand._('%#INVMD', 'Inventory mode: store scans');

  /// Uploads the stored scans; they arrive as regular scans.
  NetumCommand get upload =>
      const NetumCommand._('%#TXMEM', 'Upload stored scans');

  /// Uploads the stored scans, then clears them.
  NetumCommand get uploadAndClear =>
      const NetumCommand._('%#TXMEM#C', 'Upload and clear stored scans');

  /// Reads the number of stored scans: `Total Counters=0`.
  NetumCommand get storedCount => const NetumCommand._(
    '%#+TCNT',
    'Read stored scan count',
    kind: CommandKind.query,
    replyPrefix: 'Total Counters=',
  );

  /// Reads the stored count and memory usage. Reply format unverified.
  NetumCommand get storedCountAndUsage => const NetumCommand._(
    '%#+TCNT#',
    'Read stored count and memory usage',
    kind: CommandKind.query,
  );

  /// Deletes the stored scans.
  NetumCommand get clearStored =>
      const NetumCommand._('%#*NEW*', 'Clear stored scans');

  /// Sets [mode]: `%#NORMD` or `%#INVMD`.
  NetumCommand mode(WorkMode mode) =>
      mode == WorkMode.normal ? normal : inventory;

  /// Stores scans automatically while out of range.
  NetumCommand autoSave({required bool enabled}) => NetumCommand._(
    '%AutoSav#${enabled ? 'On' : 'Off'}',
    'Auto-save when out of range ${enabled ? 'on' : 'off'}',
  );
}

/// Battery, sleep and power.
final class PowerCommands {
  const PowerCommands._();

  /// Reads the battery: `BAT_VOL=3.81V 37%`.
  NetumCommand get battery => const NetumCommand._(
    '%BAT_VOL#',
    'Read battery',
    kind: CommandKind.query,
    replyPrefix: 'BAT_VOL=',
  );

  /// Reads the sleep timeout: `Sleeptime=30min`.
  NetumCommand get sleepTimeout => const NetumCommand._(
    r'$RF#ST',
    'Read sleep timeout',
    kind: CommandKind.query,
    replyPrefix: 'Sleeptime=',
  );

  /// Sets the idle time before the scanner sleeps.
  NetumCommand setSleepTimeout(SleepTimeout timeout) => NetumCommand._(
    '\$RF#ST${timeout.code}',
    'Sleep after ${timeout.name}',
  );

  /// Turns the scanner off. The link drops.
  NetumCommand get powerOff => const NetumCommand._(
    r'$POWER#OFF',
    'Power off',
    expectsDisconnect: true,
  );
}

/// Beeper, vibration and acknowledgement feedback.
final class FeedbackCommands {
  const FeedbackCommands._();

  /// Sets the beeper volume.
  NetumCommand volume(BeepVolume volume) =>
      NetumCommand._('\$BUZZ#${volume.code}', 'Beep volume ${volume.name}');

  /// Sets the beeper tone.
  NetumCommand tone(BeepTone tone) =>
      NetumCommand._('\$BUZZ#${tone.code}', 'Beep tone ${tone.name}');

  /// Turns vibration on or off.
  NetumCommand vibration({required bool enabled}) => NetumCommand._(
    '\$MOTO#${enabled ? 1 : 0}',
    'Vibration ${enabled ? 'on' : 'off'}',
  );

  /// Whether framed commands are confirmed with a beep and vibration. With
  /// `false`, framed commands are silent but still acknowledged. Raw
  /// commands always beep.
  NetumCommand ackBeep({required bool enabled}) => NetumCommand._(
    '%ACKBEEP#${enabled ? 1 : 0}',
    'Command beep ${enabled ? 'on' : 'off'}',
  );

  /// Toggles the beep when the scanner connects to its base or cradle.
  NetumCommand get baseConnectBeepToggle =>
      const NetumCommand._('%ACKBEEP#2', 'Toggle base-connect beep');

  /// Plays preset melody [level] (0–26), e.g. 0 is a short beep and 26 a
  /// trill.
  NetumCommand beep(int level) {
    _checkRange(level, 'level', 0, 26);
    return NetumCommand._(
      '\$BUZZ#B${String.fromCharCode(0x30 + level)}',
      'Beep preset $level',
    );
  }

  /// Plays a custom beep. Experimental: the duration and frequency encoding
  /// is unverified, and the DS5000 ignores [type].
  ///
  /// [duration] is 10–2540 ms and [frequencyHz] is 100–5200.
  NetumCommand customBeep({
    required Duration duration,
    required int frequencyHz,
    BeepType type = BeepType.beepAndVibrate,
  }) {
    final ms = duration.inMilliseconds;
    _checkRange(ms, 'duration (ms)', 10, 2540);
    _checkRange(frequencyHz, 'frequencyHz', 100, 5200);
    final time = _hex2((ms + 10) ~/ 10);
    final frequency = _hex2((frequencyHz - 100) ~/ 20);
    return NetumCommand._(
      '\$BUZZ#BK$time${type.code}$frequency',
      'Custom beep ${ms}ms ${frequencyHz}Hz',
      experimental: true,
    );
  }
}

/// Triggering and scan behaviour.
final class ScanCommands {
  const ScanCommands._();

  /// Turns the scan engine on for [seconds] (1–7), as if the trigger were
  /// pressed.
  NetumCommand trigger(int seconds) {
    _checkRange(seconds, 'seconds', 1, 7);
    return NetumCommand._('%SCANTM#$seconds#', 'Scan for ${seconds}s');
  }

  /// Sets how scans are triggered.
  NetumCommand mode(ScanMode mode) =>
      NetumCommand._(mode.ascii, 'Scan mode ${mode.name}');

  /// Sets how long the scanner tries to decode.
  NetumCommand decodeTimeout(DecodeTimeout timeout) =>
      NetumCommand._(timeout.ascii, 'Decode timeout ${timeout.name}');

  /// Sets the minimum time between scans.
  NetumCommand interval(ScanInterval interval) =>
      NetumCommand._(interval.ascii, 'Scan interval ${interval.name}');
}

/// Prefix, suffix, hidden characters and terminator.
///
/// The hide commands are labelled differently in the vendor's Android SDK
/// and iOS demo; these names follow the Android SDK. Unverified.
final class FormatCommands {
  const FormatCommands._();

  /// Clears all prefix, suffix and hide formatting.
  NetumCommand get clear =>
      const NetumCommand._(r'$DATA#0', 'Clear prefix/suffix/hide formatting');

  /// Enables suffix output.
  NetumCommand get enableSuffix =>
      const NetumCommand._(r'$DATA#1', 'Enable suffix output');

  /// Enables prefix output.
  NetumCommand get enablePrefix =>
      const NetumCommand._(r'$DATA#2', 'Enable prefix output');

  /// Enables hiding characters at the end.
  NetumCommand get enableHideTail =>
      const NetumCommand._(r'$DATA#3', 'Enable hide tail');

  /// Enables hiding characters in the middle.
  NetumCommand get enableHideMiddle =>
      const NetumCommand._(r'$DATA#4', 'Enable hide middle');

  /// Enables hiding characters at the start.
  NetumCommand get enableHideHead =>
      const NetumCommand._(r'$DATA#5', 'Enable hide head');

  /// Sets the prefix [text] (ASCII, control characters allowed).
  /// Experimental.
  NetumCommand prefix(String text) => _text('2', text, 'Set prefix');

  /// Sets the suffix [text] (ASCII, control characters allowed, e.g.
  /// `'abcd\x03'`). Experimental.
  NetumCommand suffix(String text) => _text('1', text, 'Set suffix');

  /// Hides [count] characters at the end (0–255). Experimental.
  NetumCommand hideTail(int count) {
    _checkRange(count, 'count', 0, 255);
    return NetumCommand._(
      '\$DATA#30${_hex2(count, upper: true)}#',
      'Hide $count at tail',
      experimental: true,
    );
  }

  /// Hides [count] characters starting at [start] (each 0–255).
  /// Experimental.
  NetumCommand hideMiddle(int start, int count) {
    _checkRange(start, 'start', 0, 255);
    _checkRange(count, 'count', 0, 255);
    return NetumCommand._(
      '\$DATA#40${_hex2(start, upper: true)}${_hex2(count, upper: true)}#',
      'Hide $count from $start',
      experimental: true,
    );
  }

  /// Hides [count] characters at the start (0–255). Experimental.
  NetumCommand hideHead(int count) {
    _checkRange(count, 'count', 0, 255);
    return NetumCommand._(
      '\$DATA#50${_hex2(count, upper: true)}#',
      'Hide $count at head',
      experimental: true,
    );
  }

  /// Sets the extra characters appended after every barcode. On the DS5000
  /// scans already end in CR at the factory value [Terminator.none].
  NetumCommand terminator(Terminator terminator) => NetumCommand._(
    '\$TERM#${terminator.code}',
    'Terminator ${terminator.name}',
  );

  NetumCommand _text(String slot, String text, String description) {
    // `$DATA#<slot>0<len><text>#`: 9 characters around the text.
    _checkAscii(text, 'text', maxLength: maxPayloadLength - 9);
    return NetumCommand._(
      '\$DATA#${slot}0${_hex2(text.length, upper: true)}$text#',
      '$description "$text"',
      experimental: true,
    );
  }
}

/// Settings that only matter in keyboard (HID) mode, or over USB / 2.4G.
final class KeyboardCommands {
  const KeyboardCommands._();

  /// Shows or hides the iOS on-screen keyboard.
  NetumCommand get toggleOnScreenKeyboard =>
      const NetumCommand._('%%0S', 'Toggle iOS on-screen keyboard');

  /// Toggles "hold the trigger 3 s to toggle the iOS keyboard".
  NetumCommand get holdTriggerTogglesKeyboard => const NetumCommand._(
    '%%0H3',
    'Toggle: hold trigger 3 s toggles iOS keyboard',
  );

  /// Toggles "double-click the trigger to toggle the iOS keyboard".
  NetumCommand get doubleClickTogglesKeyboard => const NetumCommand._(
    '%%0HH',
    'Toggle: double-click toggles iOS keyboard',
  );

  /// Toggles ignoring Caps Lock (Windows).
  NetumCommand get capsLockIgnoreToggle =>
      const NetumCommand._('%%0HL', 'Toggle Caps Lock ignore');

  /// Toggles "hold the trigger 8 s to switch between Bluetooth and 2.4G".
  NetumCommand get holdTriggerSwitchesRadio => const NetumCommand._(
    '%%0H8',
    'Toggle: hold trigger 8 s switches Bluetooth / 2.4G',
  );

  /// Sends characters below 0x20 as Ctrl key combinations.
  NetumCommand controlCombos({required bool enabled}) => NetumCommand._(
    '\$KEY#M${enabled ? 1 : 0}',
    'Ctrl combos ${enabled ? 'on' : 'off'}',
  );

  /// Sets letter case and number-key output.
  NetumCommand caseMode(CaseMode mode) =>
      NetumCommand._('%LKLED#${mode.code}', 'Case mode ${mode.name}');

  /// Reads the output character set. Reply format unverified.
  NetumCommand get charset => const NetumCommand._(
    '%CHARSET#',
    'Read character set',
    kind: CommandKind.query,
  );

  /// Sets the output character set.
  NetumCommand setCharset(Charset charset) => NetumCommand._(
    '%CHARSET#${charset.code}',
    'Character set ${charset.name}',
  );

  /// Reads the host OS setting. Reply format unverified.
  NetumCommand get hostOs => const NetumCommand._(
    r'$KB#OS',
    'Read host OS',
    kind: CommandKind.query,
  );

  /// Sets the host OS.
  NetumCommand setHostOs(HostOs os) =>
      NetumCommand._('\$KB#OS${os.code}', 'Host OS ${os.name}');

  /// Reads the keyboard layout. Reply format unverified.
  NetumCommand get language => const NetumCommand._(
    r'$LAN#',
    'Read keyboard layout',
    kind: CommandKind.query,
  );

  /// Sets the keyboard layout.
  NetumCommand setLanguage(KeyboardLanguage language) => NetumCommand._(
    '\$LAN#${language.code}',
    'Keyboard layout ${language.name}',
  );

  /// Reads the delay between typed keys. Reply format unverified.
  NetumCommand get hidKeyDelay => const NetumCommand._(
    'AT+HIDDLY',
    'Read HID key delay',
    kind: CommandKind.query,
  );

  /// Sets the delay between typed keys.
  NetumCommand setHidKeyDelay(HidKeyDelay delay) =>
      NetumCommand._('AT+HIDDLY=${delay.code}', 'HID key delay ${delay.name}');

  /// Chooses automatically between wired and wireless output (USB / 2.4G).
  NetumCommand autoWiredWireless({required bool enabled}) => NetumCommand._(
    enabled ? '%000604' : '%000605',
    'Auto wired/wireless ${enabled ? 'on' : 'off'}',
  );

  /// Sets the key latency over USB or 2.4G.
  NetumCommand wiredLatency(WiredLatency latency) =>
      NetumCommand._(latency.ascii, 'Wired latency ${latency.name}');
}

/// ⚠️ Commands that reset the scanner, change its transport or break the
/// current connection.
final class DangerousCommands {
  const DangerousCommands._();

  /// ⚠️ Restores the scanner's factory settings (beeper, scan mode, formats,
  /// terminator…). Apps relying on a terminator must set it again.
  NetumCommand get factoryReset =>
      const NetumCommand._(r'%#IFSNO$B', 'Factory reset (scanner settings)');

  /// ⚠️ Switches the scanner's output to Bluetooth (needed before
  /// [mode]).
  NetumCommand get bluetoothOutput =>
      const NetumCommand._(r'%#IFSNO$4', 'Bluetooth output');

  /// ⚠️ Switches the Bluetooth mode. The link drops, and the scanner must
  /// then be found again in the new mode (SPP needs pairing; HID pairs as a
  /// keyboard and stops talking to this plugin).
  NetumCommand mode(NetumMode mode) => NetumCommand._(
    'AT+MODE=${mode.code}',
    'Switch to ${mode.name.toUpperCase()} mode',
    expectsDisconnect: true,
  );

  /// ⚠️ Reboots the Bluetooth module. The link drops.
  NetumCommand get moduleReboot => const NetumCommand._(
    'AT+REBOOT',
    'Reboot Bluetooth module',
    expectsDisconnect: true,
  );

  /// ⚠️ Factory-resets the Bluetooth module (name, mode…). The link drops.
  NetumCommand get moduleFactoryReset => const NetumCommand._(
    'AT+RESTORE',
    'Factory reset Bluetooth module',
    expectsDisconnect: true,
  );

  /// ⚠️ Disconnects and clears all pairing records. Phones must pair again.
  NetumCommand get clearPairing => const NetumCommand._(
    '%%ALL-CH',
    'Disconnect and clear pairing',
    expectsDisconnect: true,
  );

  /// ⚠️ Switches the output to USB keyboard. Bluetooth stops.
  NetumCommand get usbKeyboard =>
      const NetumCommand._(r'%#IFSNO$2', 'USB keyboard output');

  /// ⚠️ Switches the output to USB virtual COM port. Bluetooth stops.
  NetumCommand get usbVirtualCom =>
      const NetumCommand._(r'%#IFSNO$3', 'USB virtual COM output');

  /// ⚠️ Turns wired multi-key HID on or off.
  NetumCommand wiredMultiKey({required bool enabled}) => NetumCommand._(
    enabled ? r'%#IFSNO$6' : r'%#IFSNO$7',
    'Wired multi-key ${enabled ? 'on' : 'off'}',
  );

  /// ⚠️ Changes which decode engine the firmware drives (factory setting,
  /// 0–5). A wrong value can stop the scanner from reading barcodes.
  NetumCommand setDecodeEngine(int type) {
    _checkRange(type, 'type', 0, 5);
    return NetumCommand._('%MODULESN#$type#', 'Set decode engine $type');
  }
}

/// Two hex digits. Lowercase by default: the vendor SDK sends lowercase for
/// the custom beep, and that form is verified on hardware.
String _hex2(int value, {bool upper = false}) {
  final hex = value.toRadixString(16).padLeft(2, '0');
  return upper ? hex.toUpperCase() : hex;
}

void _checkRange(int value, String name, int min, int max) {
  if (value < min || value > max) {
    throw NetumInvalidArgument('$name must be $min–$max, got $value');
  }
}

void _checkAscii(
  String value,
  String name, {
  required int maxLength,
  bool printable = false,
}) {
  if (value.isEmpty || value.length > maxLength) {
    throw NetumInvalidArgument('$name must be 1–$maxLength characters');
  }
  final (min, max) = printable ? (0x20, 0x7E) : (0x01, 0x7F);
  if (value.codeUnits.any((unit) => unit < min || unit > max)) {
    throw NetumInvalidArgument(
      '$name must be ${printable ? 'printable ' : ''}ASCII: "$value"',
    );
  }
}
