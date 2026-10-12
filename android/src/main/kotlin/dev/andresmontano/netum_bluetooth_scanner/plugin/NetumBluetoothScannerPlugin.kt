package dev.andresmontano.netum_bluetooth_scanner.plugin

import dev.andresmontano.netum_bluetooth_scanner.core.adapter.AdapterMonitor
import dev.andresmontano.netum_bluetooth_scanner.core.adapter.AdapterState
import dev.andresmontano.netum_bluetooth_scanner.generated.ActiveLinkMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.AdapterStateMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.AdapterStatesStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.ConnectOptionsMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.DataStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.DiscoveredDeviceMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.DiscoveriesStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.DiscoveryOptionsMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.FlutterError
import dev.andresmontano.netum_bluetooth_scanner.generated.LinkStatesStreamHandler
import dev.andresmontano.netum_bluetooth_scanner.generated.NetumHostApi
import dev.andresmontano.netum_bluetooth_scanner.generated.PermissionResultMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.PermissionScopeMsg
import dev.andresmontano.netum_bluetooth_scanner.generated.PigeonEventSink
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger

/** Pigeon host implementation. Only the adapter state is real so far; the rest lands in S2 and S5. */
class NetumBluetoothScannerPlugin : FlutterPlugin, NetumHostApi {
    private var messenger: BinaryMessenger? = null
    private var adapterMonitor: AdapterMonitor? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        this.messenger = messenger
        adapterMonitor = AdapterMonitor(binding.applicationContext)

        NetumHostApi.setUp(messenger, this)
        AdapterStatesStreamHandler.register(messenger, AdapterStates())
        DiscoveriesStreamHandler.register(messenger, object : DiscoveriesStreamHandler() {})
        LinkStatesStreamHandler.register(messenger, object : LinkStatesStreamHandler() {})
        DataStreamHandler.register(messenger, object : DataStreamHandler() {})
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        messenger?.let { NetumHostApi.setUp(it, null) }
        messenger = null
        adapterMonitor?.stop()
        adapterMonitor = null
    }

    private inner class AdapterStates : AdapterStatesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<AdapterStateMsg>) {
            adapterMonitor?.start { sink.success(it.toMsg()) }
        }

        override fun onCancel(p0: Any?) {
            adapterMonitor?.stop()
        }
    }

    override fun initialize(): List<ActiveLinkMsg> = emptyList()

    override fun adapterState(): AdapterStateMsg =
        adapterMonitor?.state?.toMsg() ?: AdapterStateMsg.UNKNOWN

    override fun checkPermissions(scope: PermissionScopeMsg): PermissionResultMsg =
        unimplemented("checkPermissions")

    override suspend fun requestPermissions(scope: PermissionScopeMsg): PermissionResultMsg =
        unimplemented("requestPermissions")

    override suspend fun requestEnableBluetooth(): Boolean = unimplemented("requestEnableBluetooth")

    override fun startDiscovery(options: DiscoveryOptionsMsg) = unimplemented("startDiscovery")

    override fun stopDiscovery() = unimplemented("stopDiscovery")

    override fun bondedDevices(): List<DiscoveredDeviceMsg> = unimplemented("bondedDevices")

    override suspend fun connect(id: String, options: ConnectOptionsMsg) = unimplemented("connect")

    override suspend fun disconnect(id: String) = unimplemented("disconnect")

    override fun setAutoReconnect(id: String, enabled: Boolean) = unimplemented("setAutoReconnect")

    override suspend fun write(id: String, bytes: ByteArray) = unimplemented("write")

    override suspend fun readCharacteristic(
        id: String,
        serviceUuid: String,
        characteristicUuid: String
    ): ByteArray = unimplemented("readCharacteristic")

    override suspend fun readRssi(id: String): Long = unimplemented("readRssi")

    override fun startSppListener(timeoutMs: Long) = unimplemented("startSppListener")

    override fun stopSppListener() = unimplemented("stopSppListener")

    private fun unimplemented(method: String): Nothing =
        throw FlutterError("unimplemented", "$method is not implemented yet")
}

private fun AdapterState.toMsg(): AdapterStateMsg = when (this) {
    AdapterState.UNSUPPORTED -> AdapterStateMsg.UNSUPPORTED
    AdapterState.POWERED_OFF -> AdapterStateMsg.POWERED_OFF
    AdapterState.POWERED_ON -> AdapterStateMsg.POWERED_ON
}
