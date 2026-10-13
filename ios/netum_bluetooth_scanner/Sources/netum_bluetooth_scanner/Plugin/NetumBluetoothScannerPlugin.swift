import CoreBluetooth
import Flutter
import UIKit

/// Pigeon host implementation. Delegates to the app-scoped `NetumManager`; links outlive Dart hot
/// restarts.
public class NetumBluetoothScannerPlugin: NSObject, FlutterPlugin, NetumHostApi, NetumEvents {
  private let manager = NetumManager.shared

  // One sink per stream. A new listen (e.g. after a Dart hot restart) replaces the old sink.
  fileprivate var adapterSink: PigeonEventSink<AdapterStateMsg>?
  fileprivate var discoveriesSink: PigeonEventSink<DiscoveredDeviceMsg>?
  fileprivate var linkStatesSink: PigeonEventSink<LinkStateMsgEvent>?
  fileprivate var dataSink: PigeonEventSink<DataMsg>?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let instance = NetumBluetoothScannerPlugin()
    instance.manager.events = instance
    NetumHostApiSetup.setUp(binaryMessenger: messenger, api: instance)
    AdapterStatesStreamHandler.register(with: messenger, streamHandler: AdapterStates(instance))
    DiscoveriesStreamHandler.register(with: messenger, streamHandler: Discoveries(instance))
    LinkStatesStreamHandler.register(with: messenger, streamHandler: LinkStates(instance))
    DataStreamHandler.register(with: messenger, streamHandler: DataStream(instance))
  }

  // MARK: - NetumEvents (main thread)

  func onAdapterState(_ state: AdapterState) {
    adapterSink?.success(state.msg)
  }

  func onDiscovery(_ device: DiscoveredDevice) {
    discoveriesSink?.success(
      DiscoveredDeviceMsg(
        id: device.id, transport: .ble, name: device.name, rssi: Int64(device.rssi),
        bonded: false, serviceUuids: device.serviceUuids))
  }

  func onDiscoveryError(_ error: NetumError) {
    discoveriesSink?.error(code: error.code, message: error.message, details: error.details)
  }

  func onLinkState(_ event: LinkEvent) {
    linkStatesSink?.success(
      LinkStateMsgEvent(
        id: event.id, transport: .ble, state: event.state.msg,
        platformCode: event.platformCode.map(Int64.init), userInitiated: event.userInitiated,
        message: event.message))
  }

  func onData(id: String, bytes: Data, timestampMicros: Int64) {
    dataSink?.success(
      DataMsg(id: id, bytes: FlutterStandardTypedData(bytes: bytes), timestampMicros: timestampMicros))
  }

  // MARK: - NetumHostApi

  func initialize() throws -> [ActiveLinkMsg] {
    manager.initialize().map { ActiveLinkMsg(id: $0.id, transport: .ble, name: $0.name) }
  }

  func adapterState() throws -> AdapterStateMsg { manager.adapterState.msg }

  func checkPermissions(scope: PermissionScopeMsg) throws -> PermissionResultMsg {
    manager.checkPermissions().msg
  }

  func requestPermissions(scope: PermissionScopeMsg) async throws -> PermissionResultMsg {
    await withCheckedContinuation { continuation in
      manager.requestPermissions { continuation.resume(returning: $0.msg) }
    }
  }

  /// iOS has no "turn Bluetooth on" dialog.
  func requestEnableBluetooth() async throws -> Bool { false }

  func startDiscovery(options: DiscoveryOptionsMsg) throws {
    guard options.transport == .ble else { throw NetumError.unsupported("SPP is Android only").pigeon }
    try bridge { try manager.startDiscovery(filterNetum: options.filterNetum, timeoutMs: Int(options.timeoutMs)) }
  }

  func stopDiscovery() throws { manager.stopDiscovery() }

  func bondedDevices() throws -> [DiscoveredDeviceMsg] { [] }

  func connect(id: String, options: ConnectOptionsMsg) async throws {
    guard options.transport == .ble else { throw NetumError.unsupported("SPP is Android only").pigeon }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      manager.connect(id: id, timeoutMs: Int(options.timeoutMs), autoReconnect: options.autoReconnect) {
        continuation.resume(with: $0.mapError(\.pigeon))
      }
    }
  }

  func disconnect(id: String) async throws {
    let link = try bridge { try manager.link(id) }
    await withCheckedContinuation { continuation in
      link.disconnect { continuation.resume() }
    }
  }

  func setAutoReconnect(id: String, enabled: Bool) throws {
    try bridge { try manager.setAutoReconnect(id: id, enabled: enabled) }
  }

  func write(id: String, bytes: FlutterStandardTypedData) async throws {
    let link = try bridge { try manager.link(id) }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      link.write(bytes.data) { continuation.resume(with: $0.mapError(\.pigeon)) }
    }
  }

  func readCharacteristic(id: String, serviceUuid: String, characteristicUuid: String) async throws
    -> FlutterStandardTypedData
  {
    let link = try bridge { try manager.link(id) }
    let data = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Data, Error>) in
      link.read(service: CBUUID(string: serviceUuid), characteristic: CBUUID(string: characteristicUuid)) {
        continuation.resume(with: $0.mapError(\.pigeon))
      }
    }
    return FlutterStandardTypedData(bytes: data)
  }

  func readRssi(id: String) async throws -> Int64 {
    let link = try bridge { try manager.link(id) }
    let rssi = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Int, Error>) in
      link.readRssi { continuation.resume(with: $0.mapError(\.pigeon)) }
    }
    return Int64(rssi)
  }

  func startSppListener(timeoutMs: Int64) throws {
    throw NetumError.unsupported("SPP is Android only").pigeon
  }

  func stopSppListener() throws {
    throw NetumError.unsupported("SPP is Android only").pigeon
  }

  private func bridge<T>(_ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch let error as NetumError {
      throw error.pigeon
    }
  }
}

// MARK: - Stream handlers

private final class AdapterStates: AdapterStatesStreamHandler {
  private weak var plugin: NetumBluetoothScannerPlugin?

  init(_ plugin: NetumBluetoothScannerPlugin) { self.plugin = plugin }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<AdapterStateMsg>) {
    plugin?.adapterSink = sink
    NetumManager.shared.startAdapterUpdates()
  }

  override func onCancel(withArguments arguments: Any?) {
    plugin?.adapterSink = nil
    NetumManager.shared.stopAdapterUpdates()
  }
}

private final class Discoveries: DiscoveriesStreamHandler {
  private weak var plugin: NetumBluetoothScannerPlugin?

  init(_ plugin: NetumBluetoothScannerPlugin) { self.plugin = plugin }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<DiscoveredDeviceMsg>) {
    plugin?.discoveriesSink = sink
  }

  override func onCancel(withArguments arguments: Any?) { plugin?.discoveriesSink = nil }
}

private final class LinkStates: LinkStatesStreamHandler {
  private weak var plugin: NetumBluetoothScannerPlugin?

  init(_ plugin: NetumBluetoothScannerPlugin) { self.plugin = plugin }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<LinkStateMsgEvent>) {
    plugin?.linkStatesSink = sink
  }

  override func onCancel(withArguments arguments: Any?) { plugin?.linkStatesSink = nil }
}

private final class DataStream: DataStreamHandler {
  private weak var plugin: NetumBluetoothScannerPlugin?

  init(_ plugin: NetumBluetoothScannerPlugin) { self.plugin = plugin }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<DataMsg>) {
    plugin?.dataSink = sink
  }

  override func onCancel(withArguments arguments: Any?) { plugin?.dataSink = nil }
}

// MARK: - Mappings

extension NetumError {
  fileprivate var pigeon: PigeonError { PigeonError(code: code, message: message, details: details) }
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

extension PermissionResult {
  fileprivate var msg: PermissionResultMsg {
    switch self {
    case .granted: return .granted
    case .denied: return .denied
    case .permanentlyDenied: return .permanentlyDenied
    case .notRequired: return .notRequired
    }
  }
}

extension LinkState {
  fileprivate var msg: LinkStateMsg {
    switch self {
    case .disconnected: return .disconnected
    case .connecting: return .connecting
    case .connected: return .connected
    case .disconnecting: return .disconnecting
    }
  }
}
