package dev.andresmontano.netum_bluetooth_scanner.core.adapter

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.os.Build
import android.provider.Settings

enum class AdapterState { UNSUPPORTED, POWERED_OFF, POWERED_ON, LOCATION_SERVICES_OFF }

/** Reports the Bluetooth adapter state, including Location services where they block discovery. */
class AdapterMonitor(private val context: Context) {
    val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter

    private var receiver: BroadcastReceiver? = null
    private var lastEmitted: AdapterState? = null

    val isPoweredOn: Boolean
        get() = adapter?.state == BluetoothAdapter.STATE_ON

    val isLocationEnabled: Boolean
        get() {
            val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager?
                ?: return false
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                manager.isLocationEnabled
            } else {
                @Suppress("DEPRECATION")
                Settings.Secure.getInt(
                    context.contentResolver,
                    Settings.Secure.LOCATION_MODE,
                    Settings.Secure.LOCATION_MODE_OFF,
                ) != Settings.Secure.LOCATION_MODE_OFF
            }
        }

    val state: AdapterState
        get() = when {
            adapter == null -> AdapterState.UNSUPPORTED
            !isPoweredOn -> AdapterState.POWERED_OFF
            LOCATION_BLOCKS_DISCOVERY && !isLocationEnabled -> AdapterState.LOCATION_SERVICES_OFF
            else -> AdapterState.POWERED_ON
        }

    /** Emits the current state, then every change, on the main thread. */
    fun start(onChange: (AdapterState) -> Unit) {
        stop()
        emit(onChange)
        if (adapter == null) return

        val newReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                emit(onChange)
            }
        }
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(LocationManager.PROVIDERS_CHANGED_ACTION)
            addAction(LocationManager.MODE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(newReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(newReceiver, filter)
        }
        receiver = newReceiver
    }

    fun stop() {
        receiver?.let { context.unregisterReceiver(it) }
        receiver = null
        lastEmitted = null
    }

    // Transitional states (TURNING_ON/OFF) and repeated Location broadcasts map to the same
    // state; only report real changes.
    private fun emit(onChange: (AdapterState) -> Unit) {
        val current = state
        if (current == lastEmitted) return
        lastEmitted = current
        onChange(current)
    }

    companion object {
        /**
         * Whether Location services must be on for BLE discovery to return results. Certain up to
         * Android 11 (API 30). For Android 12+ (no `neverForLocation`) this is settled by
         * hardware test H2.2.
         */
        val LOCATION_BLOCKS_DISCOVERY: Boolean = Build.VERSION.SDK_INT <= Build.VERSION_CODES.R
    }
}
