# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-http-record-modifier"
  spec.version       = "0.0.3"
  spec.authors       = ["Augusto Nishi"]
  spec.email         = ["augusto.nishi@gmail.com"]
  spec.summary       = %q{fluentd filter plugin for modifing record based on a HTTP request}
  spec.description   = %q{fluentd filter plugin for modifing record based on a HTTP request}
  spec.homepage      = "http://github.com/DEVTecnologia/fluent-plugin-http-record-modifier"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "fluentd"

end
