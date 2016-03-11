require "sensu/redis/constants"
require "sensu/redis/errors"

module Sensu
  module Redis
    # Sensu Module for requesting Redis commands.
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
        send_data(command)
      end

      # Create Redis command methods. Command methods just wrap
      # `send_command()` and enqueue a response callback. This method
      # MUST be called in the connection object's `initialize()`.
      def self.create_command_methods
        @response_callbacks ||= []
        REDIS_COMMANDS.each do |command|
          define_method(command.to_sym) do |*arguments, &callback|
            send_command(command, *arguments)
            @response_callbacks << [RESPONSE_PROCESSORS[command], callback]
          end
        end
      end

      def select(db, &callback)
        @db = db.to_i
        send_command(['select', @db], &callback)
      end

      def auth(password, &callback)
        @password = password
        send_command(['auth', password], &callback)
      end

      def subscribe(channel, &callback)
        @pubsub_callbacks ||= Hash.new([])
        @pubsub_callbacks[channel] << callback
        send_command(['subscribe', channel], &callback)
      end

      def unsubscribe(channel=nil, &callback)
        @pubsub_callbacks ||= Hash.new([])
        arguments = ["unsubscribe"]
        if channel
          @pubsub_callbacks[channel] = [callback]
          arguments << channel
        else
          @pubsub_callbacks.each_key do |key|
            @pubsub_callbacks[key] = [callback]
          end
        end
        send_command(arguments)
      end
    end
  end
end
