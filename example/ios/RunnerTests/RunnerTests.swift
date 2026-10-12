import CoreBluetooth
import XCTest

@testable import netum_bluetooth_scanner

/// Unit tests for the plugin's pure iOS mappings (DEF-10 B8).
class RunnerTests: XCTestCase {

  func testAdapterStateBeforeTheManagerExistsNeverPrompts() {
    XCTAssertEqual(
      StateMapping.adapterState(managerState: nil, authorization: .notDetermined), .unknown)
    XCTAssertEqual(
      StateMapping.adapterState(managerState: nil, authorization: .denied), .unauthorized)
    XCTAssertEqual(
      StateMapping.adapterState(managerState: nil, authorization: .restricted), .unauthorized)
    XCTAssertEqual(
      StateMapping.adapterState(managerState: nil, authorization: .allowedAlways), .unknown)
  }

  func testAdapterStateFromTheManager() {
    let cases: [(CBManagerState, AdapterState)] = [
      (.poweredOn, .poweredOn), (.poweredOff, .poweredOff), (.unauthorized, .unauthorized),
      (.unsupported, .unsupported), (.unknown, .unknown), (.resetting, .unknown),
    ]
    for (managerState, expected) in cases {
      XCTAssertEqual(
        StateMapping.adapterState(managerState: managerState, authorization: .allowedAlways),
        expected)
    }
  }

  func testPermissionResults() {
    XCTAssertEqual(StateMapping.permissionResult(.allowedAlways), .granted)
    XCTAssertEqual(StateMapping.permissionResult(.notDetermined), .denied)
    XCTAssertEqual(StateMapping.permissionResult(.denied), .permanentlyDenied)
    XCTAssertEqual(StateMapping.permissionResult(.restricted), .permanentlyDenied)
  }

  func testDataVariantPrefersFFF0() {
    let both = StateMapping.dataVariant(
      in: [CBUUID(string: "180A"), CBUUID(string: "FF00"), CBUUID(string: "FFF0")])
    XCTAssertEqual(both?.notify, CBUUID(string: "FFF1"))
    XCTAssertEqual(both?.write, CBUUID(string: "FFF2"))

    let alternative = StateMapping.dataVariant(in: [CBUUID(string: "FF00")])
    XCTAssertEqual(alternative?.notify, CBUUID(string: "FF01"))

    XCTAssertNil(StateMapping.dataVariant(in: [CBUUID(string: "180A")]))
  }
}
