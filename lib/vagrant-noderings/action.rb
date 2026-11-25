# frozen_string_literal: true

require "pathname"
require "vagrant/action/builder"

module VagrantPlugins
  module Noderings
    # The middleware stacks behind each Vagrant command.
    module Action
      include Vagrant::Action::Builtin

      def self.action_up
        Vagrant::Action::Builder.new.tap do |b|
          b.use HandleBox
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b1|
            if env[:result]
              b1.use Call, IsStopped do |env2, b2|
                if env2[:result]
                  b2.use Provision
                  b2.use SyncedFolders
                  b2.use StartServer
                else
                  b2.use Message, I18n.t("vagrant_noderings.already_created")
                end
              end
            else
              b1.use Provision
              b1.use SyncedFolders
              b1.use CreateServer
            end
          end
        end
      end

      def self.action_halt
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b1|
            if env[:result]
              b1.use StopServer
            else
              b1.use Message, I18n.t("vagrant_noderings.not_created")
            end
          end
        end
      end

      def self.action_destroy
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, DestroyConfirm do |env, b1|
            if env[:result]
              b1.use ConfigValidate
              b1.use Call, IsCreated do |env2, b2|
                if env2[:result]
                  b2.use DestroyServer
                else
                  b2.use Message, I18n.t("vagrant_noderings.not_created")
                  b2.use CleanupFiles
                end
              end
            else
              b1.use Message, I18n.t("vagrant_noderings.will_not_destroy", name: env[:machine].name)
            end
          end
        end
      end

      def self.action_reload
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b1|
            if env[:result]
              b1.use action_halt
              b1.use action_up
            else
              b1.use Message, I18n.t("vagrant_noderings.not_created")
            end
          end
        end
      end

      def self.action_provision
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b1|
            if env[:result]
              b1.use Provision
              b1.use SyncedFolders
            else
              b1.use Message, I18n.t("vagrant_noderings.not_created")
            end
          end
        end
      end

      def self.action_ssh
        running_only(SSHExec)
      end

      def self.action_ssh_run
        running_only(SSHRun)
      end

      def self.running_only(middleware)
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsCreated do |env, b1|
            if env[:result]
              b1.use middleware
            else
              b1.use Message, I18n.t("vagrant_noderings.not_created")
            end
          end
        end
      end

      def self.action_read_ssh_info
        Vagrant::Action::Builder.new.tap { |b| b.use ReadSSHInfo }
      end

      def self.action_read_state
        Vagrant::Action::Builder.new.tap { |b| b.use ReadState }
      end

      root = Pathname.new(File.expand_path("action", __dir__))
      autoload :CleanupFiles, root.join("cleanup_files")
      autoload :CreateServer, root.join("create_server")
      autoload :DestroyServer, root.join("destroy_server")
      autoload :IsCreated, root.join("is_created")
      autoload :IsStopped, root.join("is_stopped")
      autoload :ReadSSHInfo, root.join("read_ssh_info")
      autoload :ReadState, root.join("read_state")
      autoload :StartServer, root.join("start_server")
      autoload :StopServer, root.join("stop_server")
      autoload :WaitForCommunicator, root.join("wait_for_communicator")
    end
  end
end
