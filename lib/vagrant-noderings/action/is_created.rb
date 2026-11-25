# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Sets env[:result] to whether the server exists.
      class IsCreated
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          env[:result] = env[:machine].state.id != :not_created
          @app.call(env)
        end
      end
    end
  end
end
