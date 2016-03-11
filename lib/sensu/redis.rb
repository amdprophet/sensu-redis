require "rubygems"
require "sensu/redis/client"
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

      def connect(options={})
        case options
        when String
          options = parse_url(options)
        when nil
          options = {}
        end
        options[:host] ||= "127.0.0.1"
        options[:port] = (options[:port] || 6379).to_i
        EM.connect(options[:host], options[:port], Sensu::Redis::Client, options)
      end
    end
  end
end
