require "sensu/redis/constants"
require "sensu/redis/errors"

module Sensu
  module Redis
    # Sensu Module for parsing RESP (REdis Serialization Protocol).
    # You can read about RESP @ http://redis.io/topics/protocol
    # This module calls methods provided by other Sensu Redis modules:
    #   Sensu::Redis::Processor.dispatch_error()
    #   Sensu::Redis::Processor.dispatch_response()
    #   Sensu::Redis::Processor.begin_multibulk()
    #   Sensu::Redis::Connection.error()
    module Parser
      # Parse a RESP line.
      #
      # @param line [String]
      def parse_line(line)
        # Trim off the response type and delimiter (\r\n).
        response = line.slice(1..-3)
        # First character indicates response type.
        case line[0, 1]
        when MINUS # Error, e.g. -ERR
          dispatch_error(response)
        when PLUS # String, e.g. +OK
          dispatch_response(response)
        when DOLLAR # Bulk string, e.g. $3\r\nfoo\r\n
          response_size = Integer(response)
          if response_size == -1 # No data, return nil.
            dispatch_response(nil)
          elsif @buffer.size >= response_size + 2 # Complete data.
            dispatch_response(@buffer.slice!(0, response_size))
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

      # EM connection receive data, parse incoming data using RESP
      # (`parse_line()`).
      #
      # @param data [String]
      def receive_data(data)
        (@buffer ||= '') << data
        while index = @buffer.index(DELIM)
          line = @buffer.slice!(0, index+2)
          if parse_line(line) == INCOMPLETE
            @buffer[0...0] = line
            break
          end
        end
      end
    end
  end
end
