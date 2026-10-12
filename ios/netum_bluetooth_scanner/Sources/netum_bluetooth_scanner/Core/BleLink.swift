import CoreBluetooth
import Foundation

/// One BLE connection. Connect sequence: connect → discover FFF0/FF00/180A → pick the data variant
/// → discover its characteristics (and 180A's) → enable notifications → ready.
///
/// CoreBluetooth has no connect timeout, so one is enforced here. Public methods may be called from
/// any thread; all state is confined to the manager's queue (also the delegate queue).
final class BleLink: NSObject, CBPeripheralDelegate {
  let id: String
  let peripheral: CBPeripheral
  private unowned let manager: NetumManager
  private let central: CBCentralManager
  private var queue: DispatchQueue { manager.queue }

  private(set) var state: LinkState = .disconnected
  var name: String? { peripheral.name }

  private var connectCompletion: ((Result<Void, NetumError>) -> Void)?
  private var connectTimeout: DispatchWorkItem?
  private var disconnectCompletion: (() -> Void)?
  private var userDisconnecting = false
  private var dataService: CBUUID?
  private var notifyCharacteristic: CBCharacteristic?
  private var writeCharacteristic: CBCharacteristic?
  private var pendingWrites: [(Result<Void, NetumError>) -> Void] = []
  private var pendingReads: [CBUUID: [(Result<Data, NetumError>) -> Void]] = [:]
  private var pendingRssi: [(Result<Int, NetumError>) -> Void] = []

  init(manager: NetumManager, central: CBCentralManager, peripheral: CBPeripheral) {
    self.id = peripheral.identifier.uuidString
    self.manager = manager
    self.central = central
    self.peripheral = peripheral
    super.init()
  }

  // MARK: - Commands (any thread)

  /// Called on the manager queue.
  func connect(timeoutMs: Int, completion: @escaping (Result<Void, NetumError>) -> Void) {
    connectCompletion = completion
    setState(.connecting, userInitiated: true)
    peripheral.delegate = self
    central.connect(peripheral)
    let timeout = DispatchWorkItem { [weak self] in
      self?.failConnect(.connectionFailed("Connect timed out"))
    }
    connectTimeout = timeout
    queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeout)
  }

  func write(_ bytes: Data, completion: @escaping (Result<Void, NetumError>) -> Void) {
    queue.async {
      guard self.state == .connected, let characteristic = self.writeCharacteristic else {
        completion(.failure(.notConnected(self.id)))
        return
      }
      self.pendingWrites.append(completion)
      self.peripheral.writeValue(bytes, for: characteristic, type: .withResponse)
    }
  }

  func read(
    service: CBUUID, characteristic: CBUUID,
    completion: @escaping (Result<Data, NetumError>) -> Void
  ) {
    queue.async {
      guard self.state == .connected else {
        completion(.failure(.notConnected(self.id)))
        return
      }
      guard
        let target = self.peripheral.services?.first(where: { $0.uuid == service })?
          .characteristics?.first(where: { $0.uuid == characteristic })
      else {
        completion(.failure(.invalidArgument("No characteristic \(characteristic.uuidString)")))
        return
      }
      self.pendingReads[characteristic, default: []].append(completion)
      self.peripheral.readValue(for: target)
    }
  }

  func readRssi(completion: @escaping (Result<Int, NetumError>) -> Void) {
    queue.async {
      guard self.state == .connected else {
        completion(.failure(.notConnected(self.id)))
        return
      }
      self.pendingRssi.append(completion)
      self.peripheral.readRSSI()
    }
  }

  func disconnect(completion: @escaping () -> Void) {
    queue.async {
      switch self.state {
      case .disconnected:
        completion()
      case .connecting:
        self.userDisconnecting = true
        self.failConnect(.connectionFailed("Cancelled"))
        completion()
      case .connected, .disconnecting:
        self.userDisconnecting = true
        self.disconnectCompletion = completion
        self.setState(.disconnecting, userInitiated: true)
        self.central.cancelPeripheralConnection(self.peripheral)
        // didDisconnect normally arrives first; don't wait forever.
        self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
          self?.close(userInitiated: true, platformCode: nil)
        }
      }
    }
  }

  // MARK: - Central callbacks (manager queue)

  func didConnect() {
    peripheral.discoverServices(BleUuids.servicesToDiscover)
  }

  func didFailToConnect(_ error: Error?) {
    let code = (error as NSError?)?.code
    failConnect(.connectionFailed(error?.localizedDescription ?? "Connect failed", code: code))
  }

  func didDisconnect(_ error: Error?) {
    let code = (error as NSError?)?.code
    if connectCompletion != nil {
      failConnect(.connectionFailed("Link dropped while connecting", code: code))
    } else {
      // CBError 6 = connection timeout (link lost), 7 = the scanner closed it.
      close(userInitiated: userDisconnecting, platformCode: userDisconnecting ? nil : code)
    }
  }

  func handleBluetoothUnavailable() {
    if connectCompletion != nil {
      failConnect(.bluetoothUnavailable("Bluetooth turned off"))
    } else {
      close(userInitiated: false, platformCode: nil)
    }
  }

  // MARK: - CBPeripheralDelegate (manager queue)

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error {
      failConnect(.connectionFailed("Service discovery failed: \(error.localizedDescription)"))
      return
    }
    let services = peripheral.services ?? []
    guard let variant = StateMapping.dataVariant(in: services.map(\.uuid)),
      let service = services.first(where: { $0.uuid == variant.service })
    else {
      failConnect(.connectionFailed("No NETUM data service (FFF0 or FF00)"))
      return
    }
    dataService = variant.service
    peripheral.discoverCharacteristics([variant.notify, variant.write], for: service)
    if let info = services.first(where: { $0.uuid == BleUuids.deviceInformation }) {
      peripheral.discoverCharacteristics(nil, for: info)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard service.uuid == dataService, connectCompletion != nil else { return }
    if let error {
      failConnect(.connectionFailed("Characteristic discovery failed: \(error.localizedDescription)"))
      return
    }
    guard let variant = StateMapping.dataVariant(in: [service.uuid]),
      let notify = service.characteristics?.first(where: { $0.uuid == variant.notify }),
      let write = service.characteristics?.first(where: { $0.uuid == variant.write })
    else {
      failConnect(.connectionFailed("NETUM characteristics missing"))
      return
    }
    notifyCharacteristic = notify
    writeCharacteristic = write
    peripheral.setNotifyValue(true, for: notify)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard characteristic.uuid == notifyCharacteristic?.uuid, connectCompletion != nil else { return }
    if let error {
      failConnect(.connectionFailed("Enabling notifications failed: \(error.localizedDescription)"))
      return
    }
    connectTimeout?.cancel()
    connectTimeout = nil
    let completion = connectCompletion
    connectCompletion = nil
    setState(.connected, userInitiated: true)
    completion?(.success(()))
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if characteristic.uuid == notifyCharacteristic?.uuid {
      guard error == nil, state == .connected, let value = characteristic.value else { return }
      manager.emitData(id: id, bytes: value)
      return
    }
    guard var waiting = pendingReads[characteristic.uuid], !waiting.isEmpty else { return }
    let completion = waiting.removeFirst()
    pendingReads[characteristic.uuid] = waiting
    if let error {
      completion(.failure(.connectionFailed("Read failed: \(error.localizedDescription)")))
    } else {
      completion(.success(characteristic.value ?? Data()))
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard !pendingWrites.isEmpty else { return }
    let completion = pendingWrites.removeFirst()
    if let error {
      completion(.failure(.connectionFailed("Write failed: \(error.localizedDescription)")))
    } else {
      completion(.success(()))
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    guard !pendingRssi.isEmpty else { return }
    let completion = pendingRssi.removeFirst()
    if let error {
      completion(.failure(.connectionFailed("RSSI read failed: \(error.localizedDescription)")))
    } else {
      completion(.success(RSSI.intValue))
    }
  }

  // MARK: - Helpers (manager queue)

  private func setState(
    _ newState: LinkState, userInitiated: Bool, platformCode: Int? = nil, message: String? = nil
  ) {
    state = newState
    manager.emitLinkState(
      LinkEvent(
        id: id, state: newState, userInitiated: userInitiated, platformCode: platformCode,
        message: message))
  }

  private func failConnect(_ error: NetumError) {
    guard let completion = connectCompletion else { return }
    connectCompletion = nil
    connectTimeout?.cancel()
    connectTimeout = nil
    central.cancelPeripheralConnection(peripheral)
    state = .disconnected
    manager.linkClosed(self)
    setState(
      .disconnected, userInitiated: userDisconnecting, platformCode: error.details as? Int,
      message: error.message)
    completion(.failure(error))
  }

  /// Reports the disconnect once, fails pending operations and releases the slot.
  private func close(userInitiated: Bool, platformCode: Int?) {
    guard state != .disconnected else { return }
    let error = NetumError.notConnected(id)
    pendingWrites.forEach { $0(.failure(error)) }
    pendingWrites.removeAll()
    pendingReads.values.flatMap { $0 }.forEach { $0(.failure(error)) }
    pendingReads.removeAll()
    pendingRssi.forEach { $0(.failure(error)) }
    pendingRssi.removeAll()
    manager.linkClosed(self)
    setState(.disconnected, userInitiated: userInitiated, platformCode: platformCode)
    disconnectCompletion?()
    disconnectCompletion = nil
  }
}
