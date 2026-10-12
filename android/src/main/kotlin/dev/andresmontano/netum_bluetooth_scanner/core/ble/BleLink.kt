package dev.andresmontano.netum_bluetooth_scanner.core.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.os.Build
import android.os.Handler
import android.os.Looper
import dev.andresmontano.netum_bluetooth_scanner.core.Link
import dev.andresmontano.netum_bluetooth_scanner.core.LinkEvent
import dev.andresmontano.netum_bluetooth_scanner.core.LinkState
import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import dev.andresmontano.netum_bluetooth_scanner.core.NetumManager
import dev.andresmontano.netum_bluetooth_scanner.core.Transport
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID

/**
 * One BLE connection. Connect sequence: GATT connect (one retry on status 133) → discover
 * services → pick FFF0/FFF1/FFF2 or FF00/FF01/FF02 → enable notifications → request MTU 517
 * (best effort) → ready. Every GATT operation goes through [GattQueue].
 *
 * State changes and data are reported on the main thread, in order.
 */
@SuppressLint("MissingPermission") // NetumManager checks the connection permission first.
class BleLink(
    private val manager: NetumManager,
    private val device: BluetoothDevice,
) : Link {
    override val id: String = device.address
    override val transport = Transport.BLE
    override val name: String? = device.name

    @Volatile
    override var state = LinkState.DISCONNECTED
        private set

    private val main = Handler(Looper.getMainLooper())
    private val queue = GattQueue()
    private var gatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var connectSignal: CompletableDeferred<Int>? = null
    private var disconnectSignal: CompletableDeferred<Unit>? = null
    private var userDisconnecting = false
    private var gattDropped = false

    /** Connects and enables notifications. Throws `connection-failed` (status in details). */
    suspend fun connect(timeoutMs: Long) {
        setState(LinkState.CONNECTING, userInitiated = true)
        try {
            withTimeout(timeoutMs) {
                var status = openGatt()
                if (status == STATUS_133) {
                    // Seen on the Android 10 tablet on the first connect after launch (A4.13).
                    closeGatt()
                    delay(RETRY_DELAY_MS)
                    status = openGatt()
                }
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    throw NetumError(NetumError.CONNECTION_FAILED, "Connect failed (status $status)", status)
                }
                setUp()
            }
        } catch (e: TimeoutCancellationException) {
            finish(userInitiated = false, platformCode = null, message = "Connect timed out")
            throw NetumError(NetumError.CONNECTION_FAILED, "Connect timed out")
        } catch (e: NetumError) {
            finish(userInitiated = false, platformCode = e.details as? Int, message = e.message)
            throw if (e.code == NetumError.CONNECTION_FAILED) {
                e
            } else {
                NetumError(NetumError.CONNECTION_FAILED, e.message ?: "Connect failed", e.details)
            }
        } catch (e: SecurityException) {
            finish(userInitiated = false, platformCode = null, message = e.message)
            throw NetumError(NetumError.PERMISSION_DENIED, e.message ?: "Missing permission")
        }
        setState(LinkState.CONNECTED, userInitiated = true)
    }

    override suspend fun write(bytes: ByteArray) {
        val gatt = readyGatt()
        val characteristic = writeCharacteristic
            ?: throw NetumError(NetumError.NOT_CONNECTED, "$id is not ready")
        val status = queue.run<Int>(GattOp.WRITE, OP_TIMEOUT_MS) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(
                    characteristic,
                    bytes,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                ) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                @Suppress("DEPRECATION")
                characteristic.value = bytes
                @Suppress("DEPRECATION")
                gatt.writeCharacteristic(characteristic)
            }
        }
        if (status != BluetoothGatt.GATT_SUCCESS) {
            throw NetumError(NetumError.CONNECTION_FAILED, "Write failed (status $status)", status)
        }
    }

    suspend fun readCharacteristic(serviceUuid: UUID, characteristicUuid: UUID): ByteArray {
        val gatt = readyGatt()
        val characteristic = gatt.getService(serviceUuid)?.getCharacteristic(characteristicUuid)
            ?: throw NetumError(NetumError.INVALID_ARGUMENT, "No characteristic $characteristicUuid")
        val (status, value) = queue.run<Pair<Int, ByteArray>>(GattOp.READ, OP_TIMEOUT_MS) {
            gatt.readCharacteristic(characteristic)
        }
        if (status != BluetoothGatt.GATT_SUCCESS) {
            throw NetumError(NetumError.CONNECTION_FAILED, "Read failed (status $status)", status)
        }
        return value
    }

    suspend fun readRssi(): Int {
        val gatt = readyGatt()
        val (status, rssi) = queue.run<Pair<Int, Int>>(GattOp.READ_RSSI, OP_TIMEOUT_MS) {
            gatt.readRemoteRssi()
        }
        if (status != BluetoothGatt.GATT_SUCCESS) {
            throw NetumError(NetumError.CONNECTION_FAILED, "RSSI read failed (status $status)", status)
        }
        return rssi
    }

    override suspend fun disconnect() {
        val gatt = gatt ?: return
        userDisconnecting = true
        setState(LinkState.DISCONNECTING, userInitiated = true)
        val signal = CompletableDeferred<Unit>().also { disconnectSignal = it }
        gatt.disconnect()
        withTimeoutOrNull(DISCONNECT_TIMEOUT_MS) { signal.await() }
        finish(userInitiated = true, platformCode = null, message = null)
    }

    override fun close() {
        closeGatt()
        state = LinkState.DISCONNECTED
    }

    // region Connect steps

    private suspend fun openGatt(): Int {
        val signal = CompletableDeferred<Int>().also { connectSignal = it }
        gatt = device.connectGatt(manager.context, false, callback, BluetoothDevice.TRANSPORT_LE)
            ?: throw NetumError(NetumError.CONNECTION_FAILED, "connectGatt returned null")
        return try {
            signal.await()
        } finally {
            connectSignal = null
        }
    }

    private suspend fun setUp() {
        val gatt = gatt ?: throw NetumError(NetumError.CONNECTION_FAILED, "Link dropped")

        val discovered = queue.run<Int>(GattOp.DISCOVER_SERVICES, OP_TIMEOUT_MS) {
            gatt.discoverServices()
        }
        if (discovered != BluetoothGatt.GATT_SUCCESS) {
            throw NetumError(NetumError.CONNECTION_FAILED, "Service discovery failed ($discovered)", discovered)
        }

        val (notify, write) = BleUuids.VARIANTS.firstNotNullOfOrNull { (service, notify, write) ->
            val s = gatt.getService(service) ?: return@firstNotNullOfOrNull null
            val n = s.getCharacteristic(notify) ?: return@firstNotNullOfOrNull null
            val w = s.getCharacteristic(write) ?: return@firstNotNullOfOrNull null
            n to w
        } ?: throw NetumError(NetumError.CONNECTION_FAILED, "No NETUM data service (FFF0 or FF00)")
        writeCharacteristic = write

        gatt.setCharacteristicNotification(notify, true)
        val descriptor = notify.getDescriptor(BleUuids.CCCD)
            ?: throw NetumError(NetumError.CONNECTION_FAILED, "Notify characteristic has no CCCD")
        val cccd = queue.run<Int>(GattOp.WRITE_DESCRIPTOR, OP_TIMEOUT_MS) {
            val value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = value
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(descriptor)
            }
        }
        if (cccd != BluetoothGatt.GATT_SUCCESS) {
            throw NetumError(NetumError.CONNECTION_FAILED, "Enabling notifications failed ($cccd)", cccd)
        }

        // Best effort: the DS5000 already negotiates MTU 200 itself (A4.3).
        try {
            queue.run<Int>(GattOp.REQUEST_MTU, OP_TIMEOUT_MS) { gatt.requestMtu(REQUESTED_MTU) }
        } catch (e: NetumError) {
            if (gattDropped) throw e
        }
    }

    // endregion

    private fun readyGatt(): BluetoothGatt {
        val gatt = gatt
        if (gatt == null || state != LinkState.CONNECTED) {
            throw NetumError(NetumError.NOT_CONNECTED, "$id is not connected")
        }
        return gatt
    }

    private fun setState(newState: LinkState, userInitiated: Boolean, platformCode: Int? = null, message: String? = null) {
        state = newState
        manager.emitLinkState(LinkEvent(id, transport, newState, userInitiated, platformCode, message))
    }

    /** Closes the GATT, releases the slot and reports the disconnect (once). */
    private fun finish(userInitiated: Boolean, platformCode: Int?, message: String?) {
        if (state == LinkState.DISCONNECTED) return
        closeGatt()
        manager.unregister(this)
        setState(LinkState.DISCONNECTED, userInitiated, platformCode, message)
    }

    private fun closeGatt() {
        gatt?.close()
        gatt = null
        writeCharacteristic = null
    }

    // Called on a binder thread. Connection changes are handled on the main thread, in order.
    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post { onConnectionChange(g, status, newState) }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            queue.complete(GattOp.DISCOVER_SERVICES, status)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            queue.complete(GattOp.WRITE_DESCRIPTOR, status)
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            queue.complete(GattOp.REQUEST_MTU, status)
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            queue.complete(GattOp.WRITE, status)
        }

        override fun onCharacteristicRead(
            g: BluetoothGatt,
            c: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            queue.complete(GattOp.READ, status to value)
        }

        @Deprecated("Called below API 33")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            queue.complete(GattOp.READ, status to (c.value ?: ByteArray(0)))
        }

        override fun onReadRemoteRssi(g: BluetoothGatt, rssi: Int, status: Int) {
            queue.complete(GattOp.READ_RSSI, status to rssi)
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            c: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            deliver(value.copyOf())
        }

        @Deprecated("Called below API 33")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            // Read immediately: the stack reuses the characteristic's buffer.
            @Suppress("DEPRECATION")
            deliver(c.value?.copyOf() ?: return)
        }
    }

    private fun deliver(bytes: ByteArray) {
        main.post { if (state == LinkState.CONNECTED) manager.emitData(id, bytes) }
    }

    private fun onConnectionChange(g: BluetoothGatt, status: Int, newState: Int) {
        if (g !== gatt) return // A GATT we already closed (e.g. before the 133 retry).
        when (newState) {
            BluetoothProfile.STATE_CONNECTED -> connectSignal?.complete(status)
            BluetoothProfile.STATE_DISCONNECTED -> {
                // Still opening: report the failure to the connect attempt.
                connectSignal?.let {
                    it.complete(if (status == BluetoothGatt.GATT_SUCCESS) STATUS_UNKNOWN else status)
                    return
                }
                gattDropped = true
                queue.fail(NetumError(NetumError.NOT_CONNECTED, "Link dropped (status $status)", status))
                disconnectSignal?.complete(Unit)
                // During setup the connect attempt reports the failure; during a user disconnect,
                // disconnect() does. Otherwise the scanner went away: 8 = link lost, 19 = remote
                // terminated (e.g. after a rename).
                if (state == LinkState.CONNECTED && !userDisconnecting) {
                    finish(userInitiated = false, platformCode = status, message = null)
                }
            }
        }
    }

    companion object {
        private const val STATUS_133 = 133
        private const val STATUS_UNKNOWN = -1
        private const val RETRY_DELAY_MS = 500L
        private const val OP_TIMEOUT_MS = 5_000L
        private const val DISCONNECT_TIMEOUT_MS = 2_000L
        private const val REQUESTED_MTU = 517
    }
}
