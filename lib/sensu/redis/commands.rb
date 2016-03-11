require "sensu/redis/constants"
require "sensu/redis/errors"

module Sensu
  module Redis
    # Sensu Module for requesting Redis commands, intended to be
    # included by Sensu::Redis::Client.
    #
    # You can read about RESP @ http://redis.io/topics/protocol
    module Commands
      # Determine the byte size of a string.
      #
      # @param string [String]
      # @return [Integer] string byte size.
      def get_size(string)
        string.respond_to?(:bytesize) ? string.bytesize : string.size
      end

      # Send a Redis command using RESP multi bulk. This method sends
      # data to Redis using EM connection `send_data()`.
      #
      # @params [Array<Object>] *arguments
      def send_command_data(*arguments)
        data = "*#{arguments.size}#{DELIM}"
        arguments.each do |value|
          value = value.to_s
          data << "$#{get_size(value)}#{DELIM}#{value}#{DELIM}"
        end
        send_data(data)
      end

      # Send a Redis command and queue the associated response
      # callback. This method calls `send_command_data()` for RESP
      # multi bulk and transmission.
      #
      # @params command [String]
      # @params [Array<Object>] *arguments
      # @yield command reponse callback
      def send_command(command, *arguments, &block)
        @response_callbacks ||= []
        send_command_data(command, *arguments)
        @response_callbacks << [RESPONSE_PROCESSORS[command], block]
      end

      # Send a Redis command once the Redis connection has been
      # established (EM Deferable succeeded).
      #
      # @params command [String]
      # @params [Array<Object>] *arguments
      # @yield command reponse callback
      def redis_command(command, *arguments, &block)
        if @deferred_status == :succeeded
          send_command(command, *arguments, &block)
        else
          callback do
            send_command(command, *arguments, &block)
          end
        end
      end

      # Create Redis command methods. Command methods wrap
      # `redis_command()`. This method MUST be called in
      # `initialize()`.
      def create_command_methods!
        REDIS_COMMANDS.each do |command|
          self.class.send(:define_method, command.to_sym) do |*arguments, &block|
            redis_command(command, *arguments, &block)
          end
        end
      end

      # Subscribe to a Redis PubSub channel.
      #
      # @param channel [String]
      # @yield channel message callback
      def subscribe(channel, &block)
        @pubsub_callbacks ||= Hash.new([])
        @pubsub_callbacks[channel] << block
        redis_command(SUBSCRIBE_COMMAND, channel, &block)
      end

      # Unsubscribe to one or more Redis PubSub channels. If a channel
      # is provided, this method will unsubscribe from it. If a
      # channel is not provided, this method will unsubscribe from all
      # Redis PubSub channels.
      #
      # @param channel [String]
      # @yield unsubscribe callback
      def unsubscribe(channel=nil, &block)
        @pubsub_callbacks ||= Hash.new([])
        arguments = [UNSUBSCRIBE_COMMAND]
        if channel
          @pubsub_callbacks[channel] = [block]
          arguments << channel
        else
          @pubsub_callbacks.each_key do |key|
            @pubsub_callbacks[key] = [block]
          end
        end
        redis_command(arguments)
      end
    end
  end
end
