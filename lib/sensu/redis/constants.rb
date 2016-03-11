module Sensu
  module Redis
    OK = "OK".freeze
    MINUS = "-".freeze
    PLUS = "+".freeze
    COLON = ":".freeze
    DOLLAR = "$".freeze
    ASTERISK = "*".freeze
    DELIM = "\r\n".freeze

    INCOMPLETE = "incomp".freeze

    EMPTY_ARRAY = [].freeze

    TRUE_VALUES = %w[1 OK].freeze

    PUBSUB_RESPONSES = %w[message unsubscribe].freeze

    REDIS_COMMANDS = [
      "set",
      "get",
      "del"
    ].freeze

    BOOLEAN_PROCESSOR = lambda{|r| %w[1 OK].include?(r.to_s)}

    RESPONSE_PROCESSORS = {
      "exists" => BOOLEAN_PROCESSOR,
      "sadd" => BOOLEAN_PROCESSOR,
      "srem" => BOOLEAN_PROCESSOR,
      "setnx" => BOOLEAN_PROCESSOR,
      "del" => BOOLEAN_PROCESSOR,
      "expire" => BOOLEAN_PROCESSOR,
      "select" => BOOLEAN_PROCESSOR,
      "hset" => BOOLEAN_PROCESSOR,
      "hdel" => BOOLEAN_PROCESSOR,
      "hsetnx" => BOOLEAN_PROCESSOR,
      "hgetall" => lambda{|r| Hash[*r]},
      "info" => lambda{|r|
        info = {}
        r.each_line do |line|
          line.chomp!
          unless line.empty?
            k, v = line.split(":", 2)
            info[k.to_sym] = v
          end
        end
        info
      }
    }
  end
end
