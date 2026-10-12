package dev.andresmontano.netum_bluetooth_scanner.core.ble

import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GattQueueTest {
    @Test
    fun `operations run one at a time in order`() = runTest {
        val queue = GattQueue()
        val started = mutableListOf<String>()

        val first = async { queue.run<Int>(GattOp.WRITE, 1000) { started += "first"; true } }
        val second = async { queue.run<Int>(GattOp.WRITE, 1000) { started += "second"; true } }
        runCurrent()
        assertEquals(listOf("first"), started)

        queue.complete(GattOp.WRITE, 1)
        runCurrent()
        assertEquals(listOf("first", "second"), started)

        queue.complete(GattOp.WRITE, 2)
        assertEquals(1, first.await())
        assertEquals(2, second.await())
    }

    @Test
    fun `an operation times out with connection-failed and the queue moves on`() = runTest {
        val queue = GattQueue()
        var secondStarted = false

        val first = async {
            runCatching { queue.run<Int>(GattOp.REQUEST_MTU, 500) { true } }
        }
        val second = async { queue.run<Int>(GattOp.WRITE, 1000) { secondStarted = true; true } }
        advanceTimeBy(499)
        runCurrent()
        assertFalse(secondStarted)

        advanceTimeBy(2)
        runCurrent()
        val error = first.await().exceptionOrNull()
        assertTrue(error is NetumError && error.code == NetumError.CONNECTION_FAILED)
        assertTrue(secondStarted)

        queue.complete(GattOp.WRITE, 7)
        assertEquals(7, second.await())
    }

    @Test
    fun `a callback for another operation is ignored`() = runTest {
        val queue = GattQueue()
        val write = async { queue.run<Int>(GattOp.WRITE, 1000) { true } }
        runCurrent()

        // A late MTU callback (after its operation timed out) must not resolve the write.
        queue.complete(GattOp.REQUEST_MTU, 99)
        runCurrent()
        assertFalse(write.isCompleted)

        queue.complete(GattOp.WRITE, 0)
        assertEquals(0, write.await())
    }

    @Test
    fun `a refused start fails immediately`() = runTest {
        val queue = GattQueue()
        val error = assertFailsWith<NetumError> { queue.run<Int>(GattOp.READ, 1000) { false } }
        assertEquals(NetumError.CONNECTION_FAILED, error.code)
    }

    @Test
    fun `fail rejects the running operation`() = runTest {
        val queue = GattQueue()
        val write = async { runCatching { queue.run<Int>(GattOp.WRITE, 1000) { true } } }
        runCurrent()

        queue.fail(NetumError(NetumError.NOT_CONNECTED, "dropped"))

        val error = write.await().exceptionOrNull()
        assertTrue(error is NetumError && error.code == NetumError.NOT_CONNECTED)
    }
}
