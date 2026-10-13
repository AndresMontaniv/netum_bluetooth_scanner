package dev.andresmontano.netum_bluetooth_scanner.core.spp

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.util.Log
import dev.andresmontano.netum_bluetooth_scanner.core.Link
import dev.andresmontano.netum_bluetooth_scanner.core.LinkEvent
import dev.andresmontano.netum_bluetooth_scanner.core.LinkState
import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import dev.andresmontano.netum_bluetooth_scanner.core.NetumManager
import dev.andresmontano.netum_bluetooth_scanner.core.Transport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException
import java.util.UUID

/**
 * One SPP (RFCOMM) connection. The phone is the client: a secure connect shows the OS pairing
 * prompt the first time (A4.17); a bonded scanner connects in about 0.7 s (A4.18).
 *
 * Blocking socket calls run on [Dispatchers.IO]; state changes and data are reported on the main
 * thread, in order. Teardown closes the socket (never `Thread.destroy()`, the vendor SDK crash).
 */
@SuppressLint("MissingPermission") // NetumManager checks the connection permission first.
class SppLink(
    private val manager: NetumManager,
    private val device: BluetoothDevice,
) : Link {
    override val id: String = device.address
    override val transport = Transport.SPP
    override val name: String? = device.name

    @Volatile
    override var state = LinkState.DISCONNECTED
        private set

    @Volatile
    private var socket: BluetoothSocket? = null
    private val writeLock = Mutex()
    private var autoReconnect = false
    private var insecureFallback = false
    private var userDisconnecting = false
    private var reconnecting = false
    private var reconnectJob: Job? = null

    /** Connects (main thread). Throws `connection-failed`. */
    suspend fun connect(timeoutMs: Long, autoReconnect: Boolean, insecureFallback: Boolean) {
        this.autoReconnect = autoReconnect
        this.insecureFallback = insecureFallback
        setState(LinkState.CONNECTING, userInitiated = true)
        // An unpaired scanner shows the OS pairing prompt: give the user time to accept it.
        val effectiveTimeout =
            if (device.bondState == BluetoothDevice.BOND_BONDED) timeoutMs
            else maxOf(timeoutMs, PAIRING_TIMEOUT_MS)
        val opened = try {
            openSocket(effectiveTimeout)
        } catch (e: NetumError) {
            finish(userInitiated = false, message = e.message)
            throw e
        } catch (e: SecurityException) {
            finish(userInitiated = false, message = e.message)
            throw NetumError(NetumError.PERMISSION_DENIED, e.message ?: "Missing permission")
        }
        socket = opened
        setState(LinkState.CONNECTED, userInitiated = true)
        startReading(opened)
    }

    override suspend fun write(bytes: ByteArray) {
        val current = socket
        if (current == null || state != LinkState.CONNECTED) {
            throw NetumError(NetumError.NOT_CONNECTED, "$id is not connected")
        }
        writeLock.withLock {
            withContext(Dispatchers.IO) {
                try {
                    current.outputStream.write(bytes)
                    current.outputStream.flush()
                } catch (e: IOException) {
                    throw NetumError(NetumError.NOT_CONNECTED, "Write failed: ${e.message}")
                }
            }
        }
    }

    override suspend fun disconnect() {
        if (reconnecting) {
            cancelReconnect()
            finish(userInitiated = true)
            return
        }
        val current = socket ?: return finish(userInitiated = true)
        userDisconnecting = true
        setState(LinkState.DISCONNECTING, userInitiated = true)
        withContext(Dispatchers.IO) { runCatching { current.close() } }
        // The read loop notices the close and reports it; don't wait forever.
        withTimeoutOrNull(DISCONNECT_TIMEOUT_MS) {
            while (state != LinkState.DISCONNECTED) delay(20)
        }
        finish(userInitiated = true)
    }

    override fun close() {
        cancelReconnect()
        runCatching { socket?.close() }
        socket = null
        state = LinkState.DISCONNECTED
    }

    override fun setAutoReconnect(enabled: Boolean) {
        autoReconnect = enabled
        if (!enabled && reconnecting) {
            cancelReconnect()
            finish(userInitiated = true, message = "Auto-reconnect turned off")
        }
    }

    // A connected socket fails on its own when Bluetooth goes off (read loop); the reconnect loop
    // skips attempts while Bluetooth is off.
    override fun onAdapterOff() = Unit

    override fun onAdapterOn() = Unit

    // region Socket

    private suspend fun openSocket(timeoutMs: Long): BluetoothSocket = withContext(Dispatchers.IO) {
        // Discovery slows RFCOMM connects down a lot.
        manager.adapterMonitor.adapter?.cancelDiscovery()
        try {
            connectWith(device.createRfcommSocketToServiceRecord(SPP_UUID), timeoutMs)
        } catch (e: IOException) {
            if (!insecureFallback) {
                throw NetumError(NetumError.CONNECTION_FAILED, "SPP connect failed: ${e.message}")
            }
            try {
                connectWith(device.createInsecureRfcommSocketToServiceRecord(SPP_UUID), timeoutMs)
            } catch (e2: IOException) {
                throw NetumError(NetumError.CONNECTION_FAILED, "SPP connect failed: ${e2.message}")
            }
        }
    }

    /** `BluetoothSocket.connect()` has no timeout: a watchdog closes the socket to abort it. */
    private suspend fun connectWith(candidate: BluetoothSocket, timeoutMs: Long): BluetoothSocket =
        coroutineScope {
            val watchdog = launch {
                delay(timeoutMs)
                runCatching { candidate.close() }
            }
            try {
                candidate.connect()
                candidate
            } catch (e: IOException) {
                runCatching { candidate.close() }
                throw if (watchdog.isCompleted) IOException("timed out after $timeoutMs ms") else e
            } finally {
                watchdog.cancel()
            }
        }

    private fun startReading(current: BluetoothSocket) {
        manager.scope.launch(Dispatchers.IO) {
            val buffer = ByteArray(READ_BUFFER_SIZE)
            try {
                val input = current.inputStream
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    val bytes = buffer.copyOf(count)
                    withContext(Dispatchers.Main) {
                        if (state == LinkState.CONNECTED) manager.emitData(id, bytes)
                    }
                }
            } catch (e: IOException) {
                // Closed by us, powered off, out of range or Bluetooth off.
            }
            withContext(Dispatchers.Main) { onSocketClosed(current) }
        }
    }

    private fun onSocketClosed(closed: BluetoothSocket) {
        if (closed !== socket) return // A socket we already replaced or dropped.
        socket = null
        runCatching { closed.close() }
        when {
            userDisconnecting -> finish(userInitiated = true)
            autoReconnect -> beginReconnect()
            else -> finish(userInitiated = false, message = "Link lost")
        }
    }

    // endregion

    // region Auto-reconnect (main thread)

    private fun beginReconnect() {
        reconnecting = true
        val startedAt = System.currentTimeMillis()
        // Dart turns this pair into `reconnecting`.
        setState(LinkState.DISCONNECTED, userInitiated = false)
        setState(LinkState.CONNECTING, userInitiated = false)
        reconnectJob = manager.scope.launch {
            var attempt = 0
            while (reconnecting) {
                delay(BACKOFF_MS[minOf(attempt, BACKOFF_MS.lastIndex)])
                attempt++
                if (!reconnecting) break
                if (!manager.adapterMonitor.isPoweredOn) continue
                val opened = try {
                    openSocket(RECONNECT_CONNECT_TIMEOUT_MS)
                } catch (e: NetumError) {
                    continue
                } catch (e: SecurityException) {
                    cancelReconnect()
                    finish(userInitiated = false, message = e.message)
                    return@launch
                }
                if (!reconnecting) {
                    runCatching { opened.close() }
                    return@launch
                }
                reconnecting = false
                socket = opened
                Log.i(TAG, "$id reconnected after ${System.currentTimeMillis() - startedAt} ms ($attempt attempts)")
                setState(LinkState.CONNECTED, userInitiated = false)
                startReading(opened)
            }
        }
    }

    private fun cancelReconnect() {
        reconnecting = false
        reconnectJob?.cancel()
        reconnectJob = null
    }

    // endregion

    private fun setState(newState: LinkState, userInitiated: Boolean, message: String? = null) {
        state = newState
        manager.emitLinkState(LinkEvent(id, transport, newState, userInitiated, null, message))
    }

    /** Releases the slot and reports the disconnect (once). */
    private fun finish(userInitiated: Boolean, message: String? = null) {
        if (state == LinkState.DISCONNECTED) return
        runCatching { socket?.close() }
        socket = null
        manager.unregister(this)
        setState(LinkState.DISCONNECTED, userInitiated, message)
    }

    companion object {
        private const val TAG = "NetumSppLink"
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val PAIRING_TIMEOUT_MS = 60_000L
        private const val RECONNECT_CONNECT_TIMEOUT_MS = 10_000L
        private const val DISCONNECT_TIMEOUT_MS = 2_000L
        private const val READ_BUFFER_SIZE = 1024
        private val BACKOFF_MS = longArrayOf(1_000, 2_000, 5_000, 10_000, 30_000)
    }
}
