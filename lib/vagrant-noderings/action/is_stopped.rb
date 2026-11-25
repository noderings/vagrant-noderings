# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Sets env[:result] to whether the server is stopped.
      class IsStopped
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          env[:result] = env[:machine].state.id == :stopped
          @app.call(env)
        end
      end
    end
  end
end
