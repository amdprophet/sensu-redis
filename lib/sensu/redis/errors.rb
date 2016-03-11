module Sensu
  module Redis
    # Error class for Redis connection errors.
    class ConnectionError < StandardError; end

    # Error class for Redis protocol (RESP) errors.
    class ProtocolError < StandardError; end

    # Error class for Redis command errors.
    class CommandError < StandardError
      attr_accessor :code

      def initialize(*args)
        args[0] = "redis returned error code: #{args[0]}"
        super
      end
    end
  end
end
