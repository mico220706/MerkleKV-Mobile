Pod::Spec.new do |s|
  s.name             = 'merkle_kv_mobile'
  s.version          = '0.0.1'
  s.summary          = 'A distributed key-value store for mobile devices.'
  s.description      = <<-DESC
A distributed key-value store optimized for mobile edge devices with MQTT-based communication.
                       DESC
  s.homepage         = 'https://github.com/AI-Decenter/MerkleKV-Mobile'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MerkleKV-Mobile Contributors' => 'contact@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '10.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
