import CoreBluetooth
import Foundation

enum AdapterState {
  case unknown, unsupported, unauthorized, poweredOff, poweredOn
}

/// Reports the Bluetooth adapter state. The `CBCentralManager` is created lazily by `start`,
/// because creating it is what shows the system Bluetooth permission prompt.
final class AdapterMonitor: NSObject, CBCentralManagerDelegate {
  private let queue = DispatchQueue(label: "dev.andresmontano.netum_bluetooth_scanner.central")
  private var central: CBCentralManager?
  private var lastState: AdapterState = .unknown
  private var onChange: ((AdapterState) -> Void)?

  /// Current state. Before the manager exists it is derived from the authorization alone,
  /// so reading it never triggers the permission prompt. Main thread only.
  var state: AdapterState {
    if central != nil { return lastState }
    switch CBManager.authorization {
    case .denied, .restricted: return .unauthorized
    default: return .unknown
    }
  }

  /// Emits the current state, then every change, on the main thread.
  func start(onChange: @escaping (AdapterState) -> Void) {
    self.onChange = onChange
    onChange(state)
    if central == nil {
      central = CBCentralManager(
        delegate: self, queue: queue,
        options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
  }

  func stop() {
    onChange = nil
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = Self.map(central.state)
    DispatchQueue.main.async {
      guard state != self.lastState else { return }
      self.lastState = state
      self.onChange?(state)
    }
  }

  private static func map(_ state: CBManagerState) -> AdapterState {
    switch state {
    case .unsupported: return .unsupported
    case .unauthorized: return .unauthorized
    case .poweredOff: return .poweredOff
    case .poweredOn: return .poweredOn
    case .unknown, .resetting: return .unknown
    @unknown default: return .unknown
    }
  }
}
