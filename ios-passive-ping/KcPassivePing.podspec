require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

# Pod name must match Capacitor's fixName('kc-passive-ping') == 'KcPassivePing',
# which is what the generated Podfile references.
Pod::Spec.new do |s|
  s.name = 'KcPassivePing'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = 'https://keep-contact-mauve.vercel.app'
  s.author = package['author']
  s.source = { :git => 'https://github.com/vinz-astudio/keepcontect.git', :tag => package['version'] }
  s.source_files = 'ios/Sources/**/*.{swift,h,m}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
end
