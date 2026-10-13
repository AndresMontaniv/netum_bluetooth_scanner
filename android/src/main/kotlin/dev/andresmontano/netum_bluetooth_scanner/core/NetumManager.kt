package dev.andresmontano.netum_bluetooth_scanner.core

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.AdapterMonitor
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.PermissionScope
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.Permissions
import dev.andresmontano.netum_bluetooth_scanner.core.ble.BleLink
import dev.andresmontano.netum_bluetooth_scanner.core.ble.BleScanner
import dev.andresmontano.netum_bluetooth_scanner.core.spp.SppDiscovery
import dev.andresmontano.netum_bluetooth_scanner.core.spp.SppLink
import dev.andresmontano.netum_bluetooth_scanner.core.spp.SppListener
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
    val savedStore = SavedStore(this.context)

    /** The attached Flutter side, if any. Events are dropped while detached. */
    var events: NetumEvents? = null

    private val links = LinkedHashMap<String, Link>()

    // Links react to Bluetooth on/off even while Dart is not listening to adapter states.
    init {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                    BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF ->
                        links.values.toList().forEach { it.onAdapterOff() }
                    BluetoothAdapter.STATE_ON ->
                        links.values.toList().forEach { it.onAdapterOn() }
                }
            }
        }
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            this.context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            this.context.registerReceiver(receiver, filter)
        }
    }
    private var bleScanner: BleScanner? = null
    private var sppDiscovery: SppDiscovery? = null

    val isDiscovering: Boolean
        get() = bleScanner?.isScanning == true || sppDiscovery?.isDiscovering == true

    /** Starts discovery; results and failures arrive through [events]. */
    fun startDiscovery(transport: Transport, filterNetum: Boolean, timeoutMs: Long) {
        val adapter = adapterMonitor.adapter
            ?: throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "No Bluetooth adapter", "unsupported")
        if (!adapterMonitor.isPoweredOn) {
            throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "Bluetooth is off", "poweredOff")
        }
        permissions.ensure(PermissionScope.DISCOVERY)
        if (AdapterMonitor.LOCATION_BLOCKS_DISCOVERY && !adapterMonitor.isLocationEnabled) {
            throw NetumError(NetumError.LOCATION_OFF, "Location services are off")
        }
        stopDiscovery()
        when (transport) {
            Transport.BLE -> {
                val scanner = bleScanner ?: BleScanner(adapter, scope, ::emitDiscovery, ::emitDiscoveryError)
                    .also { bleScanner = it }
                scanner.start(filterNetum, timeoutMs)
            }
            Transport.SPP -> sppDiscovery(adapter).start(timeoutMs)
        }
    }

    fun stopDiscovery() {
        bleScanner?.stop()
        sppDiscovery?.stop()
    }

    private var sppListener: SppListener? = null

    /**
     * Waits for a scanner to dial in after scanning `AT+SPPCONN=<phone MAC>`; reports it through
     * the discoveries stream. Stops discovery first so the two can't be confused.
     */
    fun startSppListener(timeoutMs: Long) {
        val adapter = adapterMonitor.adapter
            ?: throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "No Bluetooth adapter", "unsupported")
        if (!adapterMonitor.isPoweredOn) {
            throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "Bluetooth is off", "poweredOff")
        }
        permissions.ensure(PermissionScope.CONNECTION)
        stopDiscovery()
        val listener = sppListener ?: SppListener(adapter, scope, ::emitDiscovery).also { sppListener = it }
        listener.start(timeoutMs)
    }

    fun stopSppListener() {
        sppListener?.stop()
    }

    /** Bonded Classic devices (SPP candidates). */
    fun bondedDevices(): List<DiscoveredDevice> {
        val adapter = adapterMonitor.adapter ?: return emptyList()
        permissions.ensure(PermissionScope.CONNECTION)
        return sppDiscovery(adapter).bonded()
    }

    private fun sppDiscovery(adapter: android.bluetooth.BluetoothAdapter) =
        sppDiscovery ?: SppDiscovery(context, adapter, scope, ::emitDiscovery).also { sppDiscovery = it }

    /** Connects [id]; returns once the link is ready for data. Idempotent while connected. */
    suspend fun connect(
        id: String,
        transport: Transport,
        timeoutMs: Long,
        autoReconnect: Boolean,
        sppInsecureFallback: Boolean,
    ) {
        val adapter = adapterMonitor.adapter
            ?: throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "No Bluetooth adapter", "unsupported")
        if (!adapterMonitor.isPoweredOn) {
            throw NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "Bluetooth is off", "poweredOff")
        }
        permissions.ensure(PermissionScope.CONNECTION)
        if (!BluetoothAdapter.checkBluetoothAddress(id)) {
            throw NetumError(NetumError.INVALID_ARGUMENT, "Not a Bluetooth address: $id")
        }
        links[id]?.let {
            if (it.state == LinkState.CONNECTED) {
                it.setAutoReconnect(autoReconnect)
                return
            }
            throw NetumError(NetumError.BUSY, "$id is already connecting")
        }

        val device = adapter.getRemoteDevice(id)
        when (transport) {
            Transport.BLE -> {
                val link = BleLink(this, device)
                register(link)
                try {
                    link.connect(timeoutMs, autoReconnect)
                } catch (e: Exception) {
                    unregister(link)
                    throw e
                }
            }
            Transport.SPP -> {
                stopDiscovery() // Classic discovery slows RFCOMM connects down a lot.
                val link = SppLink(this, device)
                register(link)
                try {
                    link.connect(timeoutMs, autoReconnect, sppInsecureFallback)
                } catch (e: Exception) {
                    unregister(link)
                    throw e
                }
            }
        }
    }

    fun setAutoReconnect(id: String, enabled: Boolean) {
        val link = links[id] ?: throw NetumError(NetumError.NOT_CONNECTED, "$id is not connected")
        link.setAutoReconnect(enabled)
    }

    fun bleLink(id: String): BleLink {
        val link = links[id] ?: throw NetumError(NetumError.NOT_CONNECTED, "$id is not connected")
        return link as? BleLink ?: throw NetumError(NetumError.UNSUPPORTED, "$id is not a BLE link")
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
