require "rspec"
require "eventmachine"
require "sensu/redis/client"

module Helpers
  def timer(delay, &callback)
    periodic_timer = EM::PeriodicTimer.new(delay) do
      callback.call
      periodic_timer.cancel
    end
  end

  def async_wrapper(&callback)
    EM.run do
      timer(10) do
        raise "test timed out"
      end
      callback.call
    end
  end

  def async_done
    EM.stop_event_loop
  end

  def redis
    @redis ||= EM.connect("127.0.0.1", 6379, Sensu::Redis::Client)
  end
end
