import Flutter
import UIKit

/// Pigeon host implementation. Only the adapter state is real so far; BLE lands in S3.
public class NetumBluetoothScannerPlugin: NSObject, FlutterPlugin, NetumHostApi {
  private let adapterMonitor = AdapterMonitor()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let instance = NetumBluetoothScannerPlugin()
    NetumHostApiSetup.setUp(binaryMessenger: messenger, api: instance)
    AdapterStatesStreamHandler.register(
      with: messenger, streamHandler: AdapterStates(monitor: instance.adapterMonitor))
    DiscoveriesStreamHandler.register(with: messenger, streamHandler: DiscoveriesStreamHandler())
    LinkStatesStreamHandler.register(with: messenger, streamHandler: LinkStatesStreamHandler())
    DataStreamHandler.register(with: messenger, streamHandler: DataStreamHandler())
  }

  func initialize() throws -> [ActiveLinkMsg] { [] }

  func adapterState() throws -> AdapterStateMsg { adapterMonitor.state.msg }

  func checkPermissions(scope: PermissionScopeMsg) throws -> PermissionResultMsg {
    throw unimplemented("checkPermissions")
  }

  func requestPermissions(scope: PermissionScopeMsg) async throws -> PermissionResultMsg {
    throw unimplemented("requestPermissions")
  }

  func requestEnableBluetooth() async throws -> Bool { throw unimplemented("requestEnableBluetooth") }

  func startDiscovery(options: DiscoveryOptionsMsg) throws { throw unimplemented("startDiscovery") }

  func stopDiscovery() throws { throw unimplemented("stopDiscovery") }

  func bondedDevices() throws -> [DiscoveredDeviceMsg] { [] }

  func connect(id: String, options: ConnectOptionsMsg) async throws { throw unimplemented("connect") }

  func disconnect(id: String) async throws { throw unimplemented("disconnect") }

  func setAutoReconnect(id: String, enabled: Bool) throws { throw unimplemented("setAutoReconnect") }

  func write(id: String, bytes: FlutterStandardTypedData) async throws { throw unimplemented("write") }

  func readCharacteristic(id: String, serviceUuid: String, characteristicUuid: String) async throws
    -> FlutterStandardTypedData
  {
    throw unimplemented("readCharacteristic")
  }

  func readRssi(id: String) async throws -> Int64 { throw unimplemented("readRssi") }

  func startSppListener(timeoutMs: Int64) throws { throw unsupported("startSppListener") }

  func stopSppListener() throws { throw unsupported("stopSppListener") }

  private func unimplemented(_ method: String) -> PigeonError {
    PigeonError(code: "unimplemented", message: "\(method) is not implemented yet", details: nil)
  }

  private func unsupported(_ method: String) -> PigeonError {
    PigeonError(code: "unsupported", message: "\(method) is not available on iOS", details: nil)
  }
}

private final class AdapterStates: AdapterStatesStreamHandler {
  private let monitor: AdapterMonitor

  init(monitor: AdapterMonitor) {
    self.monitor = monitor
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<AdapterStateMsg>) {
    monitor.start { sink.success($0.msg) }
  }

  override func onCancel(withArguments arguments: Any?) {
    monitor.stop()
  }
}

extension AdapterState {
  fileprivate var msg: AdapterStateMsg {
    switch self {
    case .unknown: return .unknown
    case .unsupported: return .unsupported
    case .unauthorized: return .unauthorized
    case .poweredOff: return .poweredOff
    case .poweredOn: return .poweredOn
    }
  }
}
