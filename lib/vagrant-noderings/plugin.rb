# frozen_string_literal: true

begin
  require "vagrant"
rescue LoadError
  raise "The NodeRings provider must be run within Vagrant."
end

raise "The NodeRings provider needs Vagrant 2.2 or later." if Gem::Version.new(Vagrant::VERSION) < Gem::Version.new("2.2.0")

module VagrantPlugins
  module Noderings
    class Plugin < Vagrant.plugin("2")
      name "NodeRings"
      description <<~DESC
        A Vagrant provider that runs machines on NodeRings virtual machines, ordered
        from the NodeRings marketplace.
      DESC

      config(:noderings, :provider) do
        require_relative "config"
        Config
      end

      # No box is needed: the operating system comes from the provider config.
      provider(:noderings, parallel: true, box_optional: true) do
        setup_i18n
        setup_logging
        require_relative "provider"
        Provider
      end

      def self.setup_i18n
        I18n.load_path << File.expand_path("locales/en.yml", Noderings.source_root)
        I18n.reload!
      end

      def self.setup_logging
        require "log4r"
        level = begin
          Log4r.const_get(ENV.fetch("VAGRANT_LOG", "").upcase)
        rescue NameError
          nil
        end
        return unless level.is_a?(Integer)

        logger = Log4r::Logger.new("vagrant_noderings") # registered globally by name
        logger.outputters = Log4r::Outputter.stderr
        logger.level = level # rubocop:disable Lint/UselessSetterCall
      end
    end
  end
end
