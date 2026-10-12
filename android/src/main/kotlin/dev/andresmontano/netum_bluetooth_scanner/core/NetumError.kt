package dev.andresmontano.netum_bluetooth_scanner.core

/**
 * An error with one of the codes shared with iOS (DEF-10 B4). The plugin layer turns it into a
 * Pigeon error with the same code; the Dart transport maps it to a NetumException.
 */
class NetumError(
    val code: String,
    message: String,
    val details: Any? = null,
) : Exception(message) {
    companion object {
        const val NOT_CONNECTED = "not-connected"
        const val CONNECTION_FAILED = "connection-failed"
        const val PERMISSION_DENIED = "permission-denied"
        const val BLUETOOTH_UNAVAILABLE = "bluetooth-unavailable"
        const val LOCATION_OFF = "location-off"
        const val UNSUPPORTED = "unsupported"
        const val BUSY = "busy"
        const val MAX_CONNECTIONS = "max-connections"
        const val INVALID_ARGUMENT = "invalid-argument"
        const val DISCOVERY_FAILED = "discovery-failed"
        const val UNIMPLEMENTED = "unimplemented"
    }
}
