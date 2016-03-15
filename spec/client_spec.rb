require File.join(File.dirname(__FILE__), "helpers")
require "sensu/redis/client"

describe "Sensu::Redis::Client" do
  include Helpers

  it "can connect to a redis instance" do
    async_wrapper do
      redis.callback do
        expect(redis.connected?).to eq(true)
        async_done
      end
    end
  end

  it "can do a modified multi/exec" do
    async_wrapper do
      redis.callback do
        redis.multi
        redis.set("foo", "bar")
        redis.sadd("baz", "qux")
        redis.smembers("baz")
        redis.exec do |response|
          expect(response).to eq(["qux"])
          redis.get("foo") do |value|
            expect(value).to eq("bar")
            async_done
          end
        end
      end
    end
  end
end
