# frozen_string_literal: true

require "log4r"
require "vagrant"

module VagrantPlugins
  module Noderings
    class Provider < Vagrant.plugin("2", :provider)
      def initialize(machine)
        super
        @machine = machine
        # The server is remote: sync folders with rsync, not NFS or SMB.
        @machine.config.nfs.functional = false
        @machine.config.smb.functional = false
      end

      def action(name)
        method = "action_#{name}"
        Action.respond_to?(method) ? Action.send(method) : nil
      end

      def ssh_info
        @machine.action("read_ssh_info")[:machine_ssh_info]
      end

      def state
        id = @machine.action("read_state")[:machine_state_id]
        Vagrant::MachineState.new(id, I18n.t("vagrant_noderings.states.short_#{id}", default: id.to_s),
                                  I18n.t("vagrant_noderings.states.long_#{id}", default: id.to_s))
      end

      def to_s
        "NodeRings (#{@machine.id || 'new'})"
      end
    end
  end
end
