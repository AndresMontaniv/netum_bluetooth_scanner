package dev.andresmontano.netum_bluetooth_scanner.core

enum class Transport { BLE, SPP }

enum class LinkState { DISCONNECTED, CONNECTING, CONNECTED, DISCONNECTING }

data class LinkEvent(
    val id: String,
    val transport: Transport,
    val state: LinkState,
    val userInitiated: Boolean,
    val platformCode: Int? = null,
    val message: String? = null,
)

data class DiscoveredDevice(
    val id: String,
    val transport: Transport,
    val name: String?,
    val rssi: Int?,
    val bonded: Boolean,
    val serviceUuids: List<String>,
)

data class ActiveLink(val id: String, val transport: Transport, val name: String?)

/** Receives everything the core reports. Always called on the main thread. */
interface NetumEvents {
    fun onDiscovery(device: DiscoveredDevice)
    fun onDiscoveryError(error: NetumError)
    fun onLinkState(event: LinkEvent)
    fun onData(id: String, bytes: ByteArray, timestampMicros: Long)
}

/** One connection to a scanner (BLE now, SPP in S5). */
interface Link {
    val id: String
    val transport: Transport
    val name: String?
    val state: LinkState

    suspend fun write(bytes: ByteArray)
    suspend fun disconnect()

    /** Whether an unexpected disconnect is followed by an automatic reconnect. */
    fun setAutoReconnect(enabled: Boolean)

    /** Bluetooth turned off: pause or end the link. */
    fun onAdapterOff()

    /** Bluetooth turned back on: re-arm a pending reconnect. */
    fun onAdapterOn()

    /** Releases platform resources without reporting a state change. */
    fun close()
}
