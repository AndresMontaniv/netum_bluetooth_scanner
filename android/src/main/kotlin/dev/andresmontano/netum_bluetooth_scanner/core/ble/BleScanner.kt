package dev.andresmontano.netum_bluetooth_scanner.core.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import dev.andresmontano.netum_bluetooth_scanner.core.DiscoveredDevice
import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import dev.andresmontano.netum_bluetooth_scanner.core.Transport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * BLE discovery. Android silently stops delivering results to an app that starts more than 5 scans
 * in 30 s, so starts beyond that budget are postponed, never dropped (DEF-10 B5).
 */
@SuppressLint("MissingPermission") // Callers check permissions first (Permissions.ensure).
class BleScanner(
    private val adapter: BluetoothAdapter,
    private val scope: CoroutineScope,
    private val onDevice: (DiscoveredDevice) -> Unit,
    private val onError: (NetumError) -> Unit,
) {
    private val recentStarts = ArrayDeque<Long>()
    private val lastEmitted = HashMap<String, Long>()
    private var callback: ScanCallback? = null
    private var pendingStart: Job? = null
    private var timeout: Job? = null

    val isScanning: Boolean
        get() = callback != null || pendingStart != null

    fun start(filterNetum: Boolean, timeoutMs: Long) {
        stop()
        val wait = throttleDelayMs()
        if (wait > 0) {
            Log.i(TAG, "Scan start postponed ${wait}ms (Android allows 5 starts per 30 s)")
        }
        pendingStart = scope.launch {
            if (wait > 0) delay(wait)
            pendingStart = null
            startNow(filterNetum)
        }
        timeout = scope.launch {
            delay(wait + timeoutMs)
            stop()
        }
    }

    fun stop() {
        pendingStart?.cancel()
        pendingStart = null
        timeout?.cancel()
        timeout = null
        val current = callback ?: return
        callback = null
        try {
            adapter.bluetoothLeScanner?.stopScan(current)
        } catch (e: IllegalStateException) {
            // Bluetooth turned off: the scan is already gone.
        }
    }

    private fun startNow(filterNetum: Boolean) {
        val scanner = adapter.bluetoothLeScanner ?: run {
            onError(NetumError(NetumError.BLUETOOTH_UNAVAILABLE, "Bluetooth is off"))
            return
        }
        val filters = if (filterNetum) {
            BleUuids.SCAN_FILTER.map { ScanFilter.Builder().setServiceUuid(ParcelUuid(it)).build() }
        } else {
            emptyList()
        }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        // Results from a scan that was already stopped (or replaced) are dropped.
        val newCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (callback === this) report(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                if (callback === this) results.forEach(::report)
            }

            override fun onScanFailed(errorCode: Int) {
                if (callback !== this) return
                callback = null
                onError(NetumError(NetumError.DISCOVERY_FAILED, "BLE scan failed ($errorCode)", errorCode))
            }
        }
        lastEmitted.clear()
        recentStarts.addLast(SystemClock.elapsedRealtime())
        callback = newCallback
        scanner.startScan(filters, settings, newCallback)
    }

    // Results arrive many times per second per device; report the first sighting at once, then
    // at most once per second with the latest name and RSSI.
    private fun report(result: ScanResult) {
        val id = result.device.address
        val now = SystemClock.elapsedRealtime()
        val last = lastEmitted[id]
        if (last != null && now - last < REPORT_INTERVAL_MS) return
        lastEmitted[id] = now
        onDevice(
            DiscoveredDevice(
                id = id,
                transport = Transport.BLE,
                name = result.scanRecord?.deviceName ?: result.device.name,
                rssi = result.rssi,
                bonded = result.device.bondState == BluetoothDevice.BOND_BONDED,
                serviceUuids = result.scanRecord?.serviceUuids.orEmpty().map { it.uuid.toString().uppercase() },
            ),
        )
    }

    private fun throttleDelayMs(): Long {
        val now = SystemClock.elapsedRealtime()
        while (recentStarts.isNotEmpty() && now - recentStarts.first() >= THROTTLE_WINDOW_MS) {
            recentStarts.removeFirst()
        }
        if (recentStarts.size < THROTTLE_MAX_STARTS) return 0
        return recentStarts.first() + THROTTLE_WINDOW_MS + THROTTLE_MARGIN_MS - now
    }

    companion object {
        private const val TAG = "NetumBleScanner"
        private const val REPORT_INTERVAL_MS = 1000L
        private const val THROTTLE_MAX_STARTS = 5
        private const val THROTTLE_WINDOW_MS = 30_000L
        private const val THROTTLE_MARGIN_MS = 500L
    }
}
