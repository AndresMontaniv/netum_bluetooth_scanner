import 'package:meta/meta.dart';

/// The scanner's battery state, parsed from a `BAT_VOL=3.81V 37%` reply.
@immutable
class BatteryInfo {
  /// Creates a battery reading.
  const BatteryInfo({
    required this.voltage,
    required this.percent,
    required this.raw,
  });

  /// Battery voltage in volts.
  final double voltage;

  /// Charge level, 0–100.
  final int percent;

  /// The reply text as received.
  final String raw;

  @override
  bool operator ==(Object other) =>
      other is BatteryInfo &&
      other.voltage == voltage &&
      other.percent == percent &&
      other.raw == raw;

  @override
  int get hashCode => Object.hash(voltage, percent, raw);

  @override
  String toString() => 'BatteryInfo(${voltage}V, $percent%)';
}
