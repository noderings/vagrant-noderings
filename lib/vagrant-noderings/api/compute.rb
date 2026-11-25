# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#
# Marketplace offer lookup and virtual machine lifecycle helpers.

require_relative "client"

module NoderingsVagrant
  BILLING_TYPES = {
    "usage" => "BILLING_TYPE_USAGE",
    "subscription" => "BILLING_TYPE_SUBSCRIPTION",
    "free" => "BILLING_TYPE_FREE",
  }.freeze
  NONCE_TAG_PREFIX = "vagrant-create-"
  DEFAULT_WAIT_TIMEOUT = 900

  # Marketplace offers: turn a plan code and a city into a plan and region ID.
  module Marketplace
    module_function

    def amount(price)
      Float(price["unitAmount"])
    rescue ArgumentError, TypeError
      nil
    end

    # The price that best represents what the plan costs, for sorting.
    #
    # Usage plans carry several meters (compute-hours, storage, traffic, IPs);
    # comparing the smallest of them would rank by the cheapest meter, not the
    # cheapest server. Prefer the compute meter, then a flat price.
    def main_price(prices)
      prices = Array(prices).reject { |p| amount(p).nil? }
      return Float::INFINITY if prices.empty?

      compute = prices.select { |p| p["unitName"].to_s.downcase.include?("compute") }
      return compute.map { |p| amount(p) }.min unless compute.empty?

      flat = prices.select do |p|
        p["pricingModel"].to_s.end_with?("FLAT", "FLAT_RATE", "FIXED", "PER_UNIT") ||
          p["chargeTiming"].to_s.end_with?("IN_ADVANCE")
      end
      return flat.map { |p| amount(p) }.min unless flat.empty?

      prices.map { |p| amount(p) }.min
    end

    def same_place?(region, country, city)
      region["country"].to_s.casecmp?(country.to_s) && region["city"].to_s.casecmp?(city.to_s)
    end

    # Returns [offers, located]: offers sorted best first, and how many matched
    # the location before the capability and IPv6 filters.
    def find_offers(client, plan_code, country, city, billing_type: "usage", provider_id: nil,
      require_capabilities: [], require_ipv6: false, sort: "price")
      billing = BILLING_TYPES.fetch(billing_type.to_s, "")
      found = []
      if provider_id.to_s.empty?
        client.list_providers(plan_code, country, city, billing_type: billing.empty? ? nil : billing,
          ipv6_only: require_ipv6).each do |p|
            regions = p["planRegions"] || []
            region = regions.find { |r| same_place?(r, country, city) } || regions.first || {}
            found << offer(p, p["planId"], region["regionId"], billing,
              p["ipv6AvailableInFilteredRegion"], p["planPrices"])
          end
      else
        p = client.get(
          "/v1/marketplace/providers/#{NoderingsVagrant.escape(provider_id)}"
        )
        info = p["provider"] || {}
        (p["availablePlans"] || []).each do |pl|
          next if pl["planCode"] != plan_code || (!billing.empty? && pl["billingType"] != billing)
          next if pl["assetType"] && pl["assetType"] != "ASSET_TYPE_VM"

          (pl["regions"] || []).select { |r| same_place?(r, country, city) }.each do |r|
            found << offer(info, pl["planId"], r["regionId"], pl["billingType"], p["hasIpv6"], pl["planPrices"])
          end
        end
      end
      located = found.length
      need = Array(require_capabilities)
      out = found.select { |o| (need - o["capabilities"]).empty? && (!require_ipv6 || o["ipv6"]) }
      out = out.sort_by do |o|
        price = main_price(o["prices"])
        if sort.to_s == "rating"
          [-o["rating"], price, o["provider_name"].to_s, o["plan_id"].to_s]
        else
          [price, -o["rating"], o["provider_name"].to_s, o["plan_id"].to_s]
        end
      end
      [out, located]
    end

    def offer(info, plan_id, region_id, billing, ipv6, prices)
      {
        "provider_id" => info["organizationId"],
        "provider_name" => info["organizationName"],
        "plan_id" => plan_id,
        "region_id" => region_id,
        "billing_type" => NoderingsVagrant.trim_enum(billing, "BILLING_TYPE_"),
        "capabilities" => info["capabilities"] || [],
        "ipv6" => ipv6 ? true : false,
        "rating" => info["rating"].to_f,
        "total_reviews" => info["totalReviews"].to_i,
        "prices" => prices || [],
      }
    end

    def no_offer_message(plan_code, country, city, billing_type, located)
      msg = "No offer for plan code #{plan_code} in #{city}, #{country}"
      msg += " with billing type #{billing_type}" unless billing_type.to_s.empty?
      msg += "."
      msg += " #{located} offer(s) matched the location but not the required capabilities or IPv6." if located > 0
      "#{msg} List what is sold in the NodeRings console marketplace, or with the API at /v1/marketplace/plans."
    end
  end

  # Virtual machine helpers.
  module Compute
    module_function

    def power_state(machine)
      op = (machine || {})["operationStatus"].to_s
      return "running" if %w{OPERATION_STATUS_STARTED OPERATION_STATUS_RESTARTED}.include?(op)
      return "stopped" if op == "OPERATION_STATUS_STOPPED"

      t = NoderingsVagrant.trim_enum(op, "OPERATION_STATUS_")
      t.empty? ? "unknown" : t
    end

    # ubuntu-24.04, Ubuntu_24_04 and DISTRO_UBUNTU_24_04 -> ubuntu_24_04
    def normalize_distro(distro)
      distro.to_s.strip.downcase.delete_prefix("distro_").tr(".-", "__")
    end

    def distro_enum(distro)
      "DISTRO_#{normalize_distro(distro).upcase}"
    end

    def user_tags(machine)
      Array((machine || {})["tags"]).reject { |t| t.start_with?(NONCE_TAG_PREFIX) }.sort
    end

    # The VM as a plain hash with friendly fields.
    def view(machine)
      return {} if machine.nil?

      {
        "id" => machine["id"],
        "hostname" => machine["hostname"],
        "ipv4" => machine["ipv4"],
        "ipv6" => machine["ipv6"],
        "power_state" => power_state(machine),
        "distro" => NoderingsVagrant.trim_enum(machine["distro"], "DISTRO_"),
        "plan_code" => machine["planCode"],
        "plan_id" => machine["planId"],
        "region_id" => machine["regionId"],
        "billing_type" => NoderingsVagrant.trim_enum(machine["planBillingType"], "BILLING_TYPE_"),
        "provisioning_status" => NoderingsVagrant.trim_enum(machine["crStatus"], "CR_STATUS_"),
        "firewall_ruleset_id" => machine["firewallRulesetId"],
        "tags" => user_tags(machine),
      }
    end

    # The VM with this ID or unique hostname, or nil.
    def find_vm(client, name_or_id)
      if NoderingsVagrant.uuid?(name_or_id)
        begin
          return client.get_virtual_machine(name_or_id)
        rescue APIError => e
          return if e.not_found?

          raise
        end
      end
      matches = client.list_virtual_machines.select { |v| v["hostname"] == name_or_id }
      if matches.length > 1
        raise UsageError, "#{matches.length} virtual machines are named #{name_or_id}; use the ID of " \
                          "the one you mean: #{matches.map { |v| v["id"] }.join(", ")}"
      end
      return if matches.empty?

      # List entries omit some details; read the full VM.
      client.get_virtual_machine(matches.first["id"])
    end

    def translate_create_error(err)
      msg = err.message
      low = msg.downcase
      if low.include?("payment method")
        msg += ". Add a payment method to the organization in the NodeRings console. Paid plans, " \
               "including usage-billed ones, need one."
      elsif low.include?("runway") || low.include?("insufficient")
        msg += ". Top up the organization's credit balance, or choose a cheaper plan."
      elsif low.include?("no vm template")
        msg += ". This provider has no image for the chosen distro in this region. Pick another distro, or another offer."
      elsif low.include?("capacity") || low.include?("marketplace-ready node")
        msg += ". The region is out of capacity for this plan. Try another provider or city."
      end
      if err.is_a?(APIError) && err.quota?
        msg += ". The organization has reached its virtual machine quota. Delete unused VMs or ask " \
               "NodeRings support to raise the limit."
      end
      msg
    end

    # Returns [plan_id, region_id, offer] for the best matching offer.
    def choose_offer(client, plan_code, country, city, billing_type: "usage", provider_id: nil,
      require_capabilities: [], require_ipv6: false, sort: "price")
      offers, located = Marketplace.find_offers(
        client, plan_code, country, city,
        billing_type: billing_type, provider_id: provider_id,
        require_capabilities: require_capabilities, require_ipv6: require_ipv6, sort: sort
      )
      raise UsageError, Marketplace.no_offer_message(plan_code, country, city, billing_type, located) if offers.empty?

      best = offers.first
      [best["plan_id"], best["region_id"], best]
    end

    # SSH key names or IDs -> IDs.
    def resolve_ssh_keys(client, keys)
      keys = Array(keys)
      return [] if keys.empty?

      existing = client.list_ssh_keys
      keys.map do |key|
        match = existing.find { |k| k["id"] == key || k["name"] == key }
        raise UsageError, "no NodeRings SSH key is named #{key}; add it in the NodeRings console, or leave ssh_keys unset to use a key Vagrant generates" unless match

        match["id"]
      end
    end

    # A firewall ruleset name or ID -> ID.
    def resolve_ruleset(client, ruleset)
      return "" if ruleset.to_s.empty?

      rs = client.list_firewall_rulesets.find { |r| [r["id"], r["name"]].include?(ruleset) }
      raise UsageError, "no NodeRings firewall ruleset is named #{ruleset}" unless rs

      rs["id"]
    end

    def waiter(client, timeout)
      Waiter.new(timeout, sleeper: ->(s) { client.sleep_for(s) })
    end

    def wait_provisioned(client, vm_id, timeout = DEFAULT_WAIT_TIMEOUT)
      waiter(client, timeout).wait("virtual machine #{vm_id} to be provisioned") do
        vm = client.get_virtual_machine(vm_id)
        case vm["crStatus"]
        when "CR_STATUS_APPLIED" then [true, vm]
        when "CR_STATUS_FAILED"
          raise UsageError, "provisioning of virtual machine #{vm_id} failed. The API does not report " \
                            "why; delete it and try another offer, or contact the provider"
        else [false, nil]
        end
      end
    end

    # Waits until the VM is provisioned and has an IP address, without waiting
    # for the power state; tools that go on to log in check SSH themselves.
    def wait_address(client, vm_id, timeout = DEFAULT_WAIT_TIMEOUT)
      vm = wait_provisioned(client, vm_id, timeout)
      return vm unless vm["ipv4"].to_s.empty? && vm["ipv6"].to_s.empty?

      waiter(client, timeout).wait("virtual machine #{vm_id} to get an IP address") do
        vm = client.get_virtual_machine(vm_id)
        [!(vm["ipv4"].to_s.empty? && vm["ipv6"].to_s.empty?), vm]
      end
    end

    def wait_idle(client, vm_id, what, timeout = DEFAULT_WAIT_TIMEOUT)
      waiter(client, timeout).wait(what) do
        vm = client.get_virtual_machine(vm_id)
        [yield(vm) && vm["crStatus"] != "CR_STATUS_PROCESSING", vm]
      end
    end

    # Waits while the VM is in a transitional power state (created, reinstalling).
    def wait_settled(client, vm_id, timeout = DEFAULT_WAIT_TIMEOUT)
      wait_idle(client, vm_id, "the virtual machine to finish booting", timeout) do |vm|
        %w{running stopped}.include?(power_state(vm))
      end
    end

    # want: 'running', 'stopped' or 'restarted'
    def set_power(client, vm_id, want, wait: true, timeout: DEFAULT_WAIT_TIMEOUT)
      action = { "running" => "start", "stopped" => "stop", "restarted" => "restart" }.fetch(want)
      waiter(client, timeout).retry_busy { client.vm_action(vm_id, action) }
      return client.get_virtual_machine(vm_id) unless wait

      target = want == "restarted" ? "running" : want
      wait_idle(client, vm_id, "the virtual machine to be #{target}", timeout) { |vm| power_state(vm) == target }
    end

    def attach_firewall(client, vm_id, ruleset_id, wait: true, timeout: DEFAULT_WAIT_TIMEOUT)
      waiter(client, timeout).retry_busy { client.vm_action(vm_id, "attach-firewall", { "rulesetId" => ruleset_id }) }
      return client.get_virtual_machine(vm_id) unless wait

      wait_idle(client, vm_id, "the firewall to be applied", timeout) { |vm| vm["firewallRulesetId"] == ruleset_id }
    end

    def detach_firewall(client, vm_id, ruleset_id, wait: true, timeout: DEFAULT_WAIT_TIMEOUT)
      waiter(client, timeout).retry_busy { client.vm_action(vm_id, "detach-firewall", { "rulesetId" => ruleset_id }) }
      return client.get_virtual_machine(vm_id) unless wait

      wait_idle(client, vm_id, "the firewall to be removed", timeout) { |vm| vm["firewallRulesetId"].to_s.empty? }
    end

    # Reinstalls the operating system. This erases the disk; the IP addresses stay.
    def reinstall(client, vm_id, hostname, distro, ssh_key_ids: [], password: nil, wait: true,
      timeout: DEFAULT_WAIT_TIMEOUT)
      body = { "hostname" => hostname.to_s, "distro" => distro_enum(distro) }
      body["sshKeyIds"] = ssh_key_ids unless ssh_key_ids.empty?
      body["password"] = password unless password.to_s.empty?
      waiter(client, timeout).retry_busy { client.vm_action(vm_id, "reinstall", body) }
      return client.get_virtual_machine(vm_id) unless wait

      # The status may still read COMPLETED from an earlier reinstall for a moment.
      client.sleep_for(3)
      waiter(client, timeout).wait("the reinstall to finish") do
        vm = client.get_virtual_machine(vm_id)
        status = vm["reinstallStatus"]
        raise UsageError, "the reinstall of virtual machine #{vm_id} failed; the API does not report why" if status == "REINSTALL_STATUS_FAILED"

        [status == "REINSTALL_STATUS_COMPLETED" && vm["crStatus"] != "CR_STATUS_PROCESSING", vm]
      end
      wait_settled(client, vm_id, timeout)
    end

    # Orders a VM and returns it.
    #
    # Safe against lost responses: an ambiguous failure is retried with the
    # same idempotency key, and free plans (which ignore the key) are tagged
    # with a nonce so the VM is found instead of ordered twice.
    def order_vm(client, hostname, plan_id, region_id, distro: nil, ssh_key_ids: [], password: nil,
      tags: [], ruleset_id: nil, wait: true, timeout: DEFAULT_WAIT_TIMEOUT)
      body = { "hostname" => hostname, "planId" => plan_id, "regionId" => region_id,
               "idempotencyKey" => NoderingsVagrant.new_uuid }
      body["distro"] = distro_enum(distro) unless distro.to_s.empty?
      body["sshKeyIds"] = ssh_key_ids unless ssh_key_ids.empty?
      body["password"] = password unless password.to_s.empty?
      tags = Array(tags).uniq.sort

      free = begin
        client.get_marketplace_plan(plan_id)["billingType"] == "BILLING_TYPE_FREE"
             rescue APIError
               true
      end
      nonce = free ? NONCE_TAG_PREFIX + NoderingsVagrant.new_uuid : ""
      tags += [nonce] unless nonce.empty?
      body["tags"] = tags unless tags.empty?

      find_by_nonce = -> { client.list_virtual_machines.find { |v| Array(v["tags"]).include?(nonce) } }

      vm = nil
      last_err = nil
      new_key = false
      6.times do |attempt|
        begin
          vm = client.create_virtual_machine(body)
          break
        rescue APIError => e
          last_err = e
          if e.code == CODE_FAILED_PRECONDITION && e.api_message.downcase.include?("new idempotency key") && !new_key
            new_key = true
            body["idempotencyKey"] = NoderingsVagrant.new_uuid
            next
          end
          raise UsageError, "ordering virtual machine #{hostname}: #{translate_create_error(e)}" unless e.ambiguous?
        rescue *CONNECTION_ERRORS => e
          last_err = e
        end
        unless nonce.empty?
          vm = find_by_nonce.call
          break if vm
        end
        client.sleep_for([2 * (attempt + 1), 10].min)
      end
      if vm.nil? && last_err
        raise UsageError, "ordering virtual machine #{hostname}: #{last_err.message}. The order may or may " \
                          "not have been placed; check the console before trying again"
      end
      vm = find_by_nonce.call if (vm.nil? || vm["id"].to_s.empty?) && !nonce.empty?
      if vm.nil? || vm["id"].to_s.empty?
        raise UsageError, "the API accepted the order for #{hostname} but did not return the new virtual " \
                          "machine; check the console before trying again"
      end

      vm_id = vm["id"]
      if wait || ruleset_id || !nonce.empty?
        wait_provisioned(client, vm_id, timeout)
        # The VM reads CREATED until the platform has booted it, then STARTED.
        wait_settled(client, vm_id, timeout)
      end
      unless nonce.empty?
        begin
          client.update_virtual_machine_tags(vm_id, remove: [nonce])
        rescue APIError
          nil
        end
      end
      attach_firewall(client, vm_id, ruleset_id, wait: wait, timeout: timeout) unless ruleset_id.to_s.empty?
      client.get_virtual_machine(vm_id)
    end
  end
end
