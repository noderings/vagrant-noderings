# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Puts the server's state in env[:machine_state_id].
      #
      # NodeRings reports a server that has booted after its order as "created";
      # Vagrant calls that running.
      class ReadState
        STATES = { "running" => :running, "created" => :running, "stopped" => :stopped }.freeze

        def initialize(app, _env)
          @app = app
        end

        def call(env)
          machine = env[:machine]
          if machine.id.nil?
            env[:machine_state_id] = :not_created
          else
            vm = Session.new(machine).vm
            if vm.nil?
              # Deleted outside Vagrant.
              machine.id = nil
              env[:machine_state_id] = :not_created
            else
              state = NoderingsVagrant::Compute.power_state(vm)
              env[:machine_state_id] = STATES.fetch(state, state.to_sym)
            end
          end
          @app.call(env)
        end
      end
    end
  end
end
