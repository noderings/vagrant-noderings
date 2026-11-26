# frozen_string_literal: true

require "json"
require "securerandom"
require "uri"

# A stateful in-memory stand-in for the NodeRings API.
#
# It is plugged in as the client's transport, so unit tests run the real
# client, retry and order logic against it.
class FakeNoderings
  PLAN_ID = "11111111-1111-1111-1111-111111111111"
  REGION_ID = "22222222-2222-2222-2222-222222222222"
  ACME_ID = "33333333-3333-3333-3333-333333333333"
  ACME_PLAN_ID = "44444444-4444-4444-4444-444444444444"
  ACME_REGION_ID = "55555555-5555-5555-5555-555555555555"
  ACME_OFFER = {
    "organizationId" => ACME_ID, "organizationName" => "Acme Hosting", "planId" => ACME_PLAN_ID,
    "planRegions" => [{ "country" => "United States", "city" => "Ashburn", "regionId" => ACME_REGION_ID }],
    "capabilities" => [], "rating" => 3,
    "planPrices" => [{ "unitAmount" => "0.012", "unitName" => "per compute-hour" }]
  }.freeze

  attr_reader :calls, :ssh_keys, :zones, :records, :rulesets, :rules, :groups, :vms, :created_vm_bodies
  # Status codes to return before handling the next matching request: { 'POST /v1/virtual-machines' => [502] }
  attr_reader :failures
  # More provider offers to list, such as a second provider with the same name.
  attr_reader :extra_providers

  def initialize
    @calls = []
    @ssh_keys = {}
    @zones = {}
    @records = {}
    @rulesets = {}
    @rules = {}
    @groups = {}
    @vms = {}
    @created_vm_bodies = []
    @failures = Hash.new { |h, k| h[k] = [] }
    @extra_providers = []
    @routes = [
      ["GET", %r{\A/v1/organization\z}, :get_org],
      ["GET", %r{\A/v1/ssh-keys\z}, :list_keys],
      ["POST", %r{\A/v1/ssh-keys\z}, :create_key],
      ["DELETE", %r{\A/v1/ssh-keys/([^/]+)\z}, :delete_key],
      ["GET", %r{\A/v1/dns/zones\z}, :list_zones],
      ["POST", %r{\A/v1/dns/zones\z}, :create_zone],
      ["GET", %r{\A/v1/dns/zones/([^/]+)\z}, :get_zone],
      ["DELETE", %r{\A/v1/dns/zones/([^/]+)\z}, :delete_zone],
      ["GET", %r{\A/v1/dns/zones/([^/]+)/records\z}, :list_records],
      ["PUT", %r{\A/v1/dns/zones/([^/]+)/records\z}, :put_record],
      ["DELETE", %r{\A/v1/dns/zones/([^/]+)/records\z}, :delete_record],
      ["POST", %r{\A/v1/dns/zones/([^/]+)/dnssec/enable\z}, :enable_dnssec],
      ["POST", %r{\A/v1/dns/zones/([^/]+)/dnssec/disable\z}, :disable_dnssec],
      ["GET", %r{\A/v1/dns/zones/([^/]+)/dnssec\z}, :get_dnssec],
      ["GET", %r{\A/v1/firewall/address-groups\z}, :list_groups],
      ["GET", %r{\A/v1/firewall/rulesets\z}, :list_rulesets],
      ["POST", %r{\A/v1/firewall/rulesets\z}, :create_ruleset],
      ["DELETE", %r{\A/v1/firewall/rulesets/([^/]+)\z}, :delete_ruleset],
      ["GET", %r{\A/v1/firewall/rulesets/([^/]+)/rules\z}, :list_rules],
      ["POST", %r{\A/v1/firewall/rulesets/([^/]+)/rules\z}, :create_rule],
      ["PATCH", %r{\A/v1/firewall/rules/([^/]+)\z}, :update_rule],
      ["DELETE", %r{\A/v1/firewall/rules/([^/]+)\z}, :delete_rule],
      ["POST", %r{\A/v1/firewall/rules/([^/]+)/move\z}, :move_rule],
      ["GET", %r{\A/v1/marketplace/providers\z}, :list_providers],
      ["GET", %r{\A/v1/marketplace/providers/([^/]+)\z}, :get_provider],
      ["GET", %r{\A/v1/public/storefronts/([^/]+)\z}, :get_storefront],
      ["GET", %r{\A/v1/marketplace/plans/([^/]+)\z}, :get_plan],
      ["GET", %r{\A/v1/marketplace/plans\z}, :list_plans],
      ["GET", %r{\A/v1/marketplace/regions\z}, :list_regions],
      ["GET", %r{\A/v1/distros\z}, :list_distros],
      ["GET", %r{\A/v1/virtual-machines\z}, :list_vms],
      ["POST", %r{\A/v1/virtual-machines\z}, :create_vm],
      ["GET", %r{\A/v1/virtual-machines/([^/:]+)\z}, :get_vm],
      ["PATCH", %r{\A/v1/virtual-machines/([^/:]+)\z}, :patch_vm],
      ["DELETE", %r{\A/v1/virtual-machines/([^/:]+)\z}, :delete_vm],
      ["POST", %r{\A/v1/virtual-machines/([^/:]+):([a-z-]+)\z}, :vm_action]
    ]
  end

  # The transport interface: returns [status, body].
  def call(method, url, headers, body, _timeout)
    uri = URI(url)
    query = URI.decode_www_form(uri.query || "").to_h
    data = body ? JSON.parse(body) : nil
    @calls << [method, uri.path, query, data, headers]
    pending = @failures["#{method} #{uri.path}"]
    return [pending.shift, JSON.generate("code" => 14, "message" => "unavailable")] unless pending.empty?

    @routes.each do |m, pattern, handler|
      match = pattern.match(uri.path)
      next unless m == method && match

      status, out = send(handler, query, data, *match.captures)
      return [status, JSON.generate(out)]
    end
    [404, JSON.generate("code" => 5, "message" => "no route #{method} #{uri.path}")]
  end

  def writes
    @calls.reject { |c| c.first == "GET" }.map { |c| c.first(2) }
  end

  private

  def err(status, code, message)
    [status, { "code" => code, "message" => message }]
  end

  def uuid
    SecureRandom.uuid
  end

  # -- account / catalog ------------------------------------------------------

  def get_org(_query, _body)
    [200, { "organization" => { "id" => "org-1", "name" => "Test Org" } }]
  end

  def list_distros(_query, _body)
    [200, { "distros" => [{ "distro" => "DISTRO_UBUNTU_24_04" }, { "distro" => "DISTRO_DEBIAN_13" }] }]
  end

  def list_regions(_query, _body)
    [200, { "regions" => [{ "country" => "United States", "city" => "Ashburn" }] }]
  end

  def list_plans(_query, _body)
    [200, { "plans" => [{ "planCode" => "SC-GC-1C-1G-20", "billingType" => "BILLING_TYPE_USAGE" }] }]
  end

  def get_plan(_query, _body, plan_id)
    [200, { "id" => plan_id, "billingType" => "BILLING_TYPE_USAGE" }]
  end

  def list_providers(query, _body)
    return [200, { "providers" => [] }] unless query["filterCity"] == "Ashburn"

    [200, { "providers" => [
      {
        "organizationId" => "prov-2", "organizationName" => "Dear Host", "planId" => "plan-dear",
        "planRegions" => [{ "country" => "United States", "city" => "Ashburn", "regionId" => "region-dear" }],
        "capabilities" => [], "rating" => 5,
        "planPrices" => [{ "unitAmount" => "0.02", "unitName" => "per compute-hour" }]
      },
      {
        "organizationId" => "prov-1", "organizationName" => "Cheap Host", "planId" => PLAN_ID,
        "planRegions" => [{ "country" => "United States", "city" => "Ashburn", "regionId" => REGION_ID }],
        "capabilities" => ["guest_firewall"], "rating" => 4,
        "planPrices" => [{ "unitAmount" => "0.007", "unitName" => "per compute-hour" },
                         { "unitAmount" => "0.0001", "unitName" => "per GB-hour storage" }]
      },
      ACME_OFFER
    ] + @extra_providers }]
  end

  def get_provider(_query, _body, provider_id)
    return err(404, 5, "provider not found") unless provider_id == ACME_ID

    [200, { "provider" => {
      "provider" => { "organizationId" => ACME_ID, "organizationName" => "Acme Hosting", "rating" => 3 },
      "availablePlans" => [{
        "planId" => ACME_PLAN_ID, "planCode" => "SC-GC-1C-1G-20", "billingType" => "BILLING_TYPE_USAGE",
        "assetType" => "ASSET_TYPE_VM", "planPrices" => ACME_OFFER["planPrices"],
        "regions" => [{ "country" => "United States", "city" => "Ashburn", "regionId" => ACME_REGION_ID }]
      }]
    } }]
  end

  def get_storefront(_query, _body, slug)
    return err(404, 5, "storefront not found") unless slug == "acme-hosting"

    [200, { "storefront" => { "slug" => slug, "providerId" => ACME_ID } }]
  end

  # -- SSH keys ----------------------------------------------------------------

  def list_keys(_query, _body)
    [200, { "sshKeys" => @ssh_keys.values }]
  end

  def create_key(_query, body)
    return err(409, 6, "SSH key with same fingerprint already exists.") if @ssh_keys.values.any? { |k| k["publicKey"] == body["publicKey"] }

    key = { "id" => uuid, "name" => body["name"], "publicKey" => body["publicKey"] }
    @ssh_keys[key["id"]] = key
    [200, { "sshKey" => key }]
  end

  def delete_key(_query, _body, key_id)
    return err(404, 5, "not found") unless @ssh_keys.delete(key_id)

    [200, {}]
  end

  # -- DNS -----------------------------------------------------------------------

  def list_zones(_query, _body)
    # Like the real API, the list omits the assigned nameservers.
    [200, { "zones" => @zones.values.map { |z| z.except("assignedNameservers") } }]
  end

  def create_zone(_query, body)
    zone = {
      "id" => uuid, "name" => body["name"], "state" => "DNS_ZONE_STATE_PENDING_NS",
      "assignedNameservers" => %w[ans1.nrings.io ans2.nrings.io], "dnssecMode" => "DNSSEC_MODE_UNSIGNED"
    }
    @zones[zone["id"]] = zone
    @records[zone["id"]] = {}
    [200, { "zone" => zone.except("assignedNameservers") }]
  end

  def get_zone(_query, _body, zone_id)
    return err(404, 5, "zone not found") unless @zones.key?(zone_id)

    [200, { "zone" => @zones[zone_id] }]
  end

  def delete_zone(query, _body, zone_id)
    return err(400, 9, "zone has records; use force") if !@records.fetch(zone_id, {}).empty? && query["force"] != "true"

    @zones.delete(zone_id)
    @records.delete(zone_id)
    [200, {}]
  end

  def list_records(query, _body, zone_id)
    out = @records.fetch(zone_id, {}).filter_map do |(name, type), rec|
      next if query["name"] && !name.include?(query["name"])
      next if query["type"] && query["type"] != type

      { "name" => name, "type" => type, "ttl" => rec["ttl"], "rdata" => rec["rdata"] }
    end
    [200, { "records" => out, "totalCount" => out.length }]
  end

  def put_record(_query, body, zone_id)
    rec = body["record"]
    # The API stores names lowercased with a trailing dot on hostnames.
    rdata = rec["rdata"].map { |v| rec["type"] == "CNAME" ? v.downcase : v }
    @records[zone_id][[rec["name"], rec["type"]]] = { "ttl" => rec["ttl"], "rdata" => rdata }
    [200, {}]
  end

  def delete_record(query, _body, zone_id)
    return err(404, 5, "record not found") unless @records[zone_id].delete([query["name"], query["type"]])

    [200, {}]
  end

  def enable_dnssec(_query, _body, zone_id)
    @zones[zone_id]["dnssecMode"] = "DNSSEC_MODE_SIGNED_DS_PENDING"
    [200, {}]
  end

  def disable_dnssec(_query, _body, zone_id)
    @zones[zone_id]["dnssecMode"] = "DNSSEC_MODE_UNSIGNED"
    [200, {}]
  end

  def get_dnssec(_query, _body, zone_id)
    [200, { "mode" => @zones[zone_id]["dnssecMode"], "ds" => "12345 13 2 abcdef" }]
  end

  # -- firewall ------------------------------------------------------------------

  def list_groups(_query, _body)
    [200, { "groups" => @groups.values }]
  end

  def list_rulesets(query, _body)
    [200, { "rulesets" => @rulesets.values.select { |r| query["name"].nil? || r["name"] == query["name"] } }]
  end

  def create_ruleset(_query, body)
    rs = { "id" => uuid, "name" => body["ruleset"]["name"] }
    @rulesets[rs["id"]] = rs
    @rules[rs["id"]] = []
    [200, { "ruleset" => rs }]
  end

  def delete_ruleset(_query, _body, rs_id)
    @rulesets.delete(rs_id)
    @rules.delete(rs_id)
    [200, {}]
  end

  def renumber(rs_id)
    @rules[rs_id].each_with_index { |r, i| r["position"] = i }
  end

  def find_rule(rule_id)
    @rules.each do |rs_id, rules|
      rule = rules.find { |r| r["id"] == rule_id }
      return [rs_id, rule] if rule
    end
    [nil, nil]
  end

  def list_rules(_query, _body, rs_id)
    [200, { "rules" => @rules.fetch(rs_id, []) }]
  end

  def create_rule(_query, body, rs_id)
    rule = { "id" => uuid, "position" => 0, "rule" => body["rule"] }
    @rules[rs_id].unshift(rule)
    renumber(rs_id)
    [200, { "rule" => rule }]
  end

  def update_rule(_query, body, rule_id)
    find_rule(rule_id)[1]["rule"] = body["rule"]
    [200, {}]
  end

  def delete_rule(_query, _body, rule_id)
    rs_id, rule = find_rule(rule_id)
    @rules[rs_id].delete(rule)
    renumber(rs_id)
    [200, {}]
  end

  def move_rule(_query, body, rule_id)
    rs_id, rule = find_rule(rule_id)
    rules = @rules[rs_id]
    rules.delete(rule)
    target = rules.index { |r| r["id"] == body["targetRuleId"] }
    rules.insert(target, rule)
    renumber(rs_id)
    [200, {}]
  end

  # -- virtual machines ------------------------------------------------------------

  def list_vms(_query, _body)
    [200, { "virtualMachines" => @vms.values }]
  end

  def create_vm(_query, body)
    @created_vm_bodies << body
    vm = {
      "id" => uuid, "hostname" => body["hostname"], "planId" => body["planId"], "planCode" => "SC-GC-1C-1G-20",
      "regionId" => body["regionId"], "distro" => body.fetch("distro", "DISTRO_UBUNTU_24_04"),
      "tags" => Array(body["tags"]), "ipv4" => "192.0.2.50", "crStatus" => "CR_STATUS_APPLIED",
      "operationStatus" => "OPERATION_STATUS_STARTED", "planBillingType" => "BILLING_TYPE_USAGE"
    }
    @vms[vm["id"]] = vm
    [200, { "virtualMachine" => vm }]
  end

  def get_vm(_query, _body, vm_id)
    return err(404, 5, "not found") unless @vms.key?(vm_id)

    [200, @vms[vm_id]]
  end

  def patch_vm(_query, body, vm_id)
    vm = @vms[vm_id]
    tags = vm["tags"] - Array(body["removeTags"])
    vm["tags"] = tags + (Array(body["addTags"]) - tags)
    [200, {}]
  end

  def delete_vm(_query, _body, vm_id)
    @vms.delete(vm_id)
    [200, {}]
  end

  def vm_action(_query, body, vm_id, action)
    vm = @vms[vm_id]
    case action
    when "stop" then vm["operationStatus"] = "OPERATION_STATUS_STOPPED"
    when "start", "restart" then vm["operationStatus"] = "OPERATION_STATUS_STARTED"
    when "attach-firewall" then vm["firewallRulesetId"] = body["rulesetId"]
    when "detach-firewall" then vm.delete("firewallRulesetId")
    when "reinstall"
      vm["distro"] = body["distro"]
      vm["reinstallStatus"] = "REINSTALL_STATUS_COMPLETED"
    end
    [200, {}]
  end
end
