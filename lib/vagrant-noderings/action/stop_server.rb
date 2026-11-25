# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Stops the server. Its disk and IP addresses are kept.
      class StopServer
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          if env[:machine].state.id == :stopped
            env[:ui].info(I18n.t("vagrant_noderings.already_stopped"))
          else
            session = Session.new(env[:machine])
            env[:ui].info(I18n.t("vagrant_noderings.stopping"))
            session.call("stopping the server") do
              session.compute.set_power(session.client, env[:machine].id, "stopped", timeout: session.config.wait_timeout)
            end
          end
          @app.call(env)
        end
      end
    end
  end
end
