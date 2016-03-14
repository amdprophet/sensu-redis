require "sensu/redis/client"
require "eventmachine"

module Sensu
  module Redis
    class Sentinel
      # Initialize the Sentinel connections. The default Redis master
      # name is "mymaster", which is the same name that the Sensu HA
      # Redis documentation uses. The master name must be set
      # correctly in order for `resolve()`.
      #
      # @param options [Hash] containing the standard Redis
      #   connection settings.
      def initialize(options={})
        @master = options[:master] || "mymaster"
        @sentinels = connect_to_sentinels(options[:sentinels])
      end

      # Connect to a Sentinel instance.
      #
      # @param options [Hash] containing the host and port.
      # @return [Object] Sentinel connection.
      def connect_to_sentinel(options={})
        options[:host] ||= "127.0.0.1"
        options[:port] ||= 26379
        EM.connect(options[:host], options[:port], Client, options)
      end

      # Connect to all Sentinel instances. This method defaults the
      # Sentinel host and port if either have not been set.
      #
      # @param sentinels [Array]
      # @return [Array] of Sentinel connection objects.
      def connect_to_sentinels(sentinels)
        sentinels.map do |options|
          connect_to_sentinel(options)
        end
      end

      # Select a Sentinel connection object that is currently
      # connected.
      #
      # @return [Object] Sentinel connection.
      def select_a_sentinel
        @sentinels.select { |sentinel| sentinel.connected? }.shuffle.first
      end

      # Retry `resolve()` with the provided callback.
      #
      # @yield callback called when Sentinel resolves the current
      #   Redis master address (host & port).
      def retry_resolve(&block)
        EM::Timer.new(1) do
          resolve(&block)
        end
      end

      # Resolve the current Redis master via Sentinel. The correct
      # Redis master name is required for this method to work.
      #
      # @yield callback called when Sentinel resolves the current
      #   Redis master address (host & port).
      def resolve(&block)
        sentinel = select_a_sentinel
        if sentinel.nil?
          retry_resolve(&block)
        else
          sentinel.callback do
            sentinel.send_command("sentinel", "get-master-addr-by-name", @master) do |host, port|
              if host && port
                block.call(host, port.to_i)
              else
                retry_resolve(&block)
              end
            end
          end
          sentinel.errback do
            retry_resolve(&block)
          end
          sentinel.timeout(60)
        end
      end
    end
  end
end
