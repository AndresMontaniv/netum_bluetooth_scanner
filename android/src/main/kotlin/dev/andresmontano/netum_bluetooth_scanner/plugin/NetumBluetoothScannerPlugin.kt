package dev.andresmontano.netum_bluetooth_scanner.plugin

import dev.andresmontano.netum_bluetooth_scanner.core.DiscoveredDevice
import dev.andresmontano.netum_bluetooth_scanner.core.LinkEvent
import dev.andresmontano.netum_bluetooth_scanner.core.NetumError
import dev.andresmontano.netum_bluetooth_scanner.core.NetumEvents
import dev.andresmontano.netum_bluetooth_scanner.core.NetumManager
import dev.andresmontano.netum_bluetooth_scanner.generated.ActiveLinkMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.AdapterStateMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.AdapterStatesStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.ConnectOptionsMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.DataMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.DataStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.DiscoveredDeviceMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.DiscoveriesStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.DiscoveryOptionsMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.LinkStateMsgEvent
import dev.andresmontano.netum_bluetooth_scanner.generated.LinkStatesStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.NetumHostApi
import dev.andresmontano.netum_bluetooth_scanner.generated.PermissionResultMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.PermissionScopeMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.PigeonEventSink
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger

/**
 * Pigeon host implementation. Delegates to the app-scoped [NetumManager]; links outlive the
 * engine, so detaching only drops the event sinks.
 */
class NetumBluetoothScannerPlugin : FlutterPlugin, NetumHostApi, NetumEvents {
    private var messenger: BinaryMessenger? = null
    private lateinit var manager: NetumManager

    // One sink per stream. A new listen (e.g. after a Dart hot restart) replaces the old sink.
    private var discoveriesSink: PigeonEventSink<DiscoveredDeviceMsg>? = null
    private var linkStatesSink: PigeonEventSink<LinkStateMsgEvent>? = null
    private var dataSink: PigeonEventSink<DataMsg>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        this.messenger = messenger
        manager = NetumManager.get(binding.applicationContext)
        manager.events = this

        NetumHostApi.setUp(messenger, this)
        AdapterStatesStreamHandler.register(messenger, AdapterStates())
        DiscoveriesStreamHandler.register(messenger, object : DiscoveriesStreamHandler() {
            override fun onListen(p0: Any?, sink: PigeonEventSink<DiscoveredDeviceMsg>) {
                discoveriesSink = sink
            }

            override fun onCancel(p0: Any?) {
                discoveriesSink = null
            }
        })
        LinkStatesStreamHandler.register(messenger, object : LinkStatesStreamHandler() {
            override fun onListen(p0: Any?, sink: PigeonEventSink<LinkStateMsgEvent>) {
                linkStatesSink = sink
            }

            override fun onCancel(p0: Any?) {
                linkStatesSink = null
            }
        })
        DataStreamHandler.register(messenger, object : DataStreamHandler() {
            override fun onListen(p0: Any?, sink: PigeonEventSink<DataMsg>) {
                dataSink = sink
            }

            override fun onCancel(p0: Any?) {
                dataSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        messenger?.let { NetumHostApi.setUp(it, null) }
        messenger = null
        if (manager.events === this) manager.events = null
        manager.adapterMonitor.stop()
        discoveriesSink = null
        linkStatesSink = null
        dataSink = null
    }

    // region NetumEvents (main thread)

    override fun onDiscovery(device: DiscoveredDevice) {
        discoveriesSink?.success(device.toMsg())
    }

    override fun onDiscoveryError(error: NetumError) {
        discoveriesSink?.error(error.code, error.message, error.details)
    }

    override fun onLinkState(event: LinkEvent) {
        linkStatesSink?.success(event.toMsg())
    }

    override fun onData(id: String, bytes: ByteArray, timestampMicros: Long) {
        dataSink?.success(DataMsg(id = id, bytes = bytes, timestampMicros = timestampMicros))
    }

    // endregion

    private inner class AdapterStates : AdapterStatesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<AdapterStateMsg>) {
            manager.adapterMonitor.start { sink.success(it.toMsg()) }
        }

        override fun onCancel(p0: Any?) {
            manager.adapterMonitor.stop()
        }
    }

    // region NetumHostApi

    override fun initialize(): List<ActiveLinkMsg> = manager.activeLinks().map { it.toMsg() }

    override fun adapterState(): AdapterStateMsg = manager.adapterMonitor.state.toMsg()

    override fun checkPermissions(scope: PermissionScopeMsg): PermissionResultMsg =
        unimplemented("checkPermissions")

    override suspend fun requestPermissions(scope: PermissionScopeMsg): PermissionResultMsg =
        unimplemented("requestPermissions")

    override suspend fun requestEnableBluetooth(): Boolean = unimplemented("requestEnableBluetooth")

    override fun startDiscovery(options: DiscoveryOptionsMsg) = unimplemented("startDiscovery")

    override fun stopDiscovery() = unimplemented("stopDiscovery")

    override fun bondedDevices(): List<DiscoveredDeviceMsg> = unimplemented("bondedDevices")

    override suspend fun connect(id: String, options: ConnectOptionsMsg) = unimplemented("connect")

    override suspend fun disconnect(id: String) = bridge {
        val link = manager.link(id) ?: throw NetumError(NetumError.NOT_CONNECTED, "$id is not connected")
        link.disconnect()
    }

    override fun setAutoReconnect(id: String, enabled: Boolean) = unimplemented("setAutoReconnect")

    override suspend fun write(id: String, bytes: ByteArray) = bridge {
        val link = manager.link(id) ?: throw NetumError(NetumError.NOT_CONNECTED, "$id is not connected")
        link.write(bytes)
    }

    override suspend fun readCharacteristic(
        id: String,
        serviceUuid: String,
        characteristicUuid: String,
    ): ByteArray = unimplemented("readCharacteristic")

    override suspend fun readRssi(id: String): Long = unimplemented("readRssi")

    override fun startSppListener(timeoutMs: Long) = unimplemented("startSppListener")

    override fun stopSppListener() = unimplemented("stopSppListener")

    // endregion

    private fun unimplemented(method: String): Nothing =
        throw NetumError(NetumError.UNIMPLEMENTED, "$method is not implemented yet").toFlutterError()
}
