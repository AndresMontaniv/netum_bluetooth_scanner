import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/commands/reply_parsers.dart';

void main() {
  // Replies as captured on the DS5000, after decoding.
  test('battery', () {
    expect(
      parseBattery('BAT_VOL=3.81V 37%'),
      const BatteryInfo(voltage: 3.81, percent: 37, raw: 'BAT_VOL=3.81V 37%'),
    );
    expect(parseBattery('BAT_VOL=3.76V 30%')?.percent, 30);
    expect(parseBattery('7771609001660'), isNull);
  });

  test('stored count', () {
    expect(parseStoredCount('Total Counters=0'), 0);
    expect(parseStoredCount('Total Counters=125'), 125);
    expect(parseStoredCount('Total Counters='), isNull);
  });

  test('sleep timeout', () {
    expect(parseSleepTimeout('Sleeptime=30min'), const Duration(minutes: 30));
    expect(parseSleepTimeout('Sleeptime=2h'), const Duration(hours: 2));
    expect(parseSleepTimeout('Sleeptime=never'), isNull);
  });

  test('Bluetooth name', () {
    expect(
      parseBluetoothName('+NAME=DS barcode scanner'),
      'DS barcode scanner',
    );
    expect(parseBluetoothName('+NAME=Netum-01'), 'Netum-01');
    expect(parseBluetoothName('NAME=x'), isNull);
  });

  test('Bluetooth address', () {
    expect(parseBluetoothAddress('+ADDR=DC0D3060B42C'), 'DC:0D:30:60:B4:2C');
    expect(parseBluetoothAddress('+ADDR=DC0D3060B4'), isNull);
  });

  test('Bluetooth firmware (after the NUL byte is stripped)', () {
    expect(parseBluetoothFirmware('+VER=1.6.2'), '1.6.2');
    expect(parseBluetoothFirmware('1.6.2'), isNull);
  });
}
