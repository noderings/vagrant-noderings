# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Puts the SSH details of the server in env[:machine_ssh_info].
      class ReadSSHInfo
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          env[:machine_ssh_info] = read(env[:machine])
          @app.call(env)
        end

        def read(machine)
          session = Session.new(machine)
          vm = session.vm
          return nil if vm.nil?

          host = vm["ipv4"].to_s.empty? ? vm["ipv6"] : vm["ipv4"]
          return nil if host.to_s.empty?

          info = { host: host, port: 22, username: "root" }
          info[:private_key_path] = [session.private_key_path.to_s] if session.generated_key?
          info
        end
      end
    end
  end
end
