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

      # Send a Redis command using RESP multi bulk. This method is
      # called by the Redis command methods, which are created by
      # `create_command_methods()`, it simply implements RESP and
      # sends commands to Redis via EM connection `send_data()`.
      def send_command(*arguments)
        command = "*#{arguments.size}#{DELIM}"
        arguments.each do |value|
          value = value.to_s
          command << "$#{get_size(value)}#{DELIM}#{value}#{DELIM}"
        end
        callback { send_data(command) }
      end

      # Create Redis command methods. Command methods just wrap
      # `send_command()` and enqueue a response callback. This method
      # MUST be called in the connection object's `initialize()`.
      def create_command_methods!
        @response_callbacks ||= []
        REDIS_COMMANDS.each do |command|
          self.class.send(:define_method, command.to_sym) do |*arguments, &block|
            send_command(command, *arguments)
            @response_callbacks << [RESPONSE_PROCESSORS[command], block]
          end
        end
      end

      # Authenticate to Redis and select the correct DB, when
      # applicable. The auth and select Redis commands must be the
      # first commands (& callbacks) to run.
      #
      # @param password [String]
      # @param db [Integer]
      def auth_and_select_db(password=nil, db=nil)
        callbacks = @callbacks || []
        @callbacks = []
        send_command(AUTH_COMMAND, password) if password
        send_command(SELECT_COMMAND, db) if db
        callbacks.each { |block| callback(&block) }
      end

      # Subscribe to a Redis PubSub channel.
      #
      # @param channel [String]
      def subscribe(channel, &block)
        @pubsub_callbacks ||= Hash.new([])
        @pubsub_callbacks[channel] << block
        send_command(SUBSCRIBE_COMMAND, channel, &block)
      end

      # Unsubscribe to one or more Redis PubSub channels. If a channel
      # is provided, this method will unsubscribe from it. If a
      # channel is not provided, this method will unsubscribe from all
      # Redis PubSub channels.
      #
      # @param channel [String]
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
        send_command(arguments)
      end
    end
  end
end
