require "rubygems"
require "sensu/redis/parser"
require "sensu/redis/processor"
require "sensu/redis/commands"
require "sensu/redis/connection"
require "eventmachine"
require "uri"

module Sensu
  module Redis
    class Client < EM::Connection
      include EM::Deferrable
      include Parser
      include Processor
      include Commands
      include Connection

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
          if options.is_a?(String)
            options = parse_url(options)
          end
          options[:host] ||= "127.0.0.1"
          options[:port] = (options[:port] || 6379).to_i
          EM.connect(options[:host], options[:port], self, options)
        end
      end
    end
  end
end
