# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cached_enumeration/version'

Gem::Specification.new do |spec|
  spec.name          = "cached_enumeration"
  spec.version       = CachedEnumeration::VERSION
  spec.authors       = ["Peter Schrammel"]
  spec.email         = ["peter.schrammel@experteer.com"]
  spec.description   = %q{Cache nonchanging ActiveRecord models in memory}
  spec.summary       = %q{Cache nonchanging ActiveRecord models in memory}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec","~> 2.3"
  spec.add_development_dependency "sqlite3","~> 1.3"
  spec.add_development_dependency "ruby-debug"
  spec.add_dependency "activerecord","~> 3.2"

end
