import CoreBluetooth

/// Pure mappings, unit-tested in example/ios/RunnerTests.
enum StateMapping {
  /// Adapter state. Before the central manager exists, only the authorization is known; reading it
  /// never creates the manager, so it never shows the permission prompt.
  static func adapterState(
    managerState: CBManagerState?, authorization: CBManagerAuthorization
  ) -> AdapterState {
    guard let managerState else {
      switch authorization {
      case .denied, .restricted: return .unauthorized
      default: return .unknown
      }
    }
    switch managerState {
    case .unsupported: return .unsupported
    case .unauthorized: return .unauthorized
    case .poweredOff: return .poweredOff
    case .poweredOn: return .poweredOn
    case .unknown, .resetting: return .unknown
    @unknown default: return .unknown
    }
  }

  /// `.notDetermined` → denied (asking will show the prompt); denied/restricted → permanently
  /// denied (only Settings can change it).
  static func permissionResult(_ authorization: CBManagerAuthorization) -> PermissionResult {
    switch authorization {
    case .allowedAlways: return .granted
    case .denied, .restricted: return .permanentlyDenied
    case .notDetermined: return .denied
    @unknown default: return .denied
    }
  }

  /// The data service, notify and write characteristics to use, in preference order
  /// (FFF0/FFF1/FFF2, then FF00/FF01/FF02).
  static func dataVariant(in services: [CBUUID]) -> (service: CBUUID, notify: CBUUID, write: CBUUID)? {
    BleUuids.variants.first { services.contains($0.service) }
  }
}

enum BleUuids {
  /// Advertised services that mark a NETUM scanner.
  static let scanFilter = [CBUUID(string: "FFF0"), CBUUID(string: "FF00"), CBUUID(string: "18F0")]

  static let variants: [(service: CBUUID, notify: CBUUID, write: CBUUID)] = [
    (CBUUID(string: "FFF0"), CBUUID(string: "FFF1"), CBUUID(string: "FFF2")),
    (CBUUID(string: "FF00"), CBUUID(string: "FF01"), CBUUID(string: "FF02")),
  ]

  static let deviceInformation = CBUUID(string: "180A")

  /// Services discovered on connect: both data variants and Device Information.
  static let servicesToDiscover = variants.map(\.service) + [deviceInformation]
}
