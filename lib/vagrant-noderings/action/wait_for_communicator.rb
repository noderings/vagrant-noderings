# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Waits until SSH answers. A new server opens port 22 before cloud-init has
      # installed the key, so this retries until a login works.
      module WaitForCommunicator
        def self.wait(env, timeout)
          machine = env[:machine]
          env[:ui].info(I18n.t("vagrant_noderings.waiting_for_ssh"))
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          until machine.communicate.ready?
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              raise Errors::APIError, action: "waiting for SSH",
                                      message: "the server did not answer SSH in time"
            end
            return if env[:interrupted]

            sleep(Session.sleeper ? 0 : 5)
          end
          env[:ui].info(I18n.t("vagrant_noderings.ready"))
        end
      end
    end
  end
end
