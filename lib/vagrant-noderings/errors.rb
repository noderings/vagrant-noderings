# frozen_string_literal: true

module VagrantPlugins
  module Noderings
    module Errors
      class NoderingsError < Vagrant::Errors::VagrantError
        error_namespace("vagrant_noderings.errors")
      end

      # Any failure from the NodeRings API, with its message.
      class APIError < NoderingsError
        error_key(:api_error)
      end

      class NoAddress < NoderingsError
        error_key(:no_address)
      end
    end
  end
end
