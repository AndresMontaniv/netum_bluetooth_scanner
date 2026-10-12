package dev.andresmontano.netum_bluetooth_scanner.core.adapter

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build

enum class AdapterState { UNSUPPORTED, POWERED_OFF, POWERED_ON }

/**
 * Reports the Bluetooth adapter's power state. Location-services and permission
 * states are added in S2.
 */
class AdapterMonitor(private val context: Context) {
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter

    private var receiver: BroadcastReceiver? = null
    private var lastEmitted: AdapterState? = null

    val state: AdapterState
        get() = adapter?.let { map(it.state) } ?: AdapterState.UNSUPPORTED

    /** Emits the current state, then every change, on the main thread. */
    fun start(onChange: (AdapterState) -> Unit) {
        stop()
        emit(state, onChange)
        if (adapter == null) return

        val newReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val raw = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                emit(map(raw), onChange)
            }
        }
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
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

    // TURNING_ON / TURNING_OFF both map to POWERED_OFF; only report real changes.
    private fun emit(state: AdapterState, onChange: (AdapterState) -> Unit) {
        if (state == lastEmitted) return
        lastEmitted = state
        onChange(state)
    }

    private fun map(raw: Int): AdapterState =
        if (raw == BluetoothAdapter.STATE_ON) AdapterState.POWERED_ON else AdapterState.POWERED_OFF
}
