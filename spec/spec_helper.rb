# frozen_string_literal: true

require "tmpdir"
require "vagrant"
require "vagrant-noderings"
require "vagrant-noderings/config"
require "vagrant-noderings/provider"
require_relative "support/fake_noderings"

VagrantPlugins::Noderings::Plugin.setup_i18n

# A stand-in for Vagrant::Machine with what the provider uses.
class FakeMachine
  attr_accessor :id, :state_id, :ready
  attr_reader :name, :provider_config, :data_dir, :config, :communicate

  def initialize(provider_config, data_dir)
    @name = :default
    @provider_config = provider_config
    @data_dir = Pathname.new(data_dir)
    @config = Struct.new(:nfs, :smb).new(Struct.new(:functional).new(true), Struct.new(:functional).new(true))
    @ready = true
    machine = self
    @communicate = Object.new.tap { |c| c.define_singleton_method(:ready?) { machine.ready } }
  end

  def state
    Struct.new(:id).new(state_id || (id ? :running : :not_created))
  end
end

module SpecHelpers
  def provider_config(**overrides)
    VagrantPlugins::Noderings::Config.new.tap do |c|
      c.token = "test-token"
      c.plan = "SC-GC-1C-1G-20"
      c.country = "United States"
      c.city = "Ashburn"
      overrides.each { |k, v| c.public_send("#{k}=", v) }
      c.finalize!
    end
  end

  def ui
    @ui ||= Vagrant::UI::Silent.new
  end

  # Runs one middleware with the next step recorded.
  def run_action(klass, env)
    called = false
    klass.new(->(_e) { called = true }, env).call(env)
    expect(called).to be true
    env
  end
end

RSpec.configure do |c|
  c.include SpecHelpers
  c.before do
    @fake = FakeNoderings.new
    VagrantPlugins::Noderings::Session.transport = @fake
    VagrantPlugins::Noderings::Session.sleeper = ->(_s) {}
    @data_dir = Dir.mktmpdir
  end
  c.after { FileUtils.rm_rf(@data_dir) }
end
