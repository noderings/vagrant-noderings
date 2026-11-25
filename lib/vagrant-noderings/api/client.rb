# frozen_string_literal: true

#
# Copyright:: NodeRings
# License:: Apache-2.0
#
# A small JSON client for the NodeRings public API, written against the Ruby
# standard library only so the cookbook installs no gems on the node.

require "json" unless defined?(JSON)
require "net/http" unless defined?(Net::HTTP)
require "openssl" unless defined?(OpenSSL)
require "securerandom" unless defined?(SecureRandom)
require "uri" unless defined?(URI)

module NoderingsVagrant
  DEFAULT_API_URL = "https://api.noderings.com"
  TOKEN_ENV_VARS = %w{NODERINGS_TOKEN NODERINGS_API_TOKEN NR_API_TOKEN}.freeze

  # gRPC status codes carried in the API's error bodies.
  CODE_INVALID_ARGUMENT = 3
  CODE_NOT_FOUND = 5
  CODE_ALREADY_EXISTS = 6
  CODE_PERMISSION_DENIED = 7
  CODE_FAILED_PRECONDITION = 9
  CODE_UNAUTHENTICATED = 16

  UUID_RE = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # Network failures that may or may not have reached the API.
  CONNECTION_ERRORS = [
    SocketError, IOError, EOFError, SystemCallError, Timeout::Error,
    Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
  ].freeze

  # An error the NodeRings API returned.
  class APIError < StandardError
    attr_reader :status, :code, :api_message, :details, :http_method, :path

    def initialize(status, code = 0, message = "", details = nil, http_method = "", path = "")
      @status = status
      @code = code
      @api_message = message.to_s.strip
      @details = details || []
      @http_method = http_method
      @path = path
      super(build_message)
    end

    def quota_info
      @details.find do |d|
        d.is_a?(Hash) && d["@type"].to_s.end_with?("google.rpc.ErrorInfo") &&
          d["reason"].to_s.end_with?("LIMIT_REACHED")
      end
    end

    def quota?
      !quota_info.nil?
    end

    def not_found?
      @code == CODE_NOT_FOUND
    end

    # The API refuses changes while a VM operation is running.
    def busy?
      @code == CODE_FAILED_PRECONDITION && @api_message.downcase.include?("in progress")
    end

    # True when the request may or may not have been applied (lost response).
    def ambiguous?
      return true if [502, 503, 504].include?(@status)
      return !quota? if @status == 429

      false
    end

    private

    def build_message
      msg = @api_message.empty? ? "HTTP #{@status}" : @api_message
      meta = (quota_info || {})["metadata"] || {}
      return "#{msg} (quota #{meta["limit_key"]}: #{meta["current"]} of #{meta["limit"]} used)" if meta.key?("limit")

      where = @http_method.to_s.empty? ? "" : " on #{@http_method} #{@path}"
      "#{msg} (HTTP #{@status}#{where})"
    end
  end

  # A wait ran out of time.
  class WaitTimeout < StandardError; end

  # The caller asked for something that cannot work (bad name, ambiguous match, no offer).
  class UsageError < StandardError; end

  module_function

  def decode_error(status, body, http_method = "", path = "")
    code = 0
    message = ""
    details = []
    begin
      data = JSON.parse(body.to_s.empty? ? "{}" : body.to_s)
      if data.is_a?(Hash)
        code = data["code"].to_i
        message = data["message"].to_s
        details = data["details"] || []
      else
        message = data.to_s[0, 300]
      end
    rescue JSON::ParserError
      message = body.to_s.strip[0, 300]
    end
    if code == 0
      code = { 404 => CODE_NOT_FOUND, 409 => CODE_ALREADY_EXISTS, 403 => CODE_PERMISSION_DENIED,
               401 => CODE_UNAUTHENTICATED }.fetch(status, 0)
    end
    APIError.new(status, code, message, details, http_method, path)
  end

  def ambiguous?(err)
    return err.ambiguous? if err.is_a?(APIError)

    CONNECTION_ERRORS.any? { |k| err.is_a?(k) }
  end

  def not_found?(err)
    err.is_a?(APIError) && err.not_found?
  end

  def uuid?(value)
    UUID_RE.match?(value.to_s)
  end

  def new_uuid
    SecureRandom.uuid
  end

  def escape(value)
    URI.encode_www_form_component(value.to_s).gsub("+", "%20")
  end

  # BILLING_TYPE_USAGE -> usage
  def trim_enum(value, prefix)
    return "" if value.nil? || value.to_s.empty?

    v = value.to_s.delete_prefix(prefix)
    v == "UNSPECIFIED" ? "" : v.downcase
  end

  def find_by_name(items, name)
    Array(items).find { |i| i["name"] == name }
  end

  # Sends requests over Net::HTTP. Returns [status, body].
  class NetHTTPTransport
    def call(http_method, url, headers, body, timeout)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = [timeout, 30].min
      http.read_timeout = timeout
      req = Net::HTTPGenericRequest.new(http_method, !body.nil?, true, uri.request_uri, headers)
      req.body = body if body
      res = http.start { |h| h.request(req) }
      [res.code.to_i, res.body.to_s]
    end
  end

  # JSON client for the NodeRings public API.
  class Client
    attr_reader :base, :organization_id, :user_agent

    def initialize(token:, api_url: nil, organization_id: nil, timeout: 60, retries: 5,
      user_agent: nil, transport: nil, sleeper: nil)
      if token.nil? || token.to_s.strip.empty?
        raise UsageError, "A NodeRings API token is required. Set provider.token in the Vagrantfile, or the " \
                          "NODERINGS_TOKEN environment variable. Create a service account token in the NodeRings " \
                          "console under Organization, Access Control, Service accounts."
      end
      @base = (api_url.to_s.empty? ? DEFAULT_API_URL : api_url.to_s).chomp("/")
      raise UsageError, "api_url must be an absolute URL such as #{DEFAULT_API_URL}" unless @base.start_with?("https://", "http://")

      @token = token.to_s.strip
      @organization_id = organization_id.to_s.strip
      @timeout = Integer(timeout)
      @retries = [0, Integer(retries)].max
      @user_agent = user_agent || "noderings-ruby"
      @transport = transport || NetHTTPTransport.new
      @sleeper = sleeper || ->(s) { sleep(s) }
    end

    # Keep the token out of inspect output and logs.
    def inspect
      "#<#{self.class.name} base=#{@base}>"
    end

    def sleep_for(seconds)
      @sleeper.call(seconds)
    end

    # Sends one request and returns the decoded JSON body, or {}.
    #
    # GET requests retry on 503; writes do not, because some write endpoints
    # (DNS) report validation errors as 503.
    def request(http_method, path, query: nil, body: nil, retry_unavailable: nil, retries: nil)
      retry_unavailable = (http_method == "GET") if retry_unavailable.nil?
      max_retries = retries.nil? ? @retries : retries
      url = @base + path
      qs = encode_query(query)
      url += "?#{qs}" unless qs.empty?
      headers = {
        "Authorization" => "Bearer #{@token}",
        "Accept" => "application/json",
        "User-Agent" => @user_agent,
      }
      payload = nil
      unless body.nil?
        payload = JSON.generate(body)
        headers["Content-Type"] = "application/json"
      end
      headers["X-Organization-ID"] = @organization_id unless @organization_id.empty?

      attempt = 0
      loop do
        err = nil
        begin
          status, raw = @transport.call(http_method, url, headers, payload, @timeout)
          if status < 300
            return {} if raw.nil? || raw.strip.empty?

            return JSON.parse(raw)
          end
          err = NoderingsVagrant.decode_error(status, raw, http_method, path)
        rescue *CONNECTION_ERRORS => e
          err = e
        end
        raise err if attempt >= max_retries || !retryable?(err, retry_unavailable)

        sleep_for(backoff(attempt))
        attempt += 1
      end
    end

    def get(path, query = nil)
      request("GET", path, query: query)
    end

    def list_all(path, key, query = {})
      get(path, { "page" => "0", "pageSize" => "-1" }.merge(query))[key] || []
    end

    def list_paged(path, key, query = {}, page_size = 100)
      out = []
      page = 0
      loop do
        data = get(path, { "page" => page.to_s, "pageSize" => page_size.to_s }.merge(query))
        items = data[key] || []
        out.concat(items)
        return out if items.length < page_size || out.length >= data["totalCount"].to_i

        page += 1
      end
    end

    # -- organization -----------------------------------------------------------

    def organization
      get("/v1/organization")["organization"]
    end

    def credit_balance
      get("/v1/credits/balance")
    end

    # -- SSH keys -----------------------------------------------------------------

    def list_ssh_keys
      list_all("/v1/ssh-keys", "sshKeys")
    end

    def create_ssh_key(name, public_key)
      request("POST", "/v1/ssh-keys", body: { "name" => name, "publicKey" => public_key })["sshKey"]
    end

    def delete_ssh_key(key_id)
      request("DELETE", "/v1/ssh-keys/#{NoderingsVagrant.escape(key_id)}")
    end

    # -- DNS ----------------------------------------------------------------------

    def zone_path(zone_id)
      "/v1/dns/zones/#{NoderingsVagrant.escape(zone_id)}"
    end

    def list_dns_zones
      list_all("/v1/dns/zones", "zones")
    end

    def get_dns_zone(zone_id)
      get(zone_path(zone_id))["zone"]
    end

    def create_dns_zone(name)
      request("POST", "/v1/dns/zones", body: { "name" => name })["zone"]
    end

    def delete_dns_zone(zone_id, force: false)
      request("DELETE", zone_path(zone_id), query: force ? { "force" => "true" } : nil)
    end

    def list_dns_records(zone_id, name: nil, type: nil)
      list_paged("#{zone_path(zone_id)}/records", "records", { "name" => name, "type" => type })
    end

    def upsert_dns_record(zone_id, record)
      request("PUT", "#{zone_path(zone_id)}/records", body: { "record" => record })
    end

    def delete_dns_record(zone_id, name, type)
      request("DELETE", "#{zone_path(zone_id)}/records", query: { "name" => name, "type" => type })
    end

    def get_dnssec(zone_id)
      get("#{zone_path(zone_id)}/dnssec")
    end

    def enable_dnssec(zone_id)
      request("POST", "#{zone_path(zone_id)}/dnssec/enable", body: {})
    end

    def disable_dnssec(zone_id, force: false)
      request("POST", "#{zone_path(zone_id)}/dnssec/disable", body: { "force" => force })
    end

    # -- firewall -----------------------------------------------------------------

    def list_firewall_address_groups(name = nil)
      list_all("/v1/firewall/address-groups", "groups", { "name" => name })
    end

    def list_firewall_rulesets(name = nil)
      list_all("/v1/firewall/rulesets", "rulesets", { "name" => name })
    end

    def create_firewall_ruleset(name)
      out = request("POST", "/v1/firewall/rulesets", body: { "ruleset" => { "name" => name } })["ruleset"]
      return out if out && out["id"]

      NoderingsVagrant.find_by_name(list_firewall_rulesets(name), name)
    end

    def delete_firewall_ruleset(ruleset_id, force: false)
      request("DELETE", "/v1/firewall/rulesets/#{NoderingsVagrant.escape(ruleset_id)}",
        query: force ? { "force" => "true" } : nil)
    end

    def list_firewall_rules(ruleset_id)
      list_all("/v1/firewall/rulesets/#{NoderingsVagrant.escape(ruleset_id)}/rules", "rules")
        .sort_by { |r| r["position"].to_i }
    end

    def create_firewall_rule(ruleset_id, rule)
      request("POST", "/v1/firewall/rulesets/#{NoderingsVagrant.escape(ruleset_id)}/rules",
        body: { "rule" => rule })["rule"]
    end

    def update_firewall_rule(rule_id, rule)
      request("PATCH", "/v1/firewall/rules/#{NoderingsVagrant.escape(rule_id)}", body: { "rule" => rule })
    end

    def move_firewall_rule(rule_id, target_id, position = "FIREWALL_RULE_POSITION_BEFORE")
      request("POST", "/v1/firewall/rules/#{NoderingsVagrant.escape(rule_id)}/move",
        body: { "targetRuleId" => target_id, "position" => position })
    end

    def delete_firewall_rule(rule_id)
      request("DELETE", "/v1/firewall/rules/#{NoderingsVagrant.escape(rule_id)}")
    end

    # -- virtual machines ---------------------------------------------------------

    def vm_path(vm_id)
      "/v1/virtual-machines/#{NoderingsVagrant.escape(vm_id)}"
    end

    def list_virtual_machines
      list_all("/v1/virtual-machines", "virtualMachines")
    end

    def get_virtual_machine(vm_id)
      vm = get(vm_path(vm_id))
      raise APIError.new(404, CODE_NOT_FOUND, "virtual machine #{vm_id} not found") if vm.nil? || vm["id"].to_s.empty?

      vm
    end

    # Never retried blindly: the caller handles ambiguous failures.
    def create_virtual_machine(body)
      request("POST", "/v1/virtual-machines", body: body, retries: 0)["virtualMachine"]
    end

    def update_virtual_machine_tags(vm_id, add: [], remove: [])
      request("PATCH", vm_path(vm_id), body: { "addTags" => add, "removeTags" => remove })
    end

    def delete_virtual_machine(vm_id)
      request("DELETE", vm_path(vm_id))
    end

    def vm_action(vm_id, action, body = {})
      request("POST", "#{vm_path(vm_id)}:#{action}", body: body)
    end

    # -- marketplace and catalog --------------------------------------------------

    def list_marketplace_regions(asset_type = nil)
      get("/v1/marketplace/regions", { "filterAssetType" => asset_type })["regions"] || []
    end

    def list_available_plans(country: nil, city: nil, billing_type: nil, asset_type: nil)
      get("/v1/marketplace/plans", {
            "filterCountry" => country, "filterCity" => city,
            "filterBillingType" => billing_type, "filterAssetType" => asset_type
          })["plans"] || []
    end

    def get_marketplace_plan(plan_id)
      get("/v1/marketplace/plans/#{NoderingsVagrant.escape(plan_id)}")
    end

    def list_providers(plan_code, country, city, billing_type: nil, ipv6_only: false)
      query = {
        "page" => "0", "pageSize" => "-1", "filterPlanCode" => plan_code,
        "filterCountry" => country, "filterCity" => city, "filterBillingType" => billing_type
      }
      query["filterIpv6AvailableOnly"] = "true" if ipv6_only
      get("/v1/marketplace/providers", query)["providers"] || []
    end

    def get_provider(provider_id)
      get("/v1/marketplace/providers/#{NoderingsVagrant.escape(provider_id)}")["provider"]
    end

    def list_distros
      get("/v1/distros")["distros"] || []
    end

    private

    def encode_query(query)
      return "" if query.nil?

      pairs = []
      query.keys.sort.each do |key|
        value = query[key]
        next if value.nil? || value == ""

        case value
        when Array then value.each { |v| pairs << [key, v.to_s] }
        when true, false then pairs << [key, value ? "true" : "false"]
        else pairs << [key, value.to_s]
        end
      end
      URI.encode_www_form(pairs)
    end

    def backoff(attempt)
      delay = [0.5 * (2**[attempt, 10].min), 10.0].min
      (delay / 2) + (rand * delay / 2)
    end

    def retryable?(err, retry_unavailable)
      return true unless err.is_a?(APIError)
      return !err.quota? if err.status == 429
      return true if [502, 504].include?(err.status)
      return retry_unavailable if err.status == 503

      false
    end
  end

  # Polls with a growing interval until a check reports done or a timeout passes.
  class Waiter
    def initialize(timeout, sleeper:, interval: 2.0, max_interval: 15.0, clock: nil)
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @deadline = @clock.call + timeout
      @interval = interval
      @max_interval = max_interval
      @sleeper = sleeper
    end

    # The block returns [done, value].
    def wait(what)
      delay = @interval
      loop do
        done, value = yield
        return value if done
        raise WaitTimeout, "timed out waiting for #{what}" if @clock.call + delay > @deadline

        @sleeper.call(delay)
        delay = [delay * 1.5, @max_interval].min
      end
    end

    # Runs the block until the VM stops reporting 'operation in progress'.
    def retry_busy
      last = nil
      wait("the virtual machine to finish its current operation") do
        [true, yield]
      rescue APIError => e
        raise unless e.busy?

        last = e
        [false, nil]
      end
    rescue WaitTimeout => e
      raise WaitTimeout, "#{e.message} (last error: #{last})"
    end
  end
end
