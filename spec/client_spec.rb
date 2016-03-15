require File.join(File.dirname(__FILE__), "helpers")
require "sensu/redis/client"

describe "Sensu::Redis::Client" do
  include Helpers

  it "can connect to a redis instance" do
    async_wrapper do
      redis = EM.connect("127.0.0.1", 6379, Sensu::Redis::Client)
      redis.callback do
        expect(redis.connected?).to eq(true)
        async_done
      end
    end
  end
end
