package dev.andresmontano.netum_bluetooth_scanner.core.spp

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import dev.andresmontano.netum_bluetooth_scanner.core.DiscoveredDevice
import dev.andresmontano.netum_bluetooth_scanner.core.Transport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Classic (SPP) discovery: bonded devices first, then live inquiry (`ACTION_FOUND`). An inquiry
 * ends after ~12 s, so it is restarted until the timeout. Every device is reported; Dart decides
 * which look like NETUM scanners (bonded records can't be filtered by UUID: A4.20).
 */
@SuppressLint("MissingPermission") // NetumManager checks the discovery permissions first.
class SppDiscovery(
    private val context: Context,
    private val adapter: BluetoothAdapter,
    private val scope: CoroutineScope,
    private val onDevice: (DiscoveredDevice) -> Unit,
) {
    private var receiver: BroadcastReceiver? = null
    private var timeout: Job? = null

    val isDiscovering: Boolean
        get() = receiver != null

    fun bonded(): List<DiscoveredDevice> =
        adapter.bondedDevices.orEmpty().map { it.toDiscovered(rssi = null, name = it.name) }

    fun start(timeoutMs: Long) {
        stop()
        bonded().forEach(onDevice)

        val newReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device = intent.device() ?: return
                        if (device.type == BluetoothDevice.DEVICE_TYPE_LE) return
                        val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                        onDevice(
                            device.toDiscovered(
                                rssi = rssi.takeIf { it != Short.MIN_VALUE }?.toInt(),
                                name = intent.getStringExtra(BluetoothDevice.EXTRA_NAME) ?: device.name,
                            ),
                        )
                    }
                    // Keep inquiring until the timeout.
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED ->
                        if (receiver != null) adapter.startDiscovery()
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        // ACTION_FOUND comes from the Bluetooth app (com.android.bluetooth), not the system server,
        // so a NOT_EXPORTED receiver never gets it (found on the A24, S5). Adapter on/off
        // broadcasts come from the system server and work with NOT_EXPORTED.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(newReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(newReceiver, filter)
        }
        receiver = newReceiver
        adapter.cancelDiscovery()
        adapter.startDiscovery()
        timeout = scope.launch {
            delay(timeoutMs)
            stop()
        }
    }

    fun stop() {
        timeout?.cancel()
        timeout = null
        receiver?.let {
            receiver = null
            context.unregisterReceiver(it)
            adapter.cancelDiscovery()
        }
    }

    private fun BluetoothDevice.toDiscovered(rssi: Int?, name: String?) = DiscoveredDevice(
        id = address,
        transport = Transport.SPP,
        name = name,
        rssi = rssi,
        bonded = bondState == BluetoothDevice.BOND_BONDED,
        serviceUuids = uuids.orEmpty().map { it.uuid.toString().uppercase() },
    )

    private fun Intent.device(): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
}
