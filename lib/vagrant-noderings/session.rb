# frozen_string_literal: true

require "fileutils"
require "openssl"
require "securerandom"
require_relative "api/compute"
require_relative "version"

module VagrantPlugins
  module Noderings
    # The API client and the per-machine files the provider keeps in .vagrant/.
    class Session
      # Tests plug an in-memory API in here.
      class << self
        attr_accessor :transport, :sleeper
      end

      attr_reader :machine

      def initialize(machine)
        @machine = machine
      end

      def config
        machine.provider_config
      end

      def client
        @client ||= NoderingsVagrant::Client.new(
          token: config.token, api_url: config.api_url, organization_id: config.organization_id,
          user_agent: "vagrant-noderings/#{VERSION} (Vagrant #{Vagrant::VERSION})",
          transport: self.class.transport, sleeper: self.class.sleeper
        )
      end

      def compute
        NoderingsVagrant::Compute
      end

      # Runs an API call and turns its failure into a Vagrant error with the API's message.
      def call(what)
        yield
      rescue NoderingsVagrant::APIError, NoderingsVagrant::UsageError, NoderingsVagrant::WaitTimeout,
             *NoderingsVagrant::CONNECTION_ERRORS => e
        raise Errors::APIError, action: what, message: e.message
      end

      def dir
        path = machine.data_dir.join("state")
        FileUtils.mkdir_p(path)
        path
      end

      # The hostname to order with: configured, or remembered from the first `up`.
      def hostname
        return config.hostname if config.hostname

        file = dir.join("hostname")
        return file.read.strip if file.exist?

        base = "vagrant-#{machine.name}".downcase.gsub(/[^a-z0-9-]+/, "-").squeeze("-")
        name = "#{base[0, 56].chomp('-')}-#{SecureRandom.alphanumeric(6).downcase}"
        file.write(name)
        name
      end

      def private_key_path
        dir.join("id_rsa")
      end

      def generated_key?
        private_key_path.exist?
      end

      # NodeRings SSH key IDs to install: the configured ones, or a key generated for
      # this machine and uploaded as a temporary key.
      def ssh_key_ids
        return call("resolving SSH keys") { compute.resolve_ssh_keys(client, config.ssh_keys) } unless config.ssh_keys.empty?

        unless generated_key?
          key = OpenSSL::PKey::RSA.generate(3072)
          File.open(private_key_path, "w", 0o600) { |f| f.write(key.to_pem) }
        end
        id_file = dir.join("ssh_key_id")
        return [id_file.read.strip] if id_file.exist?

        uploaded = call("uploading the SSH key") { client.create_ssh_key("vagrant-#{hostname}", public_key) }
        id_file.write(uploaded["id"])
        [uploaded["id"]]
      end

      def public_key
        rsa = OpenSSL::PKey::RSA.new(private_key_path.read)
        str = ->(v) { [v.bytesize].pack("N") + v }
        mpint = ->(b) { str.call(b.getbyte(0).nobits?(0x80) ? b : "\0#{b}") }
        blob = str.call("ssh-rsa") + mpint.call(rsa.e.to_s(2)) + mpint.call(rsa.n.to_s(2))
        "ssh-rsa #{[blob].pack('m0')} vagrant-#{hostname}"
      end

      # Deletes the temporary key and every file the provider kept for this machine.
      def cleanup
        id_file = dir.join("ssh_key_id")
        if id_file.exist?
          call("deleting the temporary SSH key") do
            client.delete_ssh_key(id_file.read.strip)
          rescue NoderingsVagrant::APIError => e
            raise unless e.not_found?
          end
        end
        FileUtils.rm_rf(dir)
      end

      # The VM this machine points at, or nil when it is gone.
      def vm
        return nil if machine.id.nil?

        call("reading the server") do
          client.get_virtual_machine(machine.id)
        rescue NoderingsVagrant::APIError => e
          raise unless e.not_found?

          nil
        end
      end
    end
  end
end
