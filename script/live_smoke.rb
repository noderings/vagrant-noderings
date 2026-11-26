#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only smoke of the NodeRings API client used by the Vagrant provider.
# Exits 0 when NODERINGS_TOKEN is not set.

require_relative "../lib/vagrant-noderings/api/client"

token = NoderingsVagrant::TOKEN_ENV_VARS.map { |k| ENV[k] }.find { |v| !v.to_s.empty? }
if token.to_s.empty?
  warn "NODERINGS_TOKEN is not set; skipping live smoke."
  exit 0
end

client = NoderingsVagrant::Client.new(token: token)
org = client.organization
abort "organization response was empty" if org.nil? || (org.respond_to?(:empty?) && org.empty?)
keys = client.list_ssh_keys
abort "list_ssh_keys did not return an Array (got #{keys.class})" unless keys.is_a?(Array)
puts "ok: organization reachable, #{keys.size} SSH key(s) listed"
