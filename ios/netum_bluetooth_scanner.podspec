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
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'netum_bluetooth_scanner/Sources/netum_bluetooth_scanner/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'netum_bluetooth_scanner_privacy' => ['netum_bluetooth_scanner/Sources/netum_bluetooth_scanner/PrivacyInfo.xcprivacy']}
end
