import CoreBluetooth
import Foundation

/// Owner of the single `CBCentralManager` and every link. All CoreBluetooth work runs on [queue];
/// events reach [events] on the main thread, in order.
///
/// Creating the central manager while Bluetooth authorization is undetermined shows the one-time
/// system prompt, so it is created only by `requestPermissions`, `startDiscovery` or `connect`, or
/// right away when authorization is already granted (DEF-10 B6). Never while denied.
final class NetumManager: NSObject, CBCentralManagerDelegate {
  static let shared = NetumManager()
  static let maxLinks = 7

  let queue = DispatchQueue(label: "dev.andresmontano.netum_bluetooth_scanner.central")

  /// The attached Flutter side. Main thread only.
  weak var events: NetumEvents?

  // Everything below is confined to `queue`.
  private var central: CBCentralManager?
  private var links: [String: BleLink] = [:]
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var stateWaiters: [(CBManagerState) -> Void] = []
  private var reportsAdapterState = false
  private var lastAdapterState: AdapterState?
  private var scanGeneration = 0
  private var scanTimeout: DispatchWorkItem?
  private var lastReported: [UUID: Date] = [:]

  // MARK: - Adapter and permissions

  var adapterState: AdapterState { queue.sync { currentAdapterState() } }

  func checkPermissions() -> PermissionResult {
    StateMapping.permissionResult(CBManager.authorization)
  }

  /// Returns the links that are ready (re-adopted after a Dart hot restart).
  func initialize() -> [ActiveLink] {
    queue.sync {
      createCentralIfAuthorized()
      return links.values.filter { $0.state == .connected }.map {
        ActiveLink(id: $0.id, name: $0.name)
      }
    }
  }

  /// Starts reporting adapter states: the current one now, then every change.
  func startAdapterUpdates() {
    queue.async {
      self.reportsAdapterState = true
      self.lastAdapterState = nil
      self.createCentralIfAuthorized()
      self.reportAdapterState()
    }
  }

  func stopAdapterUpdates() {
    queue.async { self.reportsAdapterState = false }
  }

  /// Shows the system prompt if Bluetooth authorization is undetermined, then reports the result.
  func requestPermissions(completion: @escaping (PermissionResult) -> Void) {
    queue.async {
      guard CBManager.authorization == .notDetermined else {
        self.createCentralIfAuthorized()
        completion(self.checkPermissions())
        return
      }
      self.createCentral()
      self.whenStateKnown { _ in completion(self.checkPermissions()) }
    }
  }

  // MARK: - Discovery

  func startDiscovery(filterNetum: Bool, timeoutMs: Int) throws {
    try queue.sync {
      if let error = knownBlocker() { throw error }
      stopScanLocked()
      let generation = scanGeneration
      whenReady { result in
        guard generation == self.scanGeneration else { return }  // Stopped meanwhile.
        switch result {
        case .failure(let error):
          self.emit { $0.onDiscoveryError(error) }
        case .success(let central):
          self.lastReported.removeAll()
          central.scanForPeripherals(
            withServices: filterNetum ? BleUuids.scanFilter : nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
          let timeout = DispatchWorkItem { [weak self] in self?.stopScanLocked() }
          self.scanTimeout = timeout
          self.queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeout)
        }
      }
    }
  }

  func stopDiscovery() {
    queue.async { self.stopScanLocked() }
  }

  private func stopScanLocked() {
    scanGeneration += 1
    scanTimeout?.cancel()
    scanTimeout = nil
    if central?.state == .poweredOn, central?.isScanning == true {
      central?.stopScan()
    }
  }

  // MARK: - Links

  func connect(
    id: String, timeoutMs: Int, autoReconnect: Bool,
    completion: @escaping (Result<Void, NetumError>) -> Void
  ) {
    queue.async {
      guard let uuid = UUID(uuidString: id) else {
        completion(.failure(.invalidArgument("Not a peripheral identifier: \(id)")))
        return
      }
      if let error = self.knownBlocker() {
        completion(.failure(error))
        return
      }
      self.whenReady { result in
        switch result {
        case .failure(let error):
          completion(.failure(error))
        case .success(let central):
          if let existing = self.links[id] {
            if existing.state == .connected {
              existing.setAutoReconnect(autoReconnect)
              completion(.success(()))
            } else {
              completion(.failure(.busy("\(id) is already connecting")))
            }
            return
          }
          guard self.links.count < Self.maxLinks else {
            completion(.failure(.maxConnections))
            return
          }
          // A saved device connects without a scan: CoreBluetooth still knows it by identifier.
          guard let peripheral = self.peripherals[uuid]
            ?? central.retrievePeripherals(withIdentifiers: [uuid]).first
          else {
            completion(.failure(.connectionFailed("Unknown scanner \(id); discover it first")))
            return
          }
          let link = BleLink(manager: self, central: central, peripheral: peripheral)
          self.links[id] = link
          link.connect(timeoutMs: timeoutMs, autoReconnect: autoReconnect, completion: completion)
        }
      }
    }
  }

  func link(_ id: String) throws -> BleLink {
    try queue.sync {
      guard let link = links[id] else { throw NetumError.notConnected(id) }
      return link
    }
  }

  func setAutoReconnect(id: String, enabled: Bool) throws {
    try link(id).setAutoReconnect(enabled)
  }

  /// Called by a link once it is fully closed.
  func linkClosed(_ link: BleLink) {
    if links[link.id] === link { links.removeValue(forKey: link.id) }
  }

  // MARK: - Events (from `queue`)

  func emit(_ deliver: @escaping (NetumEvents) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let events = self?.events else { return }
      deliver(events)
    }
  }

  func emitLinkState(_ event: LinkEvent) {
    emit { $0.onLinkState(event) }
  }

  func emitData(id: String, bytes: Data) {
    let timestamp = Int64(Date().timeIntervalSince1970 * 1_000_000)
    emit { $0.onData(id: id, bytes: bytes, timestampMicros: timestamp) }
  }

  // MARK: - Central manager (on `queue`)

  private func currentAdapterState() -> AdapterState {
    StateMapping.adapterState(managerState: central?.state, authorization: CBManager.authorization)
  }

  private func createCentralIfAuthorized() {
    if CBManager.authorization == .allowedAlways { createCentral() }
  }

  private func createCentral() {
    guard central == nil else { return }
    central = CBCentralManager(
      delegate: self, queue: queue,
      options: [CBCentralManagerOptionShowPowerAlertKey: false])
  }

  /// An error that is certain without creating the manager (so without prompting).
  private func knownBlocker() -> NetumError? {
    switch CBManager.authorization {
    case .denied, .restricted: return .permissionDenied
    default: break
    }
    switch central?.state {
    case .poweredOff: return .bluetoothUnavailable("Bluetooth is off", state: "poweredOff")
    case .unsupported: return .bluetoothUnavailable("Bluetooth is not supported", state: "unsupported")
    default: return nil
    }
  }

  /// Creates the manager if needed (may prompt) and calls back once Bluetooth is usable.
  private func whenReady(_ completion: @escaping (Result<CBCentralManager, NetumError>) -> Void) {
    createCentral()
    whenStateKnown { state in
      guard let central = self.central else { return }
      switch state {
      case .poweredOn: completion(.success(central))
      case .unauthorized: completion(.failure(.permissionDenied))
      case .unsupported: completion(.failure(.bluetoothUnavailable("Bluetooth is not supported", state: "unsupported")))
      default: completion(.failure(.bluetoothUnavailable("Bluetooth is off", state: "poweredOff")))
      }
    }
  }

  /// Calls back once the manager reports a definite state (after the prompt, if one is shown).
  private func whenStateKnown(_ completion: @escaping (CBManagerState) -> Void) {
    guard let state = central?.state else { return }
    if state == .unknown || state == .resetting {
      stateWaiters.append(completion)
    } else {
      completion(state)
    }
  }

  private func reportAdapterState() {
    guard reportsAdapterState else { return }
    let state = currentAdapterState()
    guard state != lastAdapterState else { return }
    lastAdapterState = state
    emit { $0.onAdapterState(state) }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    reportAdapterState()
    if central.state != .unknown && central.state != .resetting {
      let waiters = stateWaiters
      stateWaiters.removeAll()
      waiters.forEach { $0(central.state) }
    }
    if central.state == .poweredOn {
      links.values.forEach { $0.rearmIfReconnecting() }
    } else {
      // iOS drops every connection and scan when Bluetooth goes away, without per-peripheral
      // callbacks.
      scanGeneration += 1
      scanTimeout?.cancel()
      for link in Array(links.values) { link.handleBluetoothUnavailable() }
    }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    let id = peripheral.identifier
    peripherals[id] = peripheral
    // Duplicates are allowed for RSSI updates; report each device at most once per second.
    let now = Date()
    if let last = lastReported[id], now.timeIntervalSince(last) < 1 { return }
    lastReported[id] = now
    let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let device = DiscoveredDevice(
      id: id.uuidString,
      name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
      rssi: RSSI.intValue,
      serviceUuids: uuids.map(\.uuidString))
    emit { $0.onDiscovery(device) }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    links[peripheral.identifier.uuidString]?.didConnect()
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    links[peripheral.identifier.uuidString]?.didFailToConnect(error)
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    links[peripheral.identifier.uuidString]?.didDisconnect(error)
  }
}
