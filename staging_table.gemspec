lib = File.expand_path("../lib", __FILE__)

$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "staging_table/version"

Gem::Specification.new do |spec|
  spec.name = "staging_table"
  spec.version = StagingTable::VERSION
  spec.authors = ["eagerworks"]
  spec.email = ["hello@eagerworks.com"]

  spec.summary = "Mass data imports via temporary staging tables"
  spec.description = "Handles mass data imports via temporary staging tables, supporting PostgreSQL and MySQL, with a clean DSL for table lifecycle management and built-in bulk insert capabilities."
  spec.homepage = "https://github.com/eagerworks/staging_table"
  spec.license = "MIT"

  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 6.0"
  spec.add_dependency "activesupport", ">= 6.0"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "mysql2"
  spec.add_development_dependency "sqlite3"
end
