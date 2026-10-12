# NETUM DS5000 wire protocol

> Derived from NETUM's Android SDK (v2.4.1) and iOS demo, then verified on DS5000 hardware (Android and iOS, October 2026). Items marked ✅ were observed on real devices; items tagged **[unverified – hardware]** have not been confirmed yet.
>
> This is the document that the Kotlin (Android) and Swift (iOS) implementations of the plugin both implement. It does not describe any SDK class — only bytes, UUIDs and flows.

---

## 1. Transports at a glance

| Mode | Scanner barcode | Phone side | Data channel | Platforms |
|---|---|---|---|---|
| HID | `AT+MODE=2` | OS keyboard pairing | Keystrokes into the focused text field | Android, iOS (no SDK needed) |
| **BLE** | `AT+MODE=3` | GATT central | Notify characteristic (in) / Write characteristic (out) | Android, iOS |
| **SPP** | `AT+MODE=1` | RFCOMM (classic BT) | Raw serial byte stream, both directions | Android only (iOS has no SPP for non-MFi devices) |

Before any of these, the scanner must be in Bluetooth output mode: scan `%#IFSNO$4`. The character after `IFSN` is the **letter O**, not zero.

The barcodes are printed in the *Quick Setup Guide* PDF.

---

## 2. BLE GATT layout

| Role | UUID (16-bit) | Full 128-bit |
|---|---|---|
| Service | `FFF0` | `0000FFF0-0000-1000-8000-00805F9B34FB` |
| Notify (scanner → phone) | `FFF1` | `0000FFF1-0000-1000-8000-00805F9B34FB` |
| Write (phone → scanner) | `FFF2` | `0000FFF2-0000-1000-8000-00805F9B34FB` |
| Alt. service (iOS only) | `FF00` | `0000FF00-…` |
| Alt. notify (iOS only) | `FF01` | `0000FF01-…` |
| Alt. write (iOS only) | `FF02` | `0000FF02-…` |

**Scan filter UUIDs.** These are advertised service UUIDs; Android filters on them and iOS does not filter at all:
- `BLEScanUUID1 = 0000FFF0-…`: "BT825" Bluetooth module. Default in the BLE demo.
- `BLEScanUUID2 = 000018F0-…`: "BT246" Bluetooth module. Default in the SPP demo's `ScanRuleConfig`, where it is irrelevant.

**Implication:** Netum ships at least two or three Bluetooth radio modules, so the plugin must not hardcode a single service. Discover services, then pick the first match in this order:
1. FFF0 / FFF1 / FFF2
2. FF00 / FF01 / FF02

✅ **Verified on DS5000 (2026-10-07, Android logcat).**

Advertising:
- Advertised name: `DS barcode scanner`.
- The advertisement carries the 16-bit service UUID `FFF0` (`03 02 F0 FF`) and an iBeacon-style manufacturer block (`4C 00 02 15 …`).

GATT table:

| Service | Characteristics |
|---|---|
| `1800` Generic Access | — |
| `1801` Generic Attribute | — |
| **`FFF0`** | **`FFF1`** props `0x10` (NOTIFY only); **`FFF2`** props `0x0C` (WRITE + WRITE_NO_RESPONSE, default write type = no-response) |
| **`180A` Device Information** | `2A24` model, `2A25` serial, `2A27` hardware rev, `2A28` software rev, `2A29` manufacturer (all READ) |

✅ **Device Information values (one test unit, read over BLE on Android and iOS):**

| Field | Value |
|---|---|
| manufacturer `2A29` | "Feasycom" |
| model `2A24` | "FSC-BT825" |
| serial `2A25` | "DC0D3060B42C" (= the Classic/SPP MAC, **not** the label serial N319D70013) |
| hardware `2A27` | "1.1" |
| software `2A28` | "1.6.2" (= `AT+VER`) |

So model, firmware and a stable cross-transport identity are readable with plain GATT reads, with no Netum command and on both platforms, including iOS where MACs are hidden. The three test units advertise byte-identical data except the MAC (flags `06`, iBeacon block with the module vendor's default UUID/major/minor, name "DS barcode scanner", service `FFF0`), and the MAC prefix `DC:0D:30` / `DD:0D:30` is the OUI of **Feasycom**, not Netum. Units can only be told apart before connecting by MAC (Android) or by a custom name (§6).

**Scan permission (✅):** do **not** declare `BLUETOOTH_SCAN` with `neverForLocation`. A build with the flag found **0 of 3** scanners on the A24 (normal build: 3/3), because Android filters beacon advertisements under that flag and the DS5000 advertises an iBeacon block. So location permission is required for discovery on all Android versions.

**Status 133 (✅):** on the Android 10 tablet the first `connectGatt` after app launch failed with status 133 in both sessions; an automatic retry ~5 s later succeeded, and later connects worked first time. No 133 on the A24 (connect ~1 s). The plugin should retry once on 133.

**Write type:**
- Android `BleConnector` does not set a write type, so it uses the characteristic's default.
- iOS uses `.withResponse`.
- Recommendation: `withResponse`. It is reliable, and it lets iOS do long writes when the payload is over 20 bytes.

**Notifications:** enable them by writing the CCCD on the notify characteristic. The Android SDK does this in `BleConnector.enableCharacteristicNotify`.

**MTU:**
- Neither SDK requests a larger MTU. Android has `setMtu` but the demo never calls it. So ATT_MTU = 23, which leaves **20 bytes of payload per packet**.
- iOS negotiates MTU automatically (usually 185+ on modern iPhones). ✅ Verified on an iPhone 16 Pro Max: ATT MTU 185 (182-byte payloads) once notifications are enabled, so long 1D barcodes arrive in one notification there too.
- ✅ **The DS5000 itself requests MTU 200 right after connecting** (A24 Bluetooth stack log: `gatts_process_mtu_req: MTU 200 request from remote … resulted MTU 200`). So every connection runs at MTU 200 (197-byte payloads) without the app asking. An app request (185) changes nothing; it stays 200. iOS also accepts peripheral-initiated MTU exchanges, which still needs confirming on the iPhone.

**Bonding:** not required for BLE. A plain `connectGatt(…, TRANSPORT_LE)` works.

---

## 3. Command frame (phone → scanner)

Every command is an ASCII string, such as `%BAT_VOL#`. The Android SDK always wraps it in a frame:

```
+------+---------+------+-------------------+-------+-------+------+
| 0x02 | n + 4   | 0x0A | ASCII payload (n) | ck_hi | ck_lo | 0x03 |
| STX  | LEN     | TYPE | e.g. "%BAT_VOL#"  | checksum (BE) | ETX  |
+------+---------+------+-------------------+-------+-------+------+
total frame length = n + 6 bytes
```

### 3.1 Checksum

Earlier docs call this a "CRC16", but it is not a CRC: there is no polynomial and no initial value. It is a **weighted sum, then 16-bit two's complement**:

```
// d = payload bytes, n = d.length
sum  = (n + 4) * (n + 2)          // LEN byte, weight n+2
     + 0x0A    * (n + 1)          // TYPE byte, weight n+1
     + Σ_{i=0..n-1} d[i] * (n - i)   // payload, weights n … 1
ck   = (0x10000 - (sum & 0xFFFF)) & 0xFFFF
frame = [0x02, n+4, 0x0A, d..., ck >> 8, ck & 0xFF, 0x03]
```

Notes:
- Java bytes are signed, so payload bytes ≥ 0x80 count as negative on Android. Commands are ASCII, so this only matters for non-ASCII prefix/suffix text.
- The Kotlin and Swift ports should accept **ASCII only** and reject anything else.

### 3.2 Test vectors

These were recomputed with an independent Python port. `%#INVMD` matches the byte array hardcoded in the iOS demo, which confirms the algorithm.

| Command | Frame (hex) | Bytes |
|---|---|---|
| `%#INVMD` | `02 0B 0A 25 23 49 4E 56 4D 44 F8 F3 03` | 13 |
| `%BAT_VOL#` | `02 0D 0A 25 42 41 54 5F 56 4F 4C 23 F3 16 03` | 15 |
| `$SW#VER` | `02 0B 0A 24 53 57 23 56 45 52 F8 42 03` | 13 |
| `%#+TCNT` | `02 0B 0A 25 23 2B 54 43 4E 54 F9 98 03` | 13 |
| `%SCANTM#1#` | `02 0E 0A 25 53 43 41 4E 54 4D 23 31 23 F1 14 03` | 16 |
| `%SCANTM#3#` | `02 0E 0A 25 53 43 41 4E 54 4D 23 33 23 F1 10 03` | 16 |
| `$BUZZ#B:` (beep level 10) | `02 0C 0A 24 42 55 5A 5A 23 42 3A F5 F1 03` | 14 |
| `%RTCSTAMP#1791400000` | `02 18 0A 25 52 54 43 53 54 41 4D 50 23 31 37 39 31 34 30 30 30 30 30 C7 F5 03` | **26 (> 20!)** |

The plugin's Dart frame encoder is unit-tested against these vectors.

### 3.3 Raw vs. framed — **[unverified – hardware]**

- The Android SDK always sends framed commands.
- The iOS demo's real send path (`sendCommandNew:`) sends the **raw UTF-8 string with no frame**. That covers every menu command, the "Scan" button (`%SCANTM#1#`) and free text.
- Only the legacy `%#INVMD` button sends a frame.

✅ **Verified: the firmware accepts both.** Raw `%BAT_VOL#` (9 bytes, no frame) got the same reply as the framed version. The plugin keeps **framed** as the default, since that is the vendor SDK behaviour and it is what produces the `[LEN, 0x0B]` ACK (§4.2). `sendRaw` stays available.

### 3.4 Frames longer than 20 bytes

A 20-byte write limit (MTU 23) is a problem for:
- `SetTimeStamp`: 26 bytes
- long prefix/suffix commands
- any payload of 15 characters or more

The Android SDK's `BLEManager.ScannerCommand` passes `split=false`, so it sends one over-long write. That works only if the stack does a long write with response; otherwise it is truncated.

Plugin rules:
1. Write with response.
2. On Android, request a higher MTU after connecting, or split into ≤20-byte chunks with response.
3. **[unverified – hardware]**: whether the scanner reassembles split frames. Moot on the DS5000, which runs at MTU 200 (§2).

---

## 4. Data from scanner → phone

### 4.1 One channel for everything

Barcodes **and** command replies (battery, version, counts, and so on) arrive on the **same** notify characteristic (BLE) or the same input stream (SPP), in both vendor SDKs.

Neither SDK has a parser, a prefix match, or request/response correlation. Both demos just do `new String(data)` / `NSUTF8StringEncoding` and print the result.

✅ **Observed on the DS5000.** Three kinds of response to a command:

| Response | Example | Seen for | Meaning (working theory) |
|---|---|---|---|
| **Plain-ASCII reply + CR** (no frame) | `BAT_VOL=3.81V 37%\r` | Queries (framed and raw); full list below | Query answer. Arrives 20–40 ms after the write. **Not every reply has a key prefix** |
| **2-byte ACK** `[LEN, 0x0B]` | `0E 0B` after `%SCANTM#3#` (LEN 0x0E); `0C 0B` after `$BUZZ#B:` (LEN 0x0C) | Action commands | "Command accepted". Byte 0 echoes the frame's LEN byte. This is the packet the vendor SDK silently drops |
| **Full echo of the frame** | The 19-byte `$BUZZ#BK650dc` frame came back unchanged; same for every `%RTCSTAMP#…` | Parameterized commands: custom beep time, RTC/timestamp | **Not a rejection.** The custom beep echoed *and* beeped and vibrated. It is an alternative acknowledgement for some commands. Whether RTC actually works is unclear: no timestamp appeared in live scans, and it may apply only to stored (inventory) data |

Raw (unframed) commands get **no** ACK: raw `%SCANTM#1#` fired the laser but returned nothing. Raw queries do get their text reply.

✅ **ACK format confirmed across command lengths:**
- `0B 0B` for 7-char commands (`$BUZZ#3`, `$MOTO#1`)
- `0C 0B` for 8 chars
- `0E 0B` for 10 chars

**Audible feedback:**
- Raw commands are handled like scanned programming barcodes: they **always beep and vibrate**.
- Framed commands beep only while `%ACKBEEP#1` is set; with `%ACKBEEP#0` they are **silent** but still ACKed.

So the plugin should always send **framed** commands. That gives silent background queries (e.g. battery polling) with `%ACKBEEP#0`, plus machine-readable ACKs.

**Query replies observed (DS5000, firmware below):**

| Query | Reply (`\r` stripped) | Prefix? |
|---|---|---|
| `%BAT_VOL#` | `BAT_VOL=3.81V 37%` | yes |
| `$SW#VER` | `bn0HDS_RFSBTD43bc_CB071` | **no** |
| `%#+TCNT` | `Total Counters=0` | yes |
| `$RF#ST` | `Sleeptime=30min` | yes |
| `AT+VER` | `+VER=1.6.2` followed by a **NUL byte** (`00`) before `\r` | yes |
| `AT+NAME` | `+NAME=DS barcode scanner` | yes |
| `AT+ADDR` | `+ADDR=DC0D3060B42C` | yes |
| `%MODULESN#` | `SE4750` | **no** |

Notes on these replies:
- **The Classic-BT address (`AT+ADDR`, `DC:0D:30:60:B4:2C`) differs from the BLE address (`DD:0D:30:60:B4:2C`)**: first byte +1. The same physical scanner has a different device id per transport. Use `AT+ADDR` (or the serial number) when a transport-independent identity is needed.
- `SE4750` is a Zebra area-imager engine. Such engines can normally decode 2D, so 2D may simply be disabled in the DS5000's firmware. Don't promise 2D support.

Barcodes, by contrast, are bare ASCII + `\r` (e.g. `7771609001660\r`).

The plugin can therefore classify every incoming packet:
1. `[x, 0x0B]` → ACK of the last framed command
2. starts with `0x02` and ends with `0x03` → echo-ACK of the last framed command
3. **a query is pending** (sent < ~500 ms ago) → reply to that query. Correlation by timing is required because `$SW#VER` and `%MODULESN#` replies have no prefix
4. anything else → barcode

Also: strip NUL bytes and the trailing `\r` before decoding. Allow only one in-flight query per device (a command queue).

The original open questions were:
- Are replies framed (start with `0x02`, end with `0x03`)?
- Are they plain ASCII like `3.95V`?
- Do they echo the command?

This is the most important open question for the plugin API: it decides whether `getBatteryLevel()` can be a `Future<double>`, or has to be "send and hope" with replies showing up in the scan stream.

### 4.2 The `0x0B` filter

Both transports drop one specific packet:

```java
if (value.length == 2 && value[1] == 11) { /* drop */ }
```

It appears in the Android SDK's BLE notify path and its SPP read loop. The code never says what this packet is. The most likely explanation is a short ACK or status packet from the scanner.

✅ **Identified: it is the ACK.** The format is `[LEN of the command frame, 0x0B]`; see the §4.1 table. The SDK's `value[1] == 11` check drops every ACK, which is why the demo never showed them. The plugin should **consume** ACKs and use them to complete `send()` futures, not throw them away.

One caveat: an ACK for a 7-char command would be `0B 0B`. A real 2-character barcode `?\x0B` is impossible, since barcodes end with CR, so the classification is safe.

### 4.3 Barcode payload

- **Plain bytes of the barcode text.** Whether a terminator is appended depends on the scanner's `$TERM#n` setting (none, CR, TAB, CRLF or LF). ✅ **The DS5000 ships with CR (`0x0D`) enabled**: every scan observed ended in `0D`.
- **Prefix/suffix** configured on the scanner (`$DATA#…`) is part of the payload.
- **Encoding** depends on the scanner's charset setting (`%CHARSET#n`). UTF-8 is the safe default. The plugin should always expose the **raw bytes** together with its best-effort decoded string, because the iOS demo crashes when a packet is not valid UTF-8.

### 4.4 Fragmentation — **[unverified – hardware]**

Context: the DS5000 is a **1D-only** scanner.
- Retail codes (EAN-13/UPC-A: 12–13 digits, plus an optional terminator) fit in one 20-byte packet.
- Fragmentation matters for longer 1D symbologies such as Code 128 / GS1-128 (shipping labels, serials), Code 39 and ITF.
- It also matters for 2D models (QR/DataMatrix), which are untested.

- BLE with MTU 23 means a barcode longer than 20 bytes almost certainly arrives as **several notifications**.
- Neither SDK reassembles them, so the demos would show one barcode as two or more rows.
- SPP reads up to 1024 bytes per `read()`, so it can also split or merge barcodes.

✅ **Result (Android and iOS): no fragmentation on the DS5000.** The scanner negotiates MTU 200 by itself (§2), so 22- and 32-byte Code 128 scans arrived as **one notification** each, with and without the app requesting MTU.

Observed edge case: two attempts at reading a 35-char Code 128 off a monitor produced the same garbage packet `3C 0D 2A 45 4D 4E 4F 3B 0D` (`<\r*EMNO;\r`). That is a misread containing an **embedded CR**. So "split on every CR" would turn one misread into two fake barcodes.

Plugin baseline:
- Treat **each notification that ends in the terminator as one complete payload** (don't split inside it).
- Buffer only when a notification does **not** end in the terminator, i.e. a payload over 197 bytes or a scanner with no terminator, and flush on terminator or a ~100 ms idle timeout.
- Still request MTU 517 on Android for other Netum models.

The plugin needs a reassembly strategy. In order of preference:
1. A configured terminator, e.g. enable `$TERM#1` (CR) and split on it.
2. An inter-packet idle timeout (e.g. 50–100 ms).
3. A framed format, if replies turn out to be framed.

The hardware result above settled this for the DS5000.

---

## 5. SPP connection flow (Android only)

The SPP UUID is the standard Serial Port Profile `00001101-0000-1000-8000-00805F9B34FB`.

### 5.1 First-time pairing (vendor "SDP" flow)

1. On the scanner, scan `%#IFSNO$4`, then `AT+MODE=1`.
2. Phone: `startSdp()` opens an RFCOMM **server** with `listenUsingRfcommWithServiceRecord("SDPService", SPP_UUID)` and loops on `accept()`.
3. On the scanner, scan a barcode containing the phone's Bluetooth MAC. Either form works:
   - `AT+SPPCONN=AABBCCDDEEFF`
   - `%%AABBCCDDEEFF$`

   The MAC is written without colons. Both forms come from the dev help PDF. The scanner then connects **into** the phone. Because the connection is secure RFCOMM, the OS pairs (bonds) the two devices implicitly.
4. Phone: `accept()` returns. The SDK **immediately closes** the accepted socket; it only wanted to learn the scanner's identity.
5. Phone: 100 ms later, it connects back **as a client** with `createRfcommSocketToServiceRecord(SPP_UUID).connect()`. This client socket carries all data.

> ✅ **Note: this flow is not required.** Phone-initiated pairing also works: discover the scanner (§5.3), tap connect (secure RFCOMM to UUID 1101), and Android shows the system pairing prompt; after accepting, it connects. Repeated 3 times, including after "forget device", with no `AT+SPPCONN` barcode and no SDP. The SDP/`AT+SPPCONN` flow is an alternative.

### 5.2 Consequence for reconnects — **[unverified – hardware]**

The data link is phone-as-client to a bonded scanner. ✅ **Verified (2026-10-08).**
- Hours after the one-time SDP pairing, and after many power cycles and BLE/SPP mode switches, a plain **client connect to the bonded Classic MAC `DC:0D:30:60:B4:2C`** worked in about 0.7 s, with no SDP server and no `AT+SPPCONN` barcode.
- The phone lists the scanner as bonded, type 3 (DUAL), named `DS barcode scanner`.
- So the plugin can offer "saved scanners" and reconnect for SPP. The SDP/barcode step is only needed **once per phone**, or after the pairing is cleared.

### 5.3 SPP "Start Scanning" (classic discovery)

- It uses `BluetoothAdapter.startDiscovery()` and lists `ACTION_FOUND` devices.
- ✅ **Verified: the scanner IS discoverable in SPP mode** (this corrects an earlier "not discoverable" result). The SPP demo list = **bonded devices** (`getBondedDevices()`) + **live classic discovery** (`ACTION_FOUND`).
  - On the Android 10 tablet, discovery found DS5000 units in SPP mode that were never paired with it, including Netum-01 (bonded only to the A24). Dual-mode units show up under both addresses (`DC:…` classic, `DD:…` LE).
  - On the A24 the demo's discovery found **no devices** in every session: the SPP demo requests location permission only up to API 30, and on Android 12+ classic discovery results are not delivered to an app that lacks location permission (no `neverForLocation`). Pairing via Settings → Bluetooth → Pair new device, then connecting from the bonded list, worked.
  - Bonded-record UUIDs reflect the mode at pairing time: Netum-01 (first paired in HID mode) shows only `00001124` (HID), class 0x540; units paired in SPP mode show `00001101`, class 0x404. So **do not filter bonded devices by the SPP UUID**; filter by name or the Classic MAC.
  - Plugin: combine bonded devices and live discovery, and request location permission on all Android versions.

### 5.4 Where to get the phone's MAC

- Android 6+ hides the phone's own Bluetooth MAC from apps (`getAddress()` returns `02:00:00:00:00:00`). The user has to read it from Settings → About phone.
- So the plugin **cannot** reliably build the `AT+SPPCONN=` barcode by itself. Options:
  - The user types the MAC into the host app.
  - The host app displays instructions.
  - The plugin offers a helper `sppPairingBarcodeData(String phoneMac)` that returns the string, and the host app renders it as a 1D barcode (Code 128).

---

## 6. Mode-switch and pairing barcodes (scanned by the scanner, never sent over the air)

| Purpose | Barcode content |
|---|---|
| Bluetooth output | `%#IFSNO$4` |
| SPP mode | `AT+MODE=1` |
| HID mode | `AT+MODE=2` |
| BLE mode | `AT+MODE=3` |
| SPP target phone | `AT+SPPCONN=<PHONEMAC>` or `%%<PHONEMAC>$` |
| Disconnect + clear pairing | `%%ALL-CH` (also exists as an over-the-air command, see [commands.md](commands.md)) |
| Rename (over the air, framed; not a barcode) | `AT+NAME=<name>` ✅. Drops the BLE link at once (status 19), restarts Bluetooth and re-advertises the new name; no ACK. `AT+NAME` returns `+NAME=<name>`. Persists across reconnects and applies to BLE and Classic/SPP |

Going from SPP/BLE back to HID: on the phone, forget the scanner and turn Bluetooth off, then scan `AT+MODE=2`, then turn Bluetooth on and pair again (Quick Setup Guide).

---

## 7. Connection-level behaviour that the plugin must implement itself

Neither vendor SDK does any of this properly:
- Auto-reconnect after the link drops.
- Persisting known devices.
- A Bluetooth adapter on/off state stream.
- A GATT operation queue (serialized CCCD write, MTU request and writes).
- Notification reassembly (section 4.4).
- Reply parsing (section 4.1).
