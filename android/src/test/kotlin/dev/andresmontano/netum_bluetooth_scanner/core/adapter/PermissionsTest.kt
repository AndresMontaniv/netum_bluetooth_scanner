package dev.andresmontano.netum_bluetooth_scanner.core.adapter

import kotlin.test.Test
import kotlin.test.assertEquals

class PermissionsTest {
    @Test
    fun `names the permissions in a SecurityException message`() {
        val message = "Need android.permission.BLUETOOTH_SCAN permission for " +
            "AttributionSource { uid = 10321 }: Starting discovery."
        assertEquals(listOf("android.permission.BLUETOOTH_SCAN"), Permissions.namedIn(message))
    }

    @Test
    fun `lists each permission once`() {
        val message = "android.permission.BLUETOOTH_CONNECT and android.permission.BLUETOOTH_CONNECT, " +
            "android.permission.BLUETOOTH_SCAN"
        assertEquals(
            listOf("android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_SCAN"),
            Permissions.namedIn(message),
        )
    }

    @Test
    fun `names nothing when the message has no permission`() {
        assertEquals(emptyList(), Permissions.namedIn("Permission denied"))
        assertEquals(emptyList(), Permissions.namedIn(null))
    }
}
