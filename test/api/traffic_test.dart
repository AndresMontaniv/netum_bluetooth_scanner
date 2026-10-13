import 'package:flutter_test/flutter_test.dart';
import 'package:netum_bluetooth_scanner/netum_bluetooth_scanner.dart';
import 'package:netum_bluetooth_scanner/src/protocol/frame.dart';

import '../helpers/fake_transport.dart';

const _id = 'DD:0D:30:60:B4:2C';

void main() {
  late FakeTransport transport;
  late NetumScanner netum;
  late NetumDevice device;
  late List<TrafficEvent> traffic;

  setUp(() async {
    transport = FakeTransport();
    netum = NetumScanner.withTransport(transport);
    traffic = [];
    netum.traffic.listen(traffic.add);
    device = await netum.connect(_id, transport: NetumTransport.ble);
    await pumpEventQueue();
  });

  tearDown(() => netum.dispose());

  test('nothing is reported while trafficLogEnabled is off', () async {
    transport.receive(_id, '7771609001660\r'.codeUnits);
    await pumpEventQueue();

    expect(traffic, isEmpty);
  });

  test('every packet is reported and classified', () async {
    netum.trafficLogEnabled = true;

    final trigger = device.triggerScan(seconds: 3);
    await pumpEventQueue();
    transport.receive(_id, [0x0E, 0x0B]);
    await trigger;
    final battery = device.getBattery();
    await pumpEventQueue();
    transport
      ..receive(_id, 'BAT_VOL=3.81V 37%\r'.codeUnits)
      ..receive(_id, '7771609001660\r'.codeUnits)
      ..receive(_id, [0x0B, 0x0B]) // A stray ACK.
      ..receive(_id, encodeFrame(r'$BUZZ#BK650dc')); // A stray frame.
    await battery;
    await pumpEventQueue();

    expect(
      traffic.map((e) => (e.direction, e.kind, e.text)).toList(),
      [
        (TrafficDirection.outbound, PacketKind.command, '%SCANTM#3#'),
        (TrafficDirection.inbound, PacketKind.ack, null),
        (TrafficDirection.outbound, PacketKind.command, '%BAT_VOL#'),
        (TrafficDirection.inbound, PacketKind.reply, 'BAT_VOL=3.81V 37%'),
        (TrafficDirection.inbound, PacketKind.barcode, '7771609001660'),
        (TrafficDirection.inbound, PacketKind.ack, null),
        (TrafficDirection.inbound, PacketKind.unknown, null),
      ],
    );
    expect(traffic.first.bytes, encodeFrame('%SCANTM#3#'));
    expect(traffic.every((e) => e.device == device), isTrue);
  });
}
