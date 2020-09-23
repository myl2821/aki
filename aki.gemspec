lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'aki/version'

Aki::GemSpec ||= Gem::Specification.new do |spec|
  spec.name          = "aki"
  spec.version       = Aki::VERSION
  spec.authors       = ["Mo Yuli"]
  spec.email         = ["moyuli@sensetime.com"]

  spec.summary       = %q{Aki is an HTTP Server}
  spec.description   = %q{Aki is an HTTP Server}
  # spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  # spec.metadata["homepage_uri"] = spec.homepage
  # spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

  end

  spec.add_dependency 'thread'
  spec.add_dependency 'http_parser.rb'
  spec.add_dependency 'eventmachine'
  spec.add_dependency 'rack'
  spec.add_dependency 'rest-client'

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
