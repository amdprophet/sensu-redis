module Sensu
  module Redis
    class ProtocolError < StandardError; end

    class Error < StandardError
      attr_accessor :code

      def initialize(*args)
        args[0] = "redis returned error code: #{args[0]}"
        super
      end
    end
  end
end
