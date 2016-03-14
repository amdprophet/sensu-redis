require File.join(File.dirname(__FILE__), "helpers")
require "sensu/redis"

describe "Sensu::Redis" do
  include Helpers

  it "can connect to a redis instance" do
    async_wrapper do
      Sensu::Redis.connect do |redis|
        redis.callback do
          expect(redis.connected?).to eq(true)
          async_done
        end
      end
    end
  end

  it "can connect to a redis master via sentinel", :sentinel => true do
    async_wrapper do
      Sensu::Redis.connect(:sentinels => [{:port => 26379}]) do |redis|
        redis.callback do
          expect(redis.connected?).to eq(true)
          async_done
        end
      end
    end
  end
end
