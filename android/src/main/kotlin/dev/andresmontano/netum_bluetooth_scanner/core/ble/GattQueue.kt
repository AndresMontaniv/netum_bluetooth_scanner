package dev.andresmontano.netum_bluetooth_scanner.core.ble

import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

/** The GATT operations whose callbacks the queue waits for. */
enum class GattOp { DISCOVER_SERVICES, WRITE_DESCRIPTOR, REQUEST_MTU, WRITE, READ, READ_RSSI }

/**
 * Runs GATT operations strictly one at a time. Android silently drops an operation issued before
 * the previous one's callback, so every operation waits for its own callback (or a timeout).
 * A callback for a different operation (e.g. a late one after a timeout) is ignored.
 */
class GattQueue {
    private val mutex = Mutex()
    private var pending: Pending? = null

    private class Pending(val op: GattOp, val result: CompletableDeferred<Any?>)

    private class Box(val value: Any?)

    /**
     * Starts [op] with [start] (which returns false if Android refused it) and waits for its
     * callback's value.
     */
    suspend fun <T> run(op: GattOp, timeoutMs: Long, start: () -> Boolean): T = mutex.withLock {
        val current = Pending(op, CompletableDeferred())
        pending = current
        try {
            if (!start()) {
                throw NetumError(NetumError.CONNECTION_FAILED, "GATT ${op.name} could not start")
            }
            // withTimeoutOrNull only absorbs its own timeout; an outer cancellation (e.g. the
            // connect timeout) still propagates.
            val box = withTimeoutOrNull(timeoutMs) { Box(current.result.await()) }
                ?: throw NetumError(NetumError.CONNECTION_FAILED, "GATT ${op.name} timed out")
            @Suppress("UNCHECKED_CAST")
            box.value as T
        } finally {
            if (pending === current) pending = null
        }
    }

    /** Called from a GATT callback. Thread-safe. */
    fun complete(op: GattOp, value: Any?) {
        val current = pending ?: return
        if (current.op == op) current.result.complete(value)
    }

    /** Fails the running operation, e.g. when the link drops. Thread-safe. */
    fun fail(error: Throwable) {
        pending?.result?.completeExceptionally(error)
    }
}
