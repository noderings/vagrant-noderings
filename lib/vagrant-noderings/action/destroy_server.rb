# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Deletes the server and the temporary SSH key.
      class DestroyServer
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          machine = env[:machine]
          session = Session.new(machine)
          env[:ui].info(I18n.t("vagrant_noderings.destroying"))
          session.call("deleting the server") do
            session.compute.waiter(session.client, session.config.wait_timeout).retry_busy do
              session.client.delete_virtual_machine(machine.id)
            rescue NoderingsVagrant::APIError => e
              raise unless e.not_found?
            end
          end
          session.cleanup
          machine.id = nil
          @app.call(env)
        end
      end
    end
  end
end
