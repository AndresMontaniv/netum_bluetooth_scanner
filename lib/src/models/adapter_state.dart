/// The state of the phone's Bluetooth adapter.
enum AdapterState {
  /// Not known yet (for example before the first platform update).
  unknown,

  /// The device has no usable Bluetooth hardware.
  unsupported,

  /// The app is not allowed to use Bluetooth.
  unauthorized,

  /// Bluetooth is turned off.
  poweredOff,

  /// Bluetooth is on and usable.
  poweredOn,

  /// Bluetooth is on, but Location services are off, which blocks discovery
  /// on Android.
  locationServicesOff,
}
