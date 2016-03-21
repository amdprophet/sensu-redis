require "sensu/redis/client/constants"
require "sensu/redis/client/errors"
require "eventmachine"

module Sensu
  module Redis
    class Client < EM::Connection
      include EM::Deferrable

      attr_accessor :sentinel, :auto_reconnect, :reconnect_on_error

      # Initialize the connection, creating the Redis command methods,
      # and setting the default connection options and callbacks.
      def initialize(options={})
        create_command_methods!
        @host = options[:host] || "127.0.0.1"
        @port = options[:port] || 6379
        @db = options[:db]
        @password = options[:password]
        @auto_reconnect = options.fetch(:auto_reconnect, true)
        @reconnect_on_error = options.fetch(:reconnect_on_error, true)
        @error_callback = Proc.new {}
        @reconnect_callbacks = {
          :before => Proc.new {},
          :after => Proc.new {}
        }
      end

      # Determine the current Redis master address. If Sentinel was
      # used to determine the original address, use it again. If
      # Sentinel is not being used, return the host and port used when
      # the connection was first established.
      #
      # @yield callback called when the current Redis master host and
      #   port has been determined.
      def determine_address(&block)
        if @sentinel
          @sentinel.resolve(&block)
        else
          block.call(@host, @port)
        end
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
      # This method will trigger a reconnect if `@reconnect_on_error`
      # is `true`.
      #
      # @param klass [Class]
      # @param message [String]
      def error(klass, message)
        redis_error = klass.new(message)
        @error_callback.call(redis_error)
        reconnect! if @reconnect_on_error
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
          determine_address do |host, port|
            reconnect(host, port)
          end
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

      # Send a Redis command using RESP multi bulk. This method sends
      # data to Redis using EM connection `send_data()`.
      #
      # @param [Array<Object>] *arguments
      def send_command_data(*arguments)
        data = "*#{arguments.length}#{DELIM}"
        arguments.each do |value|
          value = value.to_s
          data << "$#{value.bytesize}#{DELIM}#{value}#{DELIM}"
        end
        send_data(data)
      end

      # Send a Redis command and queue the associated response
      # callback. This method calls `send_command_data()` for RESP
      # multi bulk and transmission.
      #
      # @param command [String]
      # @param [Array<Object>] *arguments
      # @yield command reponse callback
      def send_command(command, *arguments, &block)
        send_command_data(command, *arguments)
        @response_callbacks << [RESPONSE_PROCESSORS[command], block]
      end

      # Send a Redis command once the Redis connection has been
      # established (EM Deferable succeeded).
      #
      # @param command [String]
      # @param [Array<Object>] *arguments
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
      # `redis_command()`. This method is called by `initialize()`.
      def create_command_methods!
        COMMANDS.each do |command|
          self.class.send(:define_method, command.to_sym) do |*arguments, &block|
            redis_command(command, *arguments, &block)
          end
        end
      end

      # Subscribe to a Redis PubSub channel.
      #
      # @param channel [String]
      # @yield channel message callback.
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
      # @yield unsubscribe callback.
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
        @response_callbacks.shift
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
        processor, block = @response_callbacks.shift
        if block
          value = processor.call(value) if processor
          block.call(value)
        end
      end

      # Parse a RESP line. This method is called by `receive_data()`.
      # You can read about RESP @ http://redis.io/topics/protocol
      #
      # @param line [String]
      def parse_response_line(line)
        # Trim off the response type and delimiter (\r\n).
        response = line.slice(1..-3)
        # First character indicates response type.
        case line[0, 1]
        when MINUS # Error, e.g. -ERR
          dispatch_error(response)
        when PLUS # String, e.g. +OK
          dispatch_response(response)
        when DOLLAR # Bulk string, e.g. $3\r\nfoo\r\n
          response_length = Integer(response)
          if response_length == -1 # No data, return nil.
            dispatch_response(nil)
          elsif @buffer.length >= response_length + 2 # Complete data.
            dispatch_response(@buffer.slice!(0, response_length))
            @buffer.slice!(0,2) # Discard delimeter (\r\n).
          else # Incomplete, have data pushed back into buffer.
            return INCOMPLETE
          end
        when COLON # Integer, e.g. :8
          dispatch_response(Integer(response))
        when ASTERISK # Array, e.g. *2\r\n$3\r\foo\r\n$3\r\nbar\r\n
          multibulk_count = Integer(response)
          if multibulk_count == -1 || multibulk_count == 0 # No data, return [].
            dispatch_response([])
          else
            begin_multibulk(multibulk_count) # Accumulate responses.
          end
        else
          error(ProtocolError, "response type not recognized: #{line.strip}")
        end
      end

      # This method is called by EM when the connection receives data.
      # This method assumes that the incoming data is using RESP and
      # it is parsed by `parse_resp_line()`.
      #
      # @param data [String]
      def receive_data(data)
        (@buffer ||= '') << data
        while index = @buffer.index(DELIM)
          line = @buffer.slice!(0, index+2)
          if parse_response_line(line) == INCOMPLETE
            @buffer[0...0] = line
            break
          end
        end
      end
    end
  end
end
