# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Removes the temporary key when the server is already gone.
      class CleanupFiles
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          Session.new(env[:machine]).cleanup if env[:machine].data_dir.join("noderings").exist?
          @app.call(env)
        end
      end
    end
  end
end
