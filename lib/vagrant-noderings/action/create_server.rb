# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Action
      # Orders the server, waits for its address and for SSH.
      class CreateServer
        def initialize(app, _env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_noderings::action::create_server")
        end

        def call(env)
          machine = env[:machine]
          session = Session.new(machine)
          config = session.config
          compute = session.compute
          client = session.client

          plan_id, region_id, what = offer(session)
          keys = session.ssh_key_ids
          hostname = session.hostname
          env[:ui].info(I18n.t("vagrant_noderings.ordering", hostname: hostname, offer: what,
                                                             distro: compute.normalize_distro(config.distro)))
          vm = session.call("ordering #{hostname}") do
            compute.order_vm(client, hostname, plan_id, region_id, distro: config.distro, ssh_key_ids: keys,
                                                                   tags: config.tags, wait: false, timeout: config.wait_timeout)
          end
          # Remember the server at once, so an interrupted `up` can still be destroyed.
          machine.id = vm["id"]
          env[:ui].info(I18n.t("vagrant_noderings.ordered", id: vm["id"]))

          vm = session.call("waiting for #{hostname}") { compute.wait_address(client, vm["id"], config.wait_timeout) }
          if config.firewall_ruleset
            ruleset = session.call("resolving the firewall ruleset") { compute.resolve_ruleset(client, config.firewall_ruleset) }
            session.call("attaching the firewall") { compute.attach_firewall(client, vm["id"], ruleset, timeout: config.wait_timeout) }
          end
          env[:ui].info(I18n.t("vagrant_noderings.address", address: vm["ipv4"] || vm["ipv6"]))
          WaitForCommunicator.wait(env, config.wait_timeout) unless env[:interrupted]
          @app.call(env)
        end

        def offer(session)
          config = session.config
          return [config.plan_id, config.region_id, "plan #{config.plan_id}"] if config.plan_id && config.region_id

          plan_id, region_id, offer = session.call("finding an offer") do
            session.compute.choose_offer(session.client, config.plan, config.country, config.city,
                                         billing_type: config.billing_type, provider_id: config.provider_id, sort: config.sort,
                                         provider: config.hosting_provider)
          end
          [plan_id, region_id, "#{config.plan} from #{offer['provider_name']} in #{config.city}, #{config.country}"]
        end
      end
    end
  end
end
