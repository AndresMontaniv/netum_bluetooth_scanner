# NETUM command catalog

> Every over-the-air command found in NETUM's Android SDK and iOS demo. Commands are ASCII strings. Frame them as described in [protocol.md](protocol.md) §3, or send them raw (§3.3).

Columns:
- **AND** = the Android SDK's constant or helper name
- **iOS** = the iOS demo's command number (CmdType). Labels are translated from Chinese.

Kind:
- **Q** = query: a reply is expected over the data channel; format unknown.
- **S** = setting: persists on the scanner.
- **A** = one-shot action.

**Settings persist across power cycles** (verified with `$BUZZ#3`).

**Hardware verification status (DS5000, BLE, 2026-10-07):** verified rows are marked ✅ in the Notes column, with the observed reply. Every other row is unverified.

---

## 1. System / info

| Command | Meaning | Kind | AND | iOS | Notes |
|---|---|---|---|---|---|
| `$SW#VER` | Read firmware version | Q | `ReadFirmwareVersion` | 1 | ✅ `bn0HDS_RFSBTD43bc_CB071` (no prefix) |
| `%#IFSNO$B` | Factory reset (scanner settings) | A | `RestoreToFactorySet` | 2 | Letter **O** |
| `%#IFSNO$` | Read current interface/transport setting | Q | `ReadInterfaceSetting` | — | |
| `%MODULESN#` | Read decode-engine (CCD/2D module) model | Q | `GetCCDModuleType` | 54 | ✅ `SE4750` (no prefix) |
| `%MODULESN#{n}#` | Set decode-engine model, n = 0..5 | S | `SetCCDModuleType` | 55–60 | Factory-level setting; don't expose casually. The unused AND enum `ModuleType` lists 212X, C06C, 4710, 280H, 4680, EX25, RFID |

## 2. Work mode / on-device storage (inventory mode)

| Command | Meaning | Kind | AND | iOS |
|---|---|---|---|---|
| `%#NORMD` | Normal mode: send each scan immediately | S | `WorkMode_Normal` | 3 |
| `%#INVMD` | Storage/inventory mode: keep scans in scanner memory | S | `WorkMode_Store` | 4 |
| `%#TXMEM` | Upload stored barcodes | A (+data) | `StoreDataUpload` | 5 ✅ ACK, then one notification per stored code, each ending in **two** CRs (`…0D 0D`) |
| `%#TXMEM#C` | Upload stored barcodes, then clear | A (+data) | `StoreDataUploadClear` | 6 |
| `%#+TCNT` | Count of stored barcodes | Q | `StoreDataNumber` | 7 ✅ `Total Counters=0` |
| `%#+TCNT#` | Count + memory usage | Q | `StoreDataNumberAndSpaceOccupancy` | 8 |
| `%#*NEW*` | Clear stored barcodes | A | `StoreDataClear` | 9 |
| `%AutoSav#Off` / `%AutoSav#On` | Auto-save to memory when out of range | S | `StoreAutoSaveOff` / `On` | 10 / 11 |

## 3. Power

| Command | Meaning | Kind | AND | iOS |
|---|---|---|---|---|
| `$RF#ST` | Read sleep timeout | Q | `ReadSleeptime` | 12 ✅ `Sleeptime=30min`; "never" reads back as `Sleeptime=None` |
| `$POWER#OFF` | Power off now | A | `PowerOff` | 13 |
| `$RF#ST{xy}` | Set sleep timeout. `xy` = two chars, value = `(c1-'0')*10 + (c2-'0')`, in 30 s units | S | see below | 14–21 |
| `%BAT_VOL#` | Read battery level/voltage | Q | `GetVolume` (misnamed; it is battery, not volume) | 22 ✅ `BAT_VOL=3.81V 37%` |

Sleep presets:

| Constant | Command | Timeout |
|---|---|---|
| `NeverSleep` | `$RF#ST00` | never |
| `SleepTime1Min` | `$RF#ST02` | 1 min |
| `SleepTime3Min` | `$RF#ST06` | 3 min |
| `SleepTime5Min` | `$RF#ST10` | 5 min |
| `SleepTime10Min` | `$RF#ST20` | 10 min |
| `SleepTime30Min` | `$RF#ST60` | 30 min |
| `SleepTime1Hour` | `$RF#ST<0` | 1 h (`<` = `'0'+12`) |
| `SleepTime2Hour` | `$RF#STH0` | 2 h (`H` = `'0'+24`) |

## 4. Beeper / vibration / feedback

| Command | Meaning | Kind | AND | iOS | Notes |
|---|---|---|---|---|---|
| `$BUZZ#0` | Mute | S | `BeepMuteVolume` | 23 | |
| `$BUZZ#1` / `#2` / `#3` | Volume high / mid / low | S | `BeepHigh/Middle/LowVolume` | 24–26 | |
| `$BUZZ#4` / `#5` | Tone high / low | S | `BeepHighTone` / `BeepLowTone` | 27 / 28 | ✅ ACKed, but **no audible difference on the DS5000** |
| `$MOTO#0` / `$MOTO#1` | Vibration | S | AND: `#0` = **disable**, `#1` = **enable** | 29 / 30. iOS: `#0` = "vibration **on**", `#1` = "**off**" | ✅ **Android is right:** `$MOTO#1` = vibration ON, `$MOTO#0` = OFF. The iOS labels are swapped |
| `%ACKBEEP#0` / `#1` | "SDK sound acknowledgement" off / on | S | `SDKAckBeepOff` / `On` | 31 / 32 | ✅ Controls the audible beep + vibration when the scanner receives a **framed** command: `#1` = confirm audibly, `#0` = silent (the `[LEN,0x0B]` ACK is still sent). **Raw commands always beep**, whatever this setting is |
| `%ACKBEEP#2` | Base/cradle connect beep toggle | S | `BaseConnectBeep` | 33 | |
| `$BUZZ#B{c}` | **Beep preset.** `c = chr(level + 0x30)`, level 0..26 | A | `ScannerUtil.CustomBeep(level)` | — | This is the demo's **SEND** button with the default **10** (`c` = `:`). Level 27 would be `K`, which collides with the `$BUZZ#BK` sub-command; hence the 0..26 cap. ✅ All levels ACKed. Heard: 0 = short beep, 5 = a different short beep, 20 (`D`) = rising "bee-ree-beep", 26 (`J`) = "tee-ree-tee-ree" trill. A preset melody table, so the plugin can expose it as `beep(int 0..26)` |
| `$BUZZ#BK{t}{type}{f}` | Custom beep/vibration | A | `ScannerUtil.CustomBeepTime(time, type, freq)` | — | Parameters below. ACKed by a full-frame echo. ✅ **`type` is ignored on the DS5000**: types 0/1/2 all behave the same, and vibration follows the global `$MOTO#` setting. Duration/frequency encoding unconfirmed (see note) |

`$BUZZ#BK` parameters:
- `t = hex((time+10)/10)`, with time clamped to 10..2540 ms
- `type`: 0 = beep + vibration, 1 = beep only, 2 = vibration only
- `f = hex((freq-100)/20)`, with freq clamped to 100..5200 Hz

⚠️ Android uses `Integer.toHexString`, which gives lowercase, **unpadded** hex. For example, time=10 gives `2` (one character), and freq=4500 gives `dc`. A fixed-width format was probably intended, so the firmware may mis-parse these. Observed: time=100 is sent as `$BUZZ#BKb0dc` (a 1-digit time) and sounded the same as 1000 ms, which points to a misparse. Confirming test (Framed, optional): `$BUZZ#BK0b0dc` (100 ms padded) vs `$BUZZ#BKfe0dc` (≈2.5 s), and `$BUZZ#BK65005` (200 Hz) vs `$BUZZ#BK650f5` (5000 Hz). Plugin plan: expose `beep(0..26)` presets as the main API; mark custom beep as experimental, using fixed-width 2-digit hex.

## 5. Scan behaviour / triggering

| Command | Meaning | Kind | AND | iOS | Notes |
|---|---|---|---|---|---|
| `%SCANTM#{n}#` | **Software trigger**: scan for n seconds, n = 1..7 | A | `ScannerUtil.SoftTrigger(n)` (clamps 1..7) | 69 (and "Scan" button = `%SCANTM#1#`) | This is the demo's **SCAN** button with the default **3** |
| `%SCMD#00#` | Trigger-key scan mode (default) | S | `KeyScanMode` | 61 | ✅ Laser on while the trigger is held |
| `%SCMD#01#` | Continuous scan mode | S | `ContinueScanMode` | 62 | ✅ DS5000: a trigger press toggles a steady laser on/off |
| `%SCMD#02#` | Key pulse mode | S | `KeyPulseScanMode` | 63 | ✅ DS5000: a trigger press gives one ~3 s scan that stops by itself |
| `%SCMD#03#` | Host-trigger mode (vendor label) | S | `HostTriggerMode` | 64 | ✅ **Not app-only on the DS5000:** a trigger press toggles a repeating ~1 s scan cycle; `%SCANTM#n#` from the app still works |
| `%SCMD#3000D` / `%SCMD#6000D` | Decode timeout 3 s / 6 s | S | `DecodeOvertime3S` / `6S` | 65 / 66 | Pattern: `%SCMD#{ms:4}D` (unverified) |
| `%SCMD#0500I` / `%SCMD#1000I` | Interval between scans 0.5 s / 1 s | S | `IntervalTime05S` / `10S` | 67 / 68 | Pattern: `%SCMD#{ms:4}I` (unverified) |

## 6. RTC / timestamp (Android only)

| Command | Meaning | Kind | AND | Notes |
|---|---|---|---|---|
| `%RTCSTAMP#0` / `#1` | Disable / enable timestamp on output | S | `DisableTimeStamp` / `EnableTimeStamp` | Hidden row in the demo |
| `%RTCTIME#{YY/MM/DD,hh:mm:ss}` | Set clock (text format), e.g. `23/05/04,09:51:00` | A | `TimeStampSetFormat1` | 26-byte payload, 32-byte frame: over the 20-byte limit |
| `%RTCSTAMP#{epoch10}` | Set clock (10-digit epoch seconds) | A | `TimeStampSetFormat2` via `ScannerUtil.SetTimeStamp(date)` | ⚠️ Adds `getRawOffset()`, so local time is sent as epoch and **DST is ignored** (1 h off in summer). The frame is 26 bytes |

## 7. Bluetooth module (AT commands) — iOS only

| Command | Meaning | Kind | iOS |
|---|---|---|---|
| `%#IFSNO$4` | Bluetooth output mode | S | 34 |
| `AT+MODE=1` / `=2` / `=3` | SPP / HID / BLE mode | S | 35 / 36 / 37 |
| `AT+VER` | Bluetooth firmware version | Q | 38 ✅ `+VER=1.6.2` + NUL |
| `AT+NAME` | Bluetooth name | Q | 39 ✅ `+NAME=DS barcode scanner` |
| `AT+ADDR` | Bluetooth MAC | Q | 40 ✅ `+ADDR=DC0D3060B42C`: the **Classic** MAC; BLE MAC is `DD:…` (useful on iOS, which hides MACs) |
| `AT+REBOOT` | Reboot the Bluetooth module | A | 41 |
| `AT+RESTORE` | Factory-reset the Bluetooth module | A | 42 |
| `AT+DISC` | Disconnect, keep pairing | A | 43 |
| `%%ALL-CH` | Disconnect and clear pairing records | A | 44 |
| `AT+HIDDLY` / `=2` / `=10` / `=30` | Query / set HID key delay low / mid / high | Q / S | 50–53 |

⚠️ The `%%…` commands come from Obj-C string literals that are **not** format strings, so the bytes on the wire really are two `%` characters. Keep them as-is.

## 8. HID keyboard behaviour (only relevant in HID mode) — iOS only

| Command | Meaning | iOS |
|---|---|---|
| `%%0S` | Toggle the iOS on-screen keyboard | 45 |
| `%%0H3` | Enable/disable: hold trigger 3 s toggles the iOS keyboard | 46 |
| `%%0HH` | Enable/disable: double-click trigger toggles the iOS keyboard | 47 |
| `%%0HL` | Caps Lock ignore (Windows) toggle | 48 |
| `%%0H8` | Enable/disable: hold trigger 8 s switches BT / 2.4G | 49 |
| `$KEY#M1` / `$KEY#M0` | Ctrl combos for chars < 0x20 on / off | 79 / 80 |
| `%LKLED#0`…`#5` | Normal case / invert case / all upper / all lower / no numpad / numpad | 81–86 |
| `%CHARSET#` | Read output charset | 87 |
| `%CHARSET#0` / `1` / `2` / `21` / `3` / `4` | Charset: auto / ANSI / UTF-8 (Word) / UTF-8 (TXT) / ISO-8859 / Normal | 88–93 |
| `$KB#OS` | Read host OS type | 94 |
| `$KB#OS0` / `1` / `2` | Host = Windows / Apple / Android | 95–97 |
| `$LAN#` | Read keyboard language | 98 (AND `ReadCurrentSelectedLanguage`) |
| `$LAN#{XX}` | Keyboard layout | 99–128 (AND `KeyboardSelectedLanguage_XX`) |

Language codes for `$LAN#{XX}`: EN (US), FR, GE (DE), TK (TR-Q), TF (TR-F), PT, ES, CS, IT, FB (BE-FR), PB (BR-PT), FC (CA-FR), HR, SK, DA, FI, HU, **EL = Latin-American Spanish** (not Greek), NL, NO, PL, SR, SL, SV, DS (CH-DE), UK (GB), JP, TH, AG (ALT generic), RU (ALT single-byte).

`%CHARSET` may also affect BLE/SPP payload encoding. Unverified.

## 9. Wired / 2.4G (not relevant to the plugin; listed for completeness) — iOS only

| Command | Meaning | iOS |
|---|---|---|
| `%#IFSNO$2` / `%#IFSNO$3` | USB HID / USB virtual COM | 70 / 71 |
| `%000604` / `%000605` | Auto wired/wireless selection on / off | 72 / 73 |
| `%KB#SP0` / `SP7` / `SP?` | Wired latency low / mid / high | 74–76 |
| `%#IFSNO$6` / `$7` | Wired HID multi-key on / off | 77 / 78 |

## 10. Data formatting (prefix / suffix / hide / terminator)

| Command | Meaning | Kind | AND | iOS |
|---|---|---|---|---|
| `$DATA#0` | Clear all prefix/suffix/hide formatting | S | `PrefixSuffixHideClearFormat` | 129 |
| `$DATA#1` | Enable suffix output | S | `AllowSuffixOutput` | 130 |
| `$DATA#2` | Enable prefix output | S | `AllowPrefixOutput` | 131 |
| `$DATA#3` | Enable "hide tail" | S | `AllowHidBarcodeSuffix` | 132 |
| `$DATA#4` | Enable "hide middle" | S | `AllowHidBarcodeContent` | 133 |
| `$DATA#5` | Enable "hide head" | S | `AllowHidBarcodePrefix` | 134 |
| `$DATA#10{len}{text}#` | Set **suffix** (sample `$DATA#1005abcd\x03#`) | S | — | 135 |
| `$DATA#20{len}{text}#` | Set **prefix** (sample `$DATA#200ANETUM12345#`) | S | — | 136 |
| `$DATA#30{nn}#` | Hide n chars (sample `$DATA#3008#`) | S | — | 137 |
| `$DATA#40{ss}{nn}#` | Hide middle chars (sample `$DATA#40050A#`) | S | — | 138 |
| `$DATA#50{nn}#` | Hide n chars (sample `$DATA#5011#`) | S | — | 139 |
| `$TERM#0`…`#4` | Terminator: none / CR / TAB / CRLF / LF | S | — | 140–144 | ✅ DS5000 factory value is **`#0` (none)**: every scan still ends in CR from a separate built-in setting, and `$TERM#1` adds a **second** CR |

Notes on this section:
- `{len}` / `{nn}` are 2-digit hex. The iOS demo's `dealPreSuffixCmd` formats `len` with `%1x` and pads it to 2 digits.
- ⚠️ **Prefix/suffix label conflict inside iOS.** CmdType135 is named "add suffix" but its alert says "enter a prefix", and 136 is the reverse. Going by `$DATA#1` = suffix and `$DATA#2` = prefix, **`$DATA#10…` = suffix and `$DATA#20…` = prefix**.
- ⚠️ **Hide head/tail conflict inside iOS.** 137 is labelled "hide **first** n", but it uses `3`, which 132 labels "hide **tail**". 139 is labelled "hide **last** n" but uses `5` = "head". Either the labels or the enable commands are swapped (unverified).
- **Terminators:** the DS5000 ends every scan with CR even at `$TERM#0` (factory). Leave `$TERM` at none; `$TERM#1` doubles the CR. The plugin's decoder strips any trailing run of CR/LF/TAB, so either works ([protocol.md](protocol.md) §4.4).

## 11. Raw engine passthrough (Android, unused)

`ModuleUtil.AutomaticScan()` returns `07 C6 04 08 00 8A 09 FE 94`. This is a **Zebra/Symbol SSI** `PARAM_SEND` (permanent) that sets trigger mode (param 0x8A) to 0x09 (presentation / auto-sense). It is not Netum-framed and nothing calls it. It shows the decode engine can be addressed directly, but don't expose it in v1.
