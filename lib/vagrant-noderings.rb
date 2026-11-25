# frozen_string_literal: true

require "pathname"
require "vagrant-noderings/plugin"

module VagrantPlugins
  # The NodeRings provider for Vagrant.
  module Noderings
    lib_path = Pathname.new(File.expand_path("vagrant-noderings", __dir__))
    autoload :Action, lib_path.join("action")
    autoload :Errors, lib_path.join("errors")
    autoload :Session, lib_path.join("session")

    # The root of the plugin's source, for the locale file.
    def self.source_root
      @source_root ||= Pathname.new(File.expand_path("..", __dir__))
    end
  end
end
