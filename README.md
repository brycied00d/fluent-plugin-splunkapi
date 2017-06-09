# Fluent::Plugin::SplunkHTTPEventcollector, a plugin for [Fluentd](http://fluentd.org)

Splunk output plugin for Fluent event collector.

This plugin interfaces with the Splunk HTTP Event Collector:
  http://dev.splunk.com/view/event-collector/SP-CAAAE6M

[![Build Status](https://travis-ci.org/brycied00d/fluent-plugin-splunk-http-eventcollector.svg?branch=master)](https://travis-ci.org/brycied00d/fluent-plugin-splunk-http-eventcollector)

## Basic Example

    <match **>
      type splunk-http-eventcollector
      server 127.0.0.1:8088
      verify false
      token YOUR-TOKEN

      # Convert fluent tags to Splunk sources.
      # If you set an index, "check_index false" is required.
      host YOUR-HOSTNAME
      index SOME-INDEX
      check_index false
      source {TAG}
      sourcetype fluent
    </match>

## Installation

Add this line to your application's Gemfile:

    gem 'fluent-plugin-splunk-http-eventcollector'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install fluent-plugin-splunk-http-eventcollector

Whatever is appropriate for your environment. Note: If you're using the
`td-agent` package, it brings with it its own "embedded" Ruby environment with
either `td-agent-gem` or `/opt/td-agent/embedded/bin/gem` depending on platform.

## Configuration

Put the following lines to your fluent.conf:

    <match **>
      type splunk-http-eventcollector

      # server: Splunk server host and port
      # default: localhost:8088
      server localhost:8088

      # protocol: Connect to Splunk server via 'http' or 'https'
      # default: https
      #protocol http

      # verify: SSL server verification
      # default: true
      #verify false

      # token: the token issued
      token YOUR-TOKEN

      #
      # Event Parameters
      #

      # host: 'host' parameter passed to Splunk
      host YOUR-HOSTNAME

      # index: 'index' parameter passed to Splunk (REST only)
      # default: <none>
      #index main

      # check_index: 'check-index' parameter passed to Splunk (REST only)
      # default: <none>
      #check_index false

      # host: 'source' parameter passed to Splunk
      # default: {TAG}
      #
      # "{TAG}" will be replaced by fluent tags at runtime
      source {TAG}

      # sourcetype: 'sourcetype' parameter passed to Splunk
      # default: fluent
      sourcetype fluent

      #
      # Buffering Parameters
      #

      # Standard parameters for buffering.  See documentation for details:
      #   http://docs.fluentd.org/articles/buffer-plugin-overview
      buffer_type memory
      buffer_queue_limit 16

      # buffer_chunk_limit: The maxium size of POST data in a single API call.
      # 
      # This value should be reasonablly small since the current implementation
      # of out_splunk-http-eventcollector converts a chunk to POST data on memory before API calls.
      # The default value should be good enough.
      buffer_chunk_limit 8m

      # flush_interval: The interval of API requests.
      # 
      # Make sure that this value is sufficiently large to make successive API calls.
      # Note that a different 'source' creates a different API POST, each of which may
      # take two or more seconds.  If you include "{TAG}" in the source parameter and
      # this 'match' section recieves many tags, a single flush may take long time.
      # (Run fluentd with -v to see verbose logs.)
      flush_interval 60s
    </match>

## Example

    # Input from applications
    <source>
      type forward
    </source>

    # Input from log files
    <source>
      type tail
      path /var/log/apache2/ssl_access.log
      tag ssl_access.log
      format /(?<message>.*)/
      pos_file /var/log/td-agent/ssl_access.log.pos
    </source>

    # fluent logs in text format
    <match fluent.*>
      type splunk-http-eventcollector
      server splunk.example.com:8089
      sourcetype fluentd
    </match>

    # log files in text format without timestamp
    <match *.log>
      type splunk-http-eventcollector
      server splunk.example.com:8089
      sourcetype log
      time_format none
    </match>

    # application logs in kvp format
    <match app.**>
      type splunk-http-eventcollector
      server splunk.example.com:8089
      sourcetype app
    </match>

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
