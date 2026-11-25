# frozen_string_literal: true

source "https://rubygems.org"

group :plugins do
  gemspec
end

group :development do
  # Plugins run inside Vagrant, which is not published to RubyGems; test against its source.
  gem "vagrant", git: "https://github.com/hashicorp/vagrant.git", tag: ENV.fetch("VAGRANT_VERSION", "v2.4.9")
end

group :test do
  gem "rake"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.69", require: false
end
