package dev.andresmontano.netum_bluetooth_scanner.core

import android.content.Context
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.AdapterMonitor
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.PermissionScope
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.Permissions
import dev.andresmontano.netum_bluetooth_scanner.core.ble.BleScanner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Application-scoped owner of every link. It outlives Flutter engines and Activities, so
 * connections survive a Dart hot restart and a future foreground service can adopt them (D6).
 */
class NetumManager private constructor(context: Context) {
    val context: Context = context.applicationContext
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val adapterMonitor = AdapterMonitor(this.context)
    val permissions = Permissions(this.context)

    /** The attached Flutter side, if any. Events are dropped while detached. */
    var events: NetumEvents? = null

    private val links = LinkedHashMap<String, Link>()
    private var bleScanner: BleScanner? = null

    val isDiscovering: Boolean
        get() = bleScanner?.isScanning == true

    /** Starts BLE discovery; results and failures arrive through [events]. */
    fun startDiscovery(transport: Transport, filterNetum: Boolean, timeoutMs: Long) {
        if (transport == Transport.SPP) {
            throw NetumError(NetumError.UNIMPLEMENTED, "SPP discovery arrives in S5")
        }
        val adapter = adapterMonitor.adapter
            ?: throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "No Bluetooth adapter")
        if (!adapterMonitor.isPoweredOn) {
            throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "Bluetooth is off")
        }
        permissions.ensure(PermissionScope.DISCOVERY)
        if (AdapterMonitor.LOCATION_BLOCKS_DISCOVERY && !adapterMonitor.isLocationEnabled) {
            throw NetumError(NetumError.LOCATION_OFF, "Location services are off")
        }
        val scanner = bleScanner ?: BleScanner(adapter, scope, ::emitDiscovery, ::emitDiscoveryError)
            .also { bleScanner = it }
        scanner.start(filterNetum, timeoutMs)
    }

    fun stopDiscovery() {
        bleScanner?.stop()
    }

    fun link(id: String): Link? = links[id]

    /** Links that are ready for data, for re-adoption after a hot restart. */
    fun activeLinks(): List<ActiveLink> = links.values
        .filter { it.state == LinkState.CONNECTED }
        .map { ActiveLink(it.id, it.transport, it.name) }

    /** Reserves a slot for a new link. Throws if [id] is taken or every slot is used. */
    fun register(link: Link) {
        if (links.containsKey(link.id)) {
            throw NetumError(NetumError.BUSY, "${link.id} is already connected or connecting")
        }
        if (links.size >= MAX_LINKS) {
            throw NetumError(NetumError.MAX_CONNECTIONS, "At most $MAX_LINKS connections")
        }
        links[link.id] = link
    }

    fun unregister(link: Link) {
        if (links[link.id] === link) links.remove(link.id)
    }

    fun emitLinkState(event: LinkEvent) {
        events?.onLinkState(event)
    }

    fun emitData(id: String, bytes: ByteArray) {
        events?.onData(id, bytes, System.currentTimeMillis() * 1000)
    }

    fun emitDiscovery(device: DiscoveredDevice) {
        events?.onDiscovery(device)
    }

    fun emitDiscoveryError(error: NetumError) {
        events?.onDiscoveryError(error)
    }

    companion object {
        const val MAX_LINKS = 7

        @Volatile
        private var instance: NetumManager? = null

        fun get(context: Context): NetumManager =
            instance ?: synchronized(this) {
                instance ?: NetumManager(context).also { instance = it }
            }
    }
}
