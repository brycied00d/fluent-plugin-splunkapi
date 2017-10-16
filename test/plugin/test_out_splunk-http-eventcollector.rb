require 'helper'

class SplunkHTTPEventcollectorOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    server localhost:8089
    verify false
    token changeme
  ]

  def create_driver(conf=CONFIG, tag='test')
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::SplunkHTTPEventcollectorOutput, tag).configure(conf)
  end

  def test_configure
    # default
    d = create_driver
    assert_equal nil, d.instance.source
    assert_equal 'fluentd', d.instance.sourcetype
  end

  def test_write
    stub_request(:post, "https://localhost:8089/services/collector").
      to_return(body: '{"text":"Success","code":0}')

    d = create_driver

    time = Time.parse("2010-01-02 13:14:15 UTC").to_i
    d.emit({ "message" => "a message"}, time)

    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {
        "Authorization" => "Splunk changeme",
        'Content-Type' => 'application/json',
        'User-Agent' => 'fluent-plugin-splunk-http-eventcollector/0.0.1'
      },
      body: { time: time, source:"test", sourcetype: "fluentd", host: "", index: "main", event: "a message" },
      times: 1
  end

  def test_expand
    stub_request(:post, "https://localhost:8089/services/collector").
      to_return(body: '{"text":"Success","code":0}')

    d = create_driver(CONFIG + %[
      source ${record["source"]}
      sourcetype ${tag_parts[0]}
    ])

    time = Time.parse("2010-01-02 13:14:15 UTC").to_i
    d.emit({"message" => "a message", "source" => "source-from-record"}, time)

    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body: { time: time, source: "source-from-record", sourcetype: "test", host: "", index: "main", event: "a message" },
      times: 1
  end

  def test_4XX_error_retry
    stub_request(:post, "https://localhost:8089/services/collector").
      with(headers: {"Authorization" => "Splunk changeme"}).
      to_return(body: '{"text":"Incorrect data format","code":5,"invalid-event-number":0}', status: 400)

    d = create_driver

    time = Time.parse("2010-01-02 13:14:15 UTC").to_i
    d.emit({ "message" => "1" }, time)
    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body: { time: time, source: "test", sourcetype: "fluentd", host: "", index: "main", event: "1" },
      times: 1
  end

  def test_5XX_error_retry
    request_count = 0
    stub_request(:post, "https://localhost:8089/services/collector").
      with(headers: {"Authorization" => "Splunk changeme"}).
      to_return do |request|
        request_count += 1

        if request_count < 5
          { body: '{"text":"Internal server error","code":8}', status: 500 }
        else
          { body: '{"text":"Success","code":0}', status: 200 }
        end
      end


    d = create_driver(CONFIG + %[
      post_retry_max 5
      post_retry_interval 0.1
    ])

    time = Time.parse("2010-01-02 13:14:15 UTC").to_i
    d.emit({ "message" => "1" }, time)
    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body: { time: time, source: "test", sourcetype: "fluentd", host: "", index: "main", event: "1" },
      times: 5
  end

  def test_write_splitting
    stub_request(:post, "https://localhost:8089/services/collector").
      with(headers: {"Authorization" => "Splunk changeme"}).
      to_return(body: '{"text":"Incorrect data format","code":5,"invalid-event-number":0}', status: 400)

    # A single msg is ~110 bytes
    d = create_driver(CONFIG + %[
      batch_size_limit 250
    ])

    time = Time.parse("2010-01-02 13:14:15 UTC").to_f
    d.emit({"message" => "a" }, time)
    d.emit({"message" => "b" }, time)
    d.emit({"message" => "c" }, time)
    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body:
        { time: time, source: "test", sourcetype: "fluentd", host: "", index: "main", event: "a" }.to_json +
        { time: time, source: "test", sourcetype: "fluentd", host: "", index: "main", event: "b" }.to_json,
      times: 1
    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body: { time: time, source: "test", sourcetype: "fluentd", host: "", index: "main", event: "c" }.to_json,
      times: 1
    assert_requested :post, "https://localhost:8089/services/collector", times: 2
  end

  def test_utf8
    stub_request(:post, "https://localhost:8089/services/collector").
      with(headers: {"Authorization" => "Splunk changeme"}).
      to_return(body: '{"text":"Success","code":0}')

    d = create_driver(CONFIG + %[
      all_items true
    ])

    time = Time.parse("2010-01-02 13:14:15 UTC").to_i
    d.emit({ "some" => { "nested" => "ü†f-8".force_encoding("BINARY"), "with" => ['ü', '†', 'f-8'].map {|c| c.force_encoding("BINARY") } } }, time)
    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body: { time: time, source: "test", sourcetype: "fluentd", host: "", index: "main", event: { some: { nested: "     f-8", with: ["  ","   ","f-8"]}}},
      times: 1
  end

  def test_utf8
    stub_request(:post, "https://localhost:8089/services/collector").
      with(headers: {"Authorization" => "Splunk changeme"}).
      to_return(body: '{"text":"Success","code":0}')

    d = create_driver(CONFIG + %[
      all_items true
    ])

    time = Time.parse("2010-01-02 13:14:15 UTC").to_i
    d.emit({ "some" => { "nested" => "ü†f-8".force_encoding("BINARY"), "with" => ['ü', '†', 'f-8'].map {|c| c.force_encoding("BINARY") } } }, time)
    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body: { time: time, source: "test", sourcetype: "fluentd", host: "", index: "main", event: { some: { nested: "     f-8", with: ["  ","   ","f-8"]}}},
      times: 1
  end

  def test_write_fields
    stub_request(:post, "https://localhost:8089/services/collector").
        with(headers: {"Authorization" => "Splunk changeme"}).
        to_return(body: '{"text":"Success","code":0}')

    d = create_driver(CONFIG + %[
      fields { "cluster": "aws" }
      source ${record["source"]}
    ])

    time = Time.parse("2010-01-02 13:14:15 UTC").to_i
    d.emit({ "message" => "a message", "source" => "source-from-record"}, time)
    d.run

    assert_requested :post, "https://localhost:8089/services/collector",
      headers: {"Authorization" => "Splunk changeme"},
      body: { time: time, source: "source-from-record", sourcetype: "fluentd", host: "", index: "main", event: "a message", fields: { cluster: "aws" } },
      times: 1
  end
end
