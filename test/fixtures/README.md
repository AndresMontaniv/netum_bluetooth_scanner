# Packet fixtures

`packets.json` holds real DS5000 traffic captured on 2026-10-07/08 (Android BLE and SPP, iOS BLE).
Only packet bytes, direction, relative timing and the pending command are kept.

- `kind` (inbound only) is labelled by content: `ack`, `echo`, `reply`, `barcode`.
- `pending` is the command still awaiting a response when the packet arrived (cleared once answered,
  or after 1.5 s).
- `tMs` / `sinceWriteMs` are `null` for the iOS session, whose log has no timestamps.

Load them with `test/helpers/fixtures.dart`.
