package dev.andresmontano.netum_bluetooth_scanner.core.spp

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import dev.andresmontano.netum_bluetooth_scanner.core.DiscoveredDevice
import dev.andresmontano.netum_bluetooth_scanner.core.Transport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * "Pair by scanning" (the vendor's SDP flow, A4.19): the phone runs an RFCOMM server; the scanner,
 * after scanning `AT+SPPCONN=<phone MAC>`, dials in. The accepted socket is only used to learn who
 * called: it is closed at once, and the app then connects as a client (vendor-proven pattern).
 */
@SuppressLint("MissingPermission") // NetumManager checks the connection permission first.
class SppListener(
    private val adapter: BluetoothAdapter,
    private val scope: CoroutineScope,
    private val onScanner: (DiscoveredDevice) -> Unit,
) {
    private var server: BluetoothServerSocket? = null
    private var job: Job? = null

    val isListening: Boolean
        get() = job?.isActive == true

    fun start(timeoutMs: Long) {
        stop()
        val listening = adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, SppLink.SPP_UUID)
        server = listening
        job = scope.launch {
            val caller: BluetoothDevice? = withContext(Dispatchers.IO) {
                try {
                    listening.accept(timeoutMs.toInt()).use { it.remoteDevice }
                } catch (e: IOException) {
                    null // Timed out or stopped.
                } finally {
                    runCatching { listening.close() }
                }
            }
            server = null
            caller ?: return@launch
            onScanner(
                DiscoveredDevice(
                    id = caller.address,
                    transport = Transport.SPP,
                    name = caller.name,
                    rssi = null,
                    bonded = caller.bondState == BluetoothDevice.BOND_BONDED,
                    serviceUuids = caller.uuids.orEmpty().map { it.uuid.toString().uppercase() },
                ),
            )
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        // Closing the server unblocks accept().
        runCatching { server?.close() }
        server = null
    }

    private companion object {
        const val SERVICE_NAME = "NetumBluetoothScanner"
    }
}
