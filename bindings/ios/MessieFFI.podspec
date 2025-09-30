Pod::Spec.new do |spec|
  spec.name          = 'MessieFFI'
  spec.version       = '0.1.0'
  spec.summary       = 'Rust FFI bindings for Messie generated with flutter_rust_bridge.'
  spec.homepage      = 'https://github.com/messie/messenger'
  spec.license       = { :type => 'Apache-2.0' }
  spec.author        = { 'Messie Team' => 'team@messie.dev' }
  spec.source        = { :path => '.' }
  spec.vendored_frameworks = 'rust/MessieFFI.xcframework'
  spec.prepare_command = <<-CMD
    set -euo pipefail
    SCRIPT_DIR="$(pwd)"
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    "$PROJECT_ROOT/bindings/ios/build.sh"
  CMD
  spec.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -l"c++"',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'armv7',
  }
end
