require "sensu/redis/constants"
require "sensu/redis/errors"

module Sensu
  module Redis
    # Sensu Module for processing Redis responses.
    module Processor
      # Fetch the next Redis command response callback. Response
      # callbacks may include an optional response processor block,
      # i.e. "1" -> false.
      #
      # @return [Array] processor, callback.
      def fetch_response_callback
        @response_callbacks ||= []
        @response_callbacks.shift
      end

      # Begin a multibulk response array for an expected number of
      # responses. Using this method causes `dispatch_response()` to
      # wait until all of the expected responses have been added to
      # the array, before calling the Redis command reponse callback.
      #
      # @param multibulk_count [Integer] number of expected responses.
      def begin_multibulk(multibulk_count)
        @multibulk_count = multibulk_count
        @multibulk_values = []
      end

      # Create an exception and pass it to the error callback if set.
      #
      # @param klass [Class]
      # @param message [String]
      def error(klass, message)
        exception = klass.new(message)
        @error_callback.call(exception) if @error_callback
      end

      # Dispatch a Redis error, dropping the associated Redis command
      # response callback, and passing a Redis error exception to the
      # error callback (if set).
      #
      # @param code [String] Redis error code.
      def dispatch_error(code)
        fetch_response_callback
        error(Sensu::Redis::Error, code)
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
            @pubsub_callbacks[value[1]].each do |callback|
              callback.call(*value) if callback
            end
            return
          end
        end
        processor, callback = fetch_response_callback
        value = processor.call(value) if processor
        callback.call(value) if callback
      end
    end
  end
end
