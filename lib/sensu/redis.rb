require "rubygems"
require "sensu/redis/client"
require "sensu/redis/sentinel"
require "eventmachine"
require "uri"

module Sensu
  module Redis
    class << self
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

      def connect_via_sentinel(options, &block)
        sentinel = Sentinel.new(options)
        sentinel.callback do
          sentinel.resolve do |host, port|
            block.call(EM.connect(host, port, Client, options))
          end
        end
        sentinel.errback do
          EM::Timer.new(3) do
            connect_via_sentinel(options, &block)
          end
        end
      end

      def connect_direct(options, &block)
        block.call(EM.connect(options[:host], options[:port], Client, options))
      end

      def connect(options={}, &block)
        case options
        when String
          options = parse_url(options)
        when nil
          options = {}
        end
        if options[:sentinels].is_a?(Array)
          connect_via_sentinel(options, &block)
        else
          connect_direct(options, &block)
        end
      end
    end
  end
end
