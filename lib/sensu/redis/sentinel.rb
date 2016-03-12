require "sensu/redis/client"
require "eventmachine"

module Sensu
  module Redis
    class Sentinel
      include EM::Deferrable

      def initialize(options={})
        @options = options
        @master_name = options[:host] || "mymaster"
        @sentinels = connect_to_sentinels(@options[:sentinels])
      end

      def connect_to_sentinel(host, port)
        connection = EM.connect(host, port, Client)
        connection.callback do
          succeed
        end
      end

      def connect_to_sentinels(sentinels)
        sentinels.map do |sentinel|
          host = sentinel[:host] || "127.0.0.1"
          port = sentinel[:port] || 26379
          connect_to_sentinel(host, port)
        end
      end

      def select_a_sentinel
        @sentinels.select { |sentinel| sentinel.connected? }.shuffle.first
      end

      def resolve
        sentinel = select_a_sentinel
        if sentinel.nil?
          fail
        else
          sentinel.callback do
            sentinel.send_command("sentinel", "get-master-addr-by-name", @master_name) do |host, port|
              yield(host, port)
            end
          end
        end
      end
    end
  end
end
