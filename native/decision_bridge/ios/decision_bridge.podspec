Pod::Spec.new do |s|
  s.name = 'decision_bridge'
  s.version = '0.1.0'
  s.summary = 'Local d1 decision runtime'
  s.description = 'On-device d1 inference with CPU and Metal support.'
  s.homepage = 'https://github.com/ggml-org/llama.cpp'
  s.license = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author = 'D1 Lab contributors'
  s.source = { :path => '.' }
  s.source_files = 'Classes/*.swift'
  s.vendored_frameworks = 'DecisionRuntime.xcframework'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'
  s.swift_version = '5.0'
  s.frameworks = 'Metal', 'MetalKit', 'Accelerate', 'Foundation'
  s.libraries = 'c++'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64' }
end
