package dev.andresmontano.netum_bluetooth_scanner.plugin

import dev.andresmontano.netum_bluetooth_scanner.core.ActiveLink
import dev.andresmontano.netum_bluetooth_scanner.core.DiscoveredDevice
import dev.andresmontano.netum_bluetooth_scanner.core.LinkEvent
import dev.andresmontano.netum_bluetooth_scanner.core.LinkState
import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import dev.andresmontano.netum_bluetooth_scanner.core.Transport
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.AdapterState
import dev.andresmontano.netum_bluetooth_scanner.generated.ActiveLinkMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.AdapterStateMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.DiscoveredDeviceMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.FlutterError
import dev.andresmontano.netum_bluetooth_scanner.generated.LinkStateMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.LinkStateMsgEvent
import dev.andresmontano.netum_bluetooth_scanner.generated.TransportMsg

internal fun Transport.toMsg() = when (this) {
    Transport.BLE -> TransportMsg.BLE
    Transport.SPP -> TransportMsg.SPP
}

internal fun TransportMsg.toCore() = when (this) {
    TransportMsg.BLE -> Transport.BLE
    TransportMsg.SPP -> Transport.SPP
}

internal fun LinkState.toMsg() = when (this) {
    LinkState.DISCONNECTED -> LinkStateMsg.DISCONNECTED
    LinkState.CONNECTING -> LinkStateMsg.CONNECTING
    LinkState.CONNECTED -> LinkStateMsg.CONNECTED
    LinkState.DISCONNECTING -> LinkStateMsg.DISCONNECTING
}

internal fun LinkEvent.toMsg() = LinkStateMsgEvent(
    id = id,
    transport = transport.toMsg(),
    state = state.toMsg(),
    platformCode = platformCode?.toLong(),
    userInitiated = userInitiated,
    message = message,
)

internal fun DiscoveredDevice.toMsg() = DiscoveredDeviceMsg(
    id = id,
    transport = transport.toMsg(),
    name = name,
    rssi = rssi?.toLong(),
    bonded = bonded,
    serviceUuids = serviceUuids,
)

internal fun ActiveLink.toMsg() = ActiveLinkMsg(id = id, transport = transport.toMsg(), name = name)

internal fun AdapterState.toMsg(): AdapterStateMsg = when (this) {
    AdapterState.UNSUPPORTED -> AdapterStateMsg.UNSUPPORTED
    AdapterState.POWERED_OFF -> AdapterStateMsg.POWERED_OFF
    AdapterState.POWERED_ON -> AdapterStateMsg.POWERED_ON
}

internal fun NetumError.toFlutterError() = FlutterError(code, message, details)

/** Runs [block], turning core errors into Pigeon errors with the shared codes. */
internal inline fun <T> bridge(block: () -> T): T =
    try {
        block()
    } catch (e: NetumError) {
        throw e.toFlutterError()
    } catch (e: SecurityException) {
        throw FlutterError(NetumError.PERMISSION_DENIED, e.message, null)
    }
