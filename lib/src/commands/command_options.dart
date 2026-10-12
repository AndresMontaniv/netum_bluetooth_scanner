/// The scanner's Bluetooth output mode.
enum NetumMode {
  /// Serial Port Profile (Classic Bluetooth). Android only.
  spp('1'),

  /// Keyboard (HID) mode: barcodes are typed into the focused field.
  hid('2'),

  /// Bluetooth Low Energy.
  ble('3');

  const NetumMode(this.code);

  /// The digit sent in `AT+MODE=<code>`.
  final String code;
}

/// Beeper volume.
enum BeepVolume {
  /// No beep.
  mute('0'),

  /// Loud.
  high('1'),

  /// Medium.
  medium('2'),

  /// Quiet.
  low('3');

  const BeepVolume(this.code);

  /// The digit sent in `$BUZZ#<code>`.
  final String code;
}

/// Beeper tone.
enum BeepTone {
  /// High pitch.
  high('4'),

  /// Low pitch.
  low('5');

  const BeepTone(this.code);

  /// The digit sent in `$BUZZ#<code>`.
  final String code;
}

/// What a custom beep does. On the DS5000 this is ignored: vibration
/// follows the global vibration setting.
enum BeepType {
  /// Beep and vibrate.
  beepAndVibrate('0'),

  /// Beep only.
  beepOnly('1'),

  /// Vibrate only.
  vibrateOnly('2');

  const BeepType(this.code);

  /// The digit sent in the custom-beep command.
  final String code;
}

/// How scans are triggered.
enum ScanMode {
  /// Scan while the trigger key is pressed (default).
  trigger('%SCMD#00#'),

  /// Scan continuously.
  continuous('%SCMD#01#'),

  /// A trigger press starts a scan that runs until a read or timeout.
  pulse('%SCMD#02#'),

  /// Only the app triggers scans (see `NetumCommand.scan.trigger`).
  hostTrigger('%SCMD#03#');

  const ScanMode(this.ascii);

  /// The command text.
  final String ascii;
}

/// How long the scanner tries to decode before giving up.
enum DecodeTimeout {
  /// 3 seconds.
  seconds3('%SCMD#3000D'),

  /// 6 seconds.
  seconds6('%SCMD#6000D');

  const DecodeTimeout(this.ascii);

  /// The command text.
  final String ascii;
}

/// Minimum time between two scans.
enum ScanInterval {
  /// 0.5 seconds.
  milliseconds500('%SCMD#0500I'),

  /// 1 second.
  seconds1('%SCMD#1000I');

  const ScanInterval(this.ascii);

  /// The command text.
  final String ascii;
}

/// Idle time before the scanner sleeps.
enum SleepTimeout {
  /// Never sleep.
  never('00'),

  /// 1 minute.
  minutes1('02'),

  /// 3 minutes.
  minutes3('06'),

  /// 5 minutes.
  minutes5('10'),

  /// 10 minutes.
  minutes10('20'),

  /// 30 minutes.
  minutes30('60'),

  /// 1 hour.
  hours1('<0'),

  /// 2 hours.
  hours2('H0');

  const SleepTimeout(this.code);

  /// The two characters sent in `$RF#ST<code>` (units of 30 s, encoded as
  /// `'0' + tens`, `'0' + ones`).
  final String code;
}

/// Characters appended after every barcode.
enum Terminator {
  /// Nothing. Payloads are then delimited by an idle timeout only.
  none('0'),

  /// Carriage return (factory default).
  cr('1'),

  /// Tab.
  tab('2'),

  /// Carriage return + line feed.
  crlf('3'),

  /// Line feed.
  lf('4');

  const Terminator(this.code);

  /// The digit sent in `$TERM#<code>`.
  final String code;
}

/// Letter case and number output in keyboard (HID) mode.
enum CaseMode {
  /// Letters as scanned.
  normal('0'),

  /// Upper and lower case swapped.
  inverted('1'),

  /// All upper case.
  upper('2'),

  /// All lower case.
  lower('3'),

  /// Digits sent as regular keys.
  noNumpad('4'),

  /// Digits sent as numeric-keypad keys.
  numpad('5');

  const CaseMode(this.code);

  /// The digit sent in `%LKLED#<code>`.
  final String code;
}

/// Output character set in keyboard (HID) mode. May also affect BLE/SPP
/// payloads (unverified).
enum Charset {
  /// Automatic.
  auto('0'),

  /// ANSI.
  ansi('1'),

  /// UTF-8 for Word-like targets.
  utf8Word('2'),

  /// UTF-8 for plain-text targets.
  utf8Text('21'),

  /// ISO-8859.
  iso8859('3'),

  /// Normal.
  normal('4');

  const Charset(this.code);

  /// The code sent in `%CHARSET#<code>`.
  final String code;
}

/// The host operating system in keyboard (HID) mode.
enum HostOs {
  /// Windows.
  windows('0'),

  /// macOS / iOS.
  apple('1'),

  /// Android.
  android('2');

  const HostOs(this.code);

  /// The digit sent in `$KB#OS<code>`.
  final String code;
}

/// Keyboard layout in keyboard (HID) mode.
enum KeyboardLanguage {
  /// English (US).
  englishUs('EN'),

  /// French.
  french('FR'),

  /// German.
  german('GE'),

  /// Turkish Q.
  turkishQ('TK'),

  /// Turkish F.
  turkishF('TF'),

  /// Portuguese.
  portuguese('PT'),

  /// Spanish.
  spanish('ES'),

  /// Czech.
  czech('CS'),

  /// Italian.
  italian('IT'),

  /// Belgian French.
  belgianFrench('FB'),

  /// Brazilian Portuguese.
  brazilianPortuguese('PB'),

  /// Canadian French.
  canadianFrench('FC'),

  /// Croatian.
  croatian('HR'),

  /// Slovak.
  slovak('SK'),

  /// Danish.
  danish('DA'),

  /// Finnish.
  finnish('FI'),

  /// Hungarian.
  hungarian('HU'),

  /// Latin-American Spanish (code `EL`, not Greek).
  latinAmericanSpanish('EL'),

  /// Dutch.
  dutch('NL'),

  /// Norwegian.
  norwegian('NO'),

  /// Polish.
  polish('PL'),

  /// Serbian.
  serbian('SR'),

  /// Slovenian.
  slovenian('SL'),

  /// Swedish.
  swedish('SV'),

  /// Swiss German.
  swissGerman('DS'),

  /// English (UK).
  englishUk('UK'),

  /// Japanese.
  japanese('JP'),

  /// Thai.
  thai('TH'),

  /// Generic ALT-code entry.
  altGeneric('AG'),

  /// Single-byte ALT-code entry.
  altSingleByte('RU');

  const KeyboardLanguage(this.code);

  /// The two letters sent in `$LAN#<code>`.
  final String code;
}

/// Delay between typed keys in keyboard (HID) mode.
enum HidKeyDelay {
  /// Short delay.
  low('2'),

  /// Medium delay.
  medium('10'),

  /// Long delay.
  high('30');

  const HidKeyDelay(this.code);

  /// The value sent in `AT+HIDDLY=<code>`.
  final String code;
}

/// Key latency over USB or 2.4G.
enum WiredLatency {
  /// Low.
  low('%KB#SP0'),

  /// Medium.
  medium('%KB#SP7'),

  /// High.
  high('%KB#SP?');

  const WiredLatency(this.ascii);

  /// The command text.
  final String ascii;
}
