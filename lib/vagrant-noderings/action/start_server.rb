# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      class StartServer
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          session = Session.new(env[:machine])
          env[:ui].info(I18n.t("vagrant_noderings.starting"))
          session.call("starting the server") do
            session.compute.set_power(session.client, env[:machine].id, "running", timeout: session.config.wait_timeout)
          end
          WaitForCommunicator.wait(env, session.config.wait_timeout)
          @app.call(env)
        end
      end
    end
  end
end
