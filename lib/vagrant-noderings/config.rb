# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    # The `config.vm.provider :noderings` block.
    class Config < Vagrant.plugin("2", :config)
      TOKEN_ENV_VARS = %w[NODERINGS_TOKEN NODERINGS_API_TOKEN NR_API_TOKEN].freeze

      # @return [String] NodeRings service account token (default: NODERINGS_TOKEN)
      attr_accessor :token
      # @return [String] API endpoint (default: NODERINGS_API_URL, then https://api.noderings.com)
      attr_accessor :api_url
      # @return [String] organization to act in, for tokens that reach several
      attr_accessor :organization_id
      # @return [String] plan code to order, such as SC-GC-1C-1G-20
      attr_accessor :plan
      # @return [String] country of the offer
      attr_accessor :country
      # @return [String] city of the offer
      attr_accessor :city
      # @return [String] usage, subscription or free
      attr_accessor :billing_type
      # @return [String] price (cheapest) or rating (best rated)
      attr_accessor :sort
      # @return [String] only consider offers from the provider with this ID (wins over hosting_provider)
      attr_accessor :provider_id
      # @return [String] only consider offers from this provider, given by ID, storefront slug or name
      attr_accessor :hosting_provider
      # @return [String] exact plan ID, instead of plan, country and city
      attr_accessor :plan_id
      # @return [String] exact region ID, with plan_id
      attr_accessor :region_id
      # @return [String] operating system, such as ubuntu_24_04
      attr_accessor :distro
      # @return [String] hostname of the server (default: vagrant-<machine>-<random>)
      attr_accessor :hostname
      # @return [Array<String>] existing NodeRings SSH key names or IDs; empty uploads a generated key
      attr_accessor :ssh_keys
      # @return [Array<String>] tags on the server
      attr_accessor :tags
      # @return [String] firewall ruleset name or ID to attach
      attr_accessor :firewall_ruleset
      # @return [Integer] seconds to wait for each operation
      attr_accessor :wait_timeout

      def initialize
        super
        @token = UNSET_VALUE
        @api_url = UNSET_VALUE
        @organization_id = UNSET_VALUE
        @plan = UNSET_VALUE
        @country = UNSET_VALUE
        @city = UNSET_VALUE
        @billing_type = UNSET_VALUE
        @sort = UNSET_VALUE
        @provider_id = UNSET_VALUE
        @hosting_provider = UNSET_VALUE
        @plan_id = UNSET_VALUE
        @region_id = UNSET_VALUE
        @distro = UNSET_VALUE
        @hostname = UNSET_VALUE
        @ssh_keys = UNSET_VALUE
        @tags = UNSET_VALUE
        @firewall_ruleset = UNSET_VALUE
        @wait_timeout = UNSET_VALUE
      end

      def finalize!
        @token = TOKEN_ENV_VARS.map { |v| ENV.fetch(v, nil) }.find { |v| !v.to_s.empty? } if @token == UNSET_VALUE
        @api_url = ENV.fetch("NODERINGS_API_URL", nil) if @api_url == UNSET_VALUE
        @organization_id = ENV.fetch("NODERINGS_ORGANIZATION_ID", nil) if @organization_id == UNSET_VALUE
        @billing_type = "usage" if @billing_type == UNSET_VALUE
        @sort = "price" if @sort == UNSET_VALUE
        @distro = "ubuntu_24_04" if @distro == UNSET_VALUE
        @ssh_keys = [] if @ssh_keys == UNSET_VALUE
        @tags = ["vagrant"] if @tags == UNSET_VALUE
        @wait_timeout = 900 if @wait_timeout == UNSET_VALUE
        %i[plan country city provider_id hosting_provider plan_id region_id hostname firewall_ruleset].each do |name|
          instance_variable_set("@#{name}", nil) if instance_variable_get("@#{name}") == UNSET_VALUE
        end
        @ssh_keys = Array(@ssh_keys)
        @tags = Array(@tags)
        @wait_timeout = Integer(@wait_timeout)
      end

      def validate(_machine)
        errors = _detected_errors
        errors << "token is required: set provider.token or the NODERINGS_TOKEN environment variable" if @token.to_s.empty?
        unless (@plan_id && @region_id) || (@plan && @country && @city)
          errors << "set plan, country and city (or plan_id and region_id) to choose what to order"
        end
        errors << "billing_type must be usage, subscription or free" unless %w[usage subscription free].include?(@billing_type.to_s)
        errors << "sort must be price or rating" unless %w[price rating].include?(@sort.to_s)
        if @hostname && @hostname !~ /\A[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/
          errors << "hostname must be one DNS label: letters, digits and hyphens, at most 63 characters"
        end
        { "NodeRings provider" => errors }
      end
    end
  end
end
