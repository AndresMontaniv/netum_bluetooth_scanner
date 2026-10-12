package dev.andresmontano.netum_bluetooth_scanner.core.ble

import java.util.UUID

/** GATT UUIDs used by NETUM scanners (doc/protocol.md §2). */
object BleUuids {
    private const val BASE = "-0000-1000-8000-00805F9B34FB"

    fun from16(short: String): UUID = UUID.fromString("0000$short$BASE")

    /** Accepts a 16-bit ("FFF0") or full 128-bit UUID string. */
    fun parse(value: String): UUID = if (value.length == 4) from16(value) else UUID.fromString(value)

    /** Advertised services that mark a NETUM scanner (BT825 module, other modules). */
    val SCAN_FILTER = listOf(from16("FFF0"), from16("FF00"), from16("18F0"))

    /** Service / notify / write triples, in preference order. */
    val VARIANTS = listOf(
        Triple(from16("FFF0"), from16("FFF1"), from16("FFF2")),
        Triple(from16("FF00"), from16("FF01"), from16("FF02")),
    )

    val CCCD: UUID = from16("2902")
}
