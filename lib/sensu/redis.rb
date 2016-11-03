require "rubygems"
require "sensu/redis/utilities"
require "sensu/redis/client"
require "sensu/redis/sentinel"
require "eventmachine"
require "uri"

module Sensu
  module Redis
    class << self
      include Utilities

      # Set the Redis logger.
      #
      # @param logger [Object] Redis logger.
      def logger=(logger)
        @logger = logger
      end

      # Parse a Redis URL. An argument error exception is thrown if
      # this method is unable to parse the provided URL string.
      #
      # @param url [String]
      # @return [Hash] Redis connection options.
      def parse_url(url)
        begin
          uri = URI.parse(url)
          {
            :host => uri.host,
            :port => uri.port,
            :password => uri.password
          }
        rescue
          raise ArgumentError, "invalid redis url"
        end
      end

      # Connect to the current Redis master via Sentinel. Sentinel
      # will resolve the current Redis master host and port.
      #
      # @param options [Hash]
      # @yield callback to be called with the redis connection object.
      def connect_via_sentinel(options, &block)
        sentinel = Sentinel.new(options)
        sentinel.resolve do |host, port|
          redis = EM.connect(host, port, Client, options)
          redis.logger = @logger
          redis.sentinel = sentinel
          block.call(redis)
        end
      end

      # Connect to the current Redis master directly, using the
      # provided connection options. This method uses `resolve_host()`
      # to first resolve the provided host, if it's not already an IP
      # address. Resolving the hostname upfront guards against lookup
      # failures that would cause the Sensu process to crash. Upfront
      # hostname resolution also allows this Redis library to work
      # with Amazon AWS ElastiCache.
      #
      # @param options [Hash]
      # @yield callback to be called with the redis connection object.
      def connect_direct(options, &block)
        resolve_host(options[:host]) do |ip_address|
          if ip_address.nil?
            EM::Timer.new(1) do
              connect_direct(options, &block)
            end
          else
            redis = EM.connect(ip_address, options[:port], Client, options)
            redis.logger = @logger
            block.call(redis)
          end
        end
      end

      # Connect to Redis using the provided connection options.
      #
      # @param options [String,Hash]
      # @yield callback to be called with the redis connection object.
      def connect(options={}, &block)
        case options
        when String
          options = parse_url(options)
        when nil
          options = {}
        end
        options[:host] ||= "127.0.0.1"
        options[:port] ||= 6379
        case
        when options[:sentinels].is_a?(String)
          raw_urls = options[:sentinels]
          options[:sentinels] = raw_urls.split(',').map { |url| parse_url(url) }
        when options[:sentinels].is_a?(Array) && options[:sentinels].length > 0
          connect_via_sentinel(options, &block)
        else
          connect_direct(options, &block)
        end
      end
    end
  end
end
