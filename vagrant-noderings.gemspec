# frozen_string_literal: true

require_relative "lib/vagrant-noderings/version"

Gem::Specification.new do |s|
  s.name = "vagrant-noderings"
  s.version = VagrantPlugins::Noderings::VERSION
  s.authors = ["NodeRings"]
  s.email = ["partners@noderings.com"]
  s.homepage = "https://github.com/noderings/vagrant-noderings"
  s.summary = "Vagrant provider for NodeRings virtual machines"
  s.description = "A Vagrant provider that orders NodeRings marketplace virtual machines, " \
                  "syncs folders with rsync, provisions them, and deletes them with their " \
                  "temporary SSH key on vagrant destroy."
  s.license = "Apache-2.0"

  s.files = %w[LICENSE README.md CHANGELOG.md] + Dir.glob("{lib,locales}/**/*")
  s.require_paths = ["lib"]
  s.required_ruby_version = ">= 3.0"

  s.metadata = {
    "bug_tracker_uri" => "#{s.homepage}/issues",
    "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{s.homepage}#readme",
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "rubygems_mfa_required" => "true"
  }

  # Vagrant itself is not a dependency: plugins run inside Vagrant's own Ruby.
  # The provider talks to the API with the Ruby standard library only.
end
