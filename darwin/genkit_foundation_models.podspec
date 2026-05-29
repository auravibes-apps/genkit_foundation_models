Pod::Spec.new do |s|
  s.name             = 'genkit_foundation_models'
  s.version          = '0.0.1'
  s.summary          = 'Genkit provider bridge for Apple Foundation Models.'
  s.description      = 'A Flutter plugin that bridges Genkit Dart models to Apple Foundation Models on Darwin platforms.'
  s.homepage         = 'https://github.com/davidlondono/genkit_foundation_models'
  s.license          = { :type => 'MIT' }
  s.author           = { 'genkit_foundation_models' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'genkit_foundation_models/Sources/genkit_foundation_models/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '26.0'
  s.osx.deployment_target = '26.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
