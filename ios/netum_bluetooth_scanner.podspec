#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint netum_bluetooth_scanner.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'netum_bluetooth_scanner'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for NETUM Bluetooth barcode scanners (BLE on Android & iOS, SPP on Android): scan streams, multi-device, commands.'
  s.description      = <<-DESC
Flutter plugin for NETUM Bluetooth barcode scanners (BLE on Android & iOS, SPP on Android): scan streams, multi-device, commands.
                       DESC
  s.homepage         = 'https://github.com/AndresMontaniv/netum_bluetooth_scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Andres Montano'
  s.source           = { :path => '.' }
  s.source_files = 'netum_bluetooth_scanner/Sources/netum_bluetooth_scanner/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'

  s.resource_bundles = {'netum_bluetooth_scanner_privacy' => ['netum_bluetooth_scanner/Sources/netum_bluetooth_scanner/PrivacyInfo.xcprivacy']}
end
