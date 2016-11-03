require "ipaddr"
require "socket"

module Sensu
  module Redis
    module Utilities
      # Determine if a host is an IP address (or DNS hostname).
      #
      # @param host [String]
      # @return [TrueClass, FalseClass]
      def ip_address?(host)
        begin
          ip_address = IPAddr.new(host)
          ip_address.ipv4? || ip_address.ipv6?
        rescue IPAddr::InvalidAddressError
          false
        end
      end

      # Resolve a hostname to an IP address for a host. This method
      # will return `nil` to the provided block when the hostname
      # cannot be resolved to an IP address.
      #
      # @param host [String]
      # @param block [Proc] called with the result of the DNS
      #   query (IP address).
      def resolve_hostname(host, &block)
        resolve = Proc.new do
          begin
            info = case RUBY_PLATFORM
            when /linux/
              flags = Socket::AI_NUMERICSERV | Socket::AI_ADDRCONFIG
              Socket.getaddrinfo(host, nil, Socket::AF_UNSPEC, nil, nil, flags)
            else
              Socket.getaddrinfo(host, nil)
            end
            info.first.nil? ? nil : info.first[2]
          rescue => error
            @logger.error("redis connection error", {
              :reason => "unable to resolve hostname",
              :host => host,
              :error => error.to_s
            }) if @logger
            nil
          end
        end
        EM.defer(resolve, block)
      end

      # Resolve a hostname to an IP address for a host. This method
      # will return the provided host to the provided block if it
      # is already an IP address. This method will return `nil` to the
      # provided block when the hostname cannot be resolved to an
      # IP address.
      #
      # @param host [String]
      # @param block [Proc] called with the result of the DNS
      #   query (IP address).
      def resolve_host(host, &block)
        if ip_address?(host)
          yield host
        else
          resolve_hostname(host, &block)
        end
      end
    end
  end
end
