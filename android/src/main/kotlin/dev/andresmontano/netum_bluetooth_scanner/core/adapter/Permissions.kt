package dev.andresmontano.netum_bluetooth_scanner.core.adapter

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import kotlinx.coroutines.CompletableDeferred

enum class PermissionScope { DISCOVERY, CONNECTION }

enum class PermissionResult { GRANTED, DENIED, PERMANENTLY_DENIED, NOT_REQUIRED }

/**
 * Runtime permissions per scope (DEF-10 B5). Discovery always needs location: `neverForLocation`
 * would hide the scanners' iBeacon advertisements. Android 12+ ignores a FINE request without
 * COARSE, so both are requested together.
 */
class Permissions(private val context: Context) {
    /** The current Activity, needed to prompt. Set by the plugin layer. */
    var activity: Activity? = null

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var pendingRequest: CompletableDeferred<Unit>? = null
    private var pendingEnable: CompletableDeferred<Boolean>? = null

    fun required(scope: PermissionScope): List<String> = when (scope) {
        PermissionScope.DISCOVERY ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                listOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                )
            } else {
                listOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                )
            }
        PermissionScope.CONNECTION ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                listOf(Manifest.permission.BLUETOOTH_CONNECT)
            } else {
                emptyList()
            }
    }

    fun missing(scope: PermissionScope): List<String> =
        required(scope).filter { !isGranted(it) }

    fun check(scope: PermissionScope): PermissionResult {
        if (required(scope).isEmpty()) return PermissionResult.NOT_REQUIRED
        val missing = missing(scope)
        return when {
            missing.isEmpty() -> PermissionResult.GRANTED
            missing.any { isPermanentlyDenied(it) } -> PermissionResult.PERMANENTLY_DENIED
            else -> PermissionResult.DENIED
        }
    }

    /** Throws `permission-denied` listing what [scope] is missing. */
    fun ensure(scope: PermissionScope) {
        val missing = missing(scope)
        if (missing.isNotEmpty()) {
            throw NetumError(NetumError.PERMISSION_DENIED, "Missing permissions", missing)
        }
    }

    suspend fun request(scope: PermissionScope): PermissionResult {
        val missing = missing(scope)
        if (missing.isEmpty()) return check(scope)
        val activity = activity
            ?: throw NetumError(NetumError.UNSUPPORTED, "No Activity to show the permission dialog")
        if (pendingRequest != null) {
            throw NetumError(NetumError.BUSY, "A permission request is already running")
        }

        val deferred = CompletableDeferred<Unit>()
        pendingRequest = deferred
        prefs.edit().apply { missing.forEach { putBoolean(KEY_REQUESTED + it, true) } }.apply()
        try {
            activity.requestPermissions(missing.toTypedArray(), REQUEST_PERMISSIONS)
            deferred.await()
        } finally {
            pendingRequest = null
        }
        return check(scope)
    }

    /** Shows the system "turn Bluetooth on" dialog. Returns whether Bluetooth is on afterwards. */
    suspend fun requestEnableBluetooth(isPoweredOn: () -> Boolean): Boolean {
        if (isPoweredOn()) return true
        ensure(PermissionScope.CONNECTION)
        val activity = activity
            ?: throw NetumError(NetumError.UNSUPPORTED, "No Activity to show the Bluetooth dialog")
        if (pendingEnable != null) {
            throw NetumError(NetumError.BUSY, "A Bluetooth enable request is already running")
        }

        val deferred = CompletableDeferred<Boolean>()
        pendingEnable = deferred
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                REQUEST_ENABLE_BLUETOOTH,
            )
            return deferred.await()
        } finally {
            pendingEnable = null
        }
    }

    /** Forwarded from the Activity. Returns whether the result was ours. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_PERMISSIONS) return false
        pendingRequest?.complete(Unit)
        return true
    }

    /** Forwarded from the Activity. Returns whether the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_ENABLE_BLUETOOTH) return false
        pendingEnable?.complete(resultCode == Activity.RESULT_OK)
        return true
    }

    /** The Activity went away mid-request: let waiting callers re-check. */
    fun onActivityDetached() {
        activity = null
        pendingRequest?.complete(Unit)
        pendingEnable?.complete(false)
    }

    private fun isGranted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    // Before the first request, shouldShowRequestPermissionRationale is also false, so a
    // "requested before" flag tells the two cases apart.
    private fun isPermanentlyDenied(permission: String): Boolean {
        val activity = activity ?: return false
        return prefs.getBoolean(KEY_REQUESTED + permission, false) &&
            !activity.shouldShowRequestPermissionRationale(permission)
    }

    companion object {
        private const val PREFS = "dev.andresmontano.netum_bluetooth_scanner"
        private const val KEY_REQUESTED = "requested."
        const val REQUEST_PERMISSIONS = 0x4E54
        const val REQUEST_ENABLE_BLUETOOTH = 0x4E55
    }
}
