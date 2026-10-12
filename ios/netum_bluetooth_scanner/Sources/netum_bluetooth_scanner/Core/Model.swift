import Foundation

enum Transport { case ble, spp }

enum LinkState { case disconnected, connecting, connected, disconnecting }

enum AdapterState { case unknown, unsupported, unauthorized, poweredOff, poweredOn }

enum PermissionResult { case granted, denied, permanentlyDenied, notRequired }

struct LinkEvent {
  let id: String
  let state: LinkState
  let userInitiated: Bool
  var platformCode: Int? = nil
  var message: String? = nil
}

struct DiscoveredDevice {
  let id: String
  let name: String?
  let rssi: Int
  let serviceUuids: [String]
}

struct ActiveLink {
  let id: String
  let name: String?
}

/// An error with one of the codes shared with Android (DEF-10 B4).
struct NetumError: Error {
  let code: String
  let message: String
  var details: (any Sendable)? = nil

  static func notConnected(_ id: String) -> NetumError {
    NetumError(code: "not-connected", message: "\(id) is not connected")
  }

  static func connectionFailed(_ message: String, code: Int? = nil) -> NetumError {
    NetumError(code: "connection-failed", message: message, details: code)
  }

  static let permissionDenied = NetumError(
    code: "permission-denied", message: "Bluetooth permission denied", details: ["bluetooth"])

  static func bluetoothUnavailable(_ message: String) -> NetumError {
    NetumError(code: "bluetooth-unavailable", message: message)
  }

  static func unsupported(_ message: String) -> NetumError {
    NetumError(code: "unsupported", message: message)
  }

  static func invalidArgument(_ message: String) -> NetumError {
    NetumError(code: "invalid-argument", message: message)
  }

  static func busy(_ message: String) -> NetumError {
    NetumError(code: "busy", message: message)
  }

  static let maxConnections = NetumError(
    code: "max-connections", message: "At most \(NetumManager.maxLinks) connections")

  static func unimplemented(_ method: String) -> NetumError {
    NetumError(code: "unimplemented", message: "\(method) is not implemented yet")
  }
}

/// Receives everything the core reports. Always called on the main thread.
protocol NetumEvents: AnyObject {
  func onAdapterState(_ state: AdapterState)
  func onDiscovery(_ device: DiscoveredDevice)
  func onDiscoveryError(_ error: NetumError)
  func onLinkState(_ event: LinkEvent)
  func onData(id: String, bytes: Data, timestampMicros: Int64)
}
