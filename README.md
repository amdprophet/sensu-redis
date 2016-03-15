# Sensu::Redis

[![Build Status](https://travis-ci.org/sensu/sensu-redis.svg?branch=master)](https://travis-ci.org/sensu/sensu-redis)

[![Code Climate](https://codeclimate.com/github/sensu/sensu-redis.png)](https://codeclimate.com/github/sensu/sensu-redis)
[![Code Climate Coverage](https://codeclimate.com/github/sensu/sensu-redis/coverage.png)](https://codeclimate.com/github/sensu/sensu-redis)

## Installation

Add this line to your application's Gemfile:

    gem 'sensu-redis'

And then execute:

    $ bundle

## Usage

This library provides the Redis client, with Sentinel support, for
Sensu's components. It's documentation can be found
[here](http://rubydoc.info/github/sensu/sensu-redis/Sensu/Redis).

## Contributing

Please do not submit a pull request to add features that Sensu does
not nor will not require.

1. [Fork it](https://github.com/sensu/sensu-redis/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

Sensu-Redis is released under the [MIT
license](https://raw.github.com/sensu/sensu-redis/master/LICENSE.txt).
