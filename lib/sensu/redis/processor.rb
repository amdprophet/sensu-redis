require "sensu/redis/constants"
require "sensu/redis/errors"

module Sensu
  module Redis
    # Sensu Module for processing Redis responses.
    # This module calls methods provided by other Sensu Redis modules:
    #   Sensu::Redis::Connection.error()
    module Processor
      # Fetch the next Redis command response callback. Response
      # callbacks may include an optional response processor block,
      # i.e. "1" -> true.
      #
      # @return [Array] processor, callback.
      def fetch_response_callback
        @response_callbacks ||= []
        @response_callbacks.shift
      end

      # Begin a multi bulk response array for an expected number of
      # responses. Using this method causes `dispatch_response()` to
      # wait until all of the expected responses have been added to
      # the array, before the Redis command reponse callback is
      # called.
      #
      # @param multibulk_count [Integer] number of expected responses.
      def begin_multibulk(multibulk_count)
        @multibulk_count = multibulk_count
        @multibulk_values = []
      end

      # Dispatch a Redis error, dropping the associated Redis command
      # response callback, and passing a Redis error object to the
      # error callback (if set).
      #
      # @param code [String] Redis error code.
      def dispatch_error(code)
        fetch_response_callback
        error(CommandError, code)
      end

      # Dispatch a response. If a multi bulk response has begun, this
      # method will build the completed response array before the
      # associated Redis command response callback is called. If one
      # or more pubsub callbacks are defined, the approprate pubsub
      # callbacks are called, provided with the pubsub response. Redis
      # command response callbacks may have an optional processor
      # block, responsible for producing a value with the correct
      # type, e.g. "1" -> true (boolean).
      #
      # @param value [Object]
      def dispatch_response(value)
        if @multibulk_count
          @multibulk_values << value
          @multibulk_count -= 1
          if @multibulk_count == 0
            value = @multibulk_values
            @multibulk_count = false
          else
            return
          end
        end
        if @pubsub_callbacks && value.is_a?(Array)
          if PUBSUB_RESPONSES.include?(value[0])
            @pubsub_callbacks[value[1]].each do |block|
              block.call(*value) if block
            end
            return
          end
        end
        processor, block = fetch_response_callback
        if block
          value = processor.call(value) if processor
          block.call(value)
        end
      end
    end
  end
end
