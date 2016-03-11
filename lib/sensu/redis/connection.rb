require "sensu/redis/constants"
require "sensu/redis/errors"

module Sensu
  module Redis
    # Sensu Module connecting to Redis.
    module Connection
      # Initialize the connection, creating the Redis command methods,
      # and setting the default connection options and callbacks.
      def initialize(options={})
        create_command_methods!
        @host = options[:host]
        @port = options[:port]
        @db = (options[:db] || 0).to_i
        @password = options[:password]
        @auto_reconnect = options.fetch(:auto_reconnect, true)
        @reconnect_on_error = options.fetch(:reconnect_on_error, true)
        @error_callback = lambda do |error|
          raise(error)
        end
        @reconnect_callbacks = {
          :before => lambda{},
          :after  => lambda{}
        }
      end

      # Set the connection error callback. This callback is called
      # when the connection encounters either a connection, protocol,
      # or command error.
      def on_error(&block)
        @error_callback = block
      end

      # Set the connection before reconnect callback. This callback is
      # called after the connection closes but before a reconnect is
      # attempted.
      def before_reconnect(&block)
        @reconnect_callbacks[:before] = block
      end

      # Set the connection after reconnect callback. This callback is
      # called after a successful reconnect, after the connection has
      # been validated.
      def after_reconnect(&block)
        @reconnect_callbacks[:after] = block
      end

      # Create an error and pass it to the connection error callback.
      #
      # @param klass [Class]
      # @param message [String]
      def error(klass, message)
        redis_error = klass.new(message)
        @error_callback.call(redis_error)
      end

      # Determine if the connection is connected to Redis.
      def connected?
        @connected || false
      end

      # Reconnect to Redis. The before reconnect callback is first
      # called if not already reconnecting. This method uses a 1
      # second delay before attempting a reconnect.
      def reconnect!
        @reconnect_callbacks[:before].call unless @reconnecting
        @reconnecting = true
        EM.add_timer(1) do
          reconnect(@host, @port)
        end
      end

      # Close the Redis connection after writing the current
      # Redis command data.
      def close
        @closing = true
        close_connection_after_writing
      end

      # This method is called by EM when the connection closes, either
      # intentionally or unexpectedly. This method is reponsible for
      # starting the reconnect process when appropriate.
      def unbind
        @deferred_status = nil
        if @closing
          @reconnecting = false
        elsif ((@connected || @reconnecting) && @auto_reconnect) || @reconnect_on_error
          reconnect!
        elsif @connected
          error(ConnectionError, "connection closed")
        else
          error(ConnectionError, "unable to connect to redis server")
        end
        @connected = false
      end

      # Authenticate to Redis if a password has been set in the
      # connection options. This method uses `send_command()`
      # directly, as it assumes that the connection has been
      # established. Redis authentication must be done prior to
      # issuing other Redis commands.
      #
      # @yield the callback called once authenticated.
      def authenticate
        if @password
          send_command(AUTH_COMMAND, @password) do |authenticated|
            if authenticated
              yield if block_given?
            else
              error(ConnectionError, "redis authenticate failed")
            end
          end
        else
          yield if block_given?
        end
      end

      # Select a Redis DB if a DB has been set in the connection
      # options. This method (& Redis command) does not require a
      # response callback.
      def select_db
        send_command(SELECT_COMMAND, @db) if @db
      end

      # Verify the version of Redis. Redis >= 2.0 RC 1 is required for
      # certain Redis commands that Sensu uses. A connection error is
      # created if the Redis version does not meet the requirements.
      #
      # @yield the callback called once verified.
      def verify_version
        send_command(INFO_COMMAND) do |redis_info|
          if redis_info[:redis_version] < "1.3.14"
            error(ConnectionError, "redis version must be >= 2.0 RC 1")
          else
            yield if block_given?
          end
        end
      end

      # This method is called by EM when the connection is
      # established. This method is reponsible for validating the
      # connection before Redis commands can be sent.
      def connection_completed
        @response_callbacks = []
        @multibulk_count = false
        @connected = true
        authenticate do
          select_db
          verify_version do
            succeed
            @reconnect_callbacks[:after].call if @reconnecting
            @reconnecting = false
          end
        end
      end
    end
  end
end
