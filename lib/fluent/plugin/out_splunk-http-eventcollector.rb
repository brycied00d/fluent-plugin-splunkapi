=begin

Copyright (c) 2015, Bryce Chidester (Calyptix Security)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=end

# Splunk HTTP Event collector docs
# http://dev.splunk.com/view/event-collector/SP-CAAAE6M
# http://docs.splunk.com/Documentation/Splunk/latest/RESTREF/RESTinput#services.2Fcollector

require 'date'

module Fluent
class SplunkHTTPEventcollectorOutput < BufferedOutput

  Plugin.register_output('splunk-http-eventcollector', self)

  config_param :test_mode, :bool, :default => false

  config_param :server, :string, :default => 'localhost:8088'
  config_param :verify, :bool, :default => true
  config_param :token, :string, :default => nil

  # Event parameters
  config_param :protocol, :string, :default => 'https'
  config_param :host, :string, :default => nil
  config_param :index, :string, :default => 'main'
  config_param :all_items, :bool, :default => false

  config_param :iso8601_time, :string, :default => nil
  config_param :sourcetype, :string, :default => 'fluentd'
  config_param :source, :string, :default => nil
  config_param :post_retry_max, :integer, :default => 5
  config_param :post_retry_interval, :integer, :default => 5
  config_param :nested_json, :bool, :default => false
  config_param :fields, :hash, :default => {}

  # TODO Find better upper limits
  config_param :batch_size_limit, :integer, :default => 262144 # 65535
  #config_param :batch_event_limit, :integer, :default => 100

  # Whether to allow non-UTF-8 characters in user logs. If set to true, any
  # non-UTF-8 character would be replaced by the string specified by
  # 'non_utf8_replacement_string'. If set to false, any non-UTF-8 character
  # would trigger the plugin to error out.
  config_param :coerce_to_utf8, :bool, :default => true

  # If 'coerce_to_utf8' is set to true, any non-UTF-8 character would be
  # replaced by the string specified here.
  config_param :non_utf8_replacement_string, :string, :default => ' '

  # Called on class load (class initializer)
  def initialize
    super
    log.trace "splunk-http-eventcollector(initialize) called"
    require 'net/http/persistent'
    require 'openssl'
  end  # initialize

  # Thanks to
  # https://github.com/kazegusuri/fluent-plugin-prometheus/blob/348c112d/lib/fluent/plugin/prometheus.rb
  def self.placeholder_expander(log)
    # Use internal class in order to expand placeholder
    if defined?(Fluent::Filter) # for v0.12, built-in PlaceholderExpander
      begin
        require 'fluent/plugin/filter_record_transformer'
        if defined?(Fluent::Plugin::RecordTransformerFilter::PlaceholderExpander)
          # for v0.14
          return Fluent::Plugin::RecordTransformerFilter::PlaceholderExpander.new(log: log)
        else
          # for v0.12
          return Fluent::RecordTransformerFilter::PlaceholderExpander.new(log: log)
        end
      rescue LoadError => e
        raise ConfigError, "cannot find filter_record_transformer plugin: #{e.message}"
      end
    else # for v0.10, use PlaceholderExapander in fluent-plugin-record-reformer plugin
      begin
        require 'fluent/plugin/out_record_reformer.rb'
        return Fluent::RecordReformerOutput::PlaceholderExpander.new(log: log)
      rescue LoadError => e
        raise ConfigError, "cannot find fluent-plugin-record-reformer: #{e.message}"
      end
    end
  end

  ## This method is called before starting.
  ## 'conf' is a Hash that includes configuration parameters.
  ## If the configuration is invalid, raise Fluent::ConfigError.
  def configure(conf)
    super
    log.trace "splunk-http-eventcollector(configure) called"
    begin
      @splunk_uri = URI "#{@protocol}://#{@server}/services/collector"
    rescue
      raise ConfigError, "Unable to parse the server into a URI."
    end

    @placeholder_expander = Fluent::SplunkHTTPEventcollectorOutput.placeholder_expander(log)
    @hostname = Socket.gethostname

    unless @fields.empty?
      @fields = inject_env_vars_into_fields
      @fields = inject_files_into_fields
    end

    # TODO Add other robust input/syntax checks.
  end  # configure

  ## This method is called when starting.
  ## Open sockets or files here.
  def start
    super
    log.trace "splunk-http-eventcollector(start) called"
    @http = Net::HTTP::Persistent.new 'fluent-plugin-splunk-http-eventcollector'
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless @verify
    @http.override_headers['Content-Type'] = 'application/json'
    @http.override_headers['User-Agent'] = 'fluent-plugin-splunk-http-eventcollector/0.0.1'
    @http.override_headers['Authorization'] = "Splunk #{@token}"

    log.trace "initialized for splunk-http-eventcollector"
  end

  ## This method is called when shutting down.
  ## Shutdown the thread and close sockets or files here.
  def shutdown
    super
    log.trace "splunk-http-eventcollector(shutdown) called"

    @http.shutdown
    log.trace "shutdown from splunk-http-eventcollector"
  end  # shutdown

  ## This method is called when an event reaches to Fluentd. (like unbuffered emit())
  ## Convert the event to a raw string.
  def format(tag, time, record)
    #log.trace "splunk-http-eventcollector(format) called"
    # Basic object for Splunk. Note explicit type-casting to avoid accidental errors.

    placeholder_values = {
      'tag' => tag,
      'tag_parts' => tag.split('.'),
      'hostname' => @hostname,
      'record' => record
    }

    placeholders = @placeholder_expander.prepare_placeholders(placeholder_values)

    splunk_object = Hash[
        "time" => handle_get_time(time, placeholders),
        "source" => if @source.nil? then tag.to_s else @placeholder_expander.expand(@source, placeholders) end,
        "sourcetype" => @placeholder_expander.expand(@sourcetype.to_s, placeholders),
        "host" => @placeholder_expander.expand(@host.to_s, placeholders),
        "index" =>  @placeholder_expander.expand(@index, placeholders)
      ]
    # TODO: parse different source types as expected: KVP, JSON, TEXT
    if @all_items
      splunk_object["event"] = convert_to_utf8(record)
    else
      splunk_object["event"] = convert_to_utf8(record["message"])
    end

    unless @fields.empty?
      splunk_object["fields"] = @fields
    end

    json_event = splunk_object.to_json
    #log.debug "Generated JSON(#{json_event.class.to_s}): #{json_event.to_s}"
    #log.debug "format: returning: #{[tag, record].to_json.to_s}"
    if @nested_json
      json_event + "\n"
    else
      json_event
    end
  end

  # By this point, fluentd has decided its buffer is full and it's time to flush
  # it. chunk.read is a concatenated string of JSON.to_s objects. Simply POST
  # them to Splunk and go about our life.
  ## This method is called every flush interval. Write the buffer chunk
  ## to files or databases here.
  ## 'chunk' is a buffer chunk that includes multiple formatted
  ## events. You can use 'data = chunk.read' to get all events and
  ## 'chunk.open {|io| ... }' to get IO objects.
  ##
  ## NOTE! This method is called by internal thread, not Fluentd's main thread. So IO wait doesn't affect other plugins.
  def write(chunk)
    log.trace "splunk-http-eventcollector(write) called"

    if @nested_json
      split_chunk = chunk.read.split("\n")
    else
      # Break the concatenated string of JSON-formatted events into an Array
      split_chunk = chunk.read.split("}{").each do |x|
        # Reconstruct the opening{/closing} that #split() strips off.
        x.prepend("{") unless x.start_with?("{")
        x << "}" unless x.end_with?("}")
      end
    end
    log.debug "Pushing #{numfmt(split_chunk.size)} events (" +
        "#{numfmt(chunk.read.bytesize)} bytes) to Splunk."
    # If fluentd is pushing too much data to Splunk at once, split up the payload
    # Don't care about the number of events so much as the POST size (bytes)
    #if split_chunk.size > @batch_event_limit
    #  log.warn "Fluentd is attempting to push #{numfmt(split_chunk.size)} " +
    #      "events in a single push to Splunk. The configured limit is " +
    #      "#{numfmt(@batch_event_limit)}."
    #end
    if chunk.read.bytesize > @batch_size_limit
      log.warn "Fluentd is attempting to push #{numfmt(chunk.read.bytesize)} " +
          "bytes in a single push to Splunk. The configured limit is " +
          "#{numfmt(@batch_size_limit)} bytes."
      newbuffer = Array.new
      split_chunk_counter = 0
      split_chunk.each do |c|
        split_chunk_counter = split_chunk_counter + 1
        #log.debug "(#{numfmt(split_chunk_counter)}/#{numfmt(split_chunk.size)}) " +
        #    "newbuffer.bytesize=#{numfmt(newbuffer.join.bytesize)} + " +
        #    "c.bytesize=#{numfmt(c.bytesize)} ????"
        if newbuffer.join.bytesize + c.bytesize < @batch_size_limit
          #log.debug "Appended!"
          newbuffer << c
        else
          # Reached the limit - push the current newbuffer.join, and reset
          #log.debug "Would exceed limit. Flushing newbuffer and continuing."
          log.debug "(#{numfmt(split_chunk_counter)}/#{numfmt(split_chunk.size)}) " +
              "newbuffer.bytesize=#{numfmt(newbuffer.join.bytesize)} + " +
              "c.bytesize=#{numfmt(c.bytesize)} > #{numfmt(@batch_size_limit)}, " +
              "flushing current buffer to Splunk."
          push_buffer newbuffer.join
          newbuffer = Array c
        end # if/else buffer fits limit
      end # split_chunk.each
      # Push anything left over.
      push_buffer newbuffer.join if newbuffer.size
      return
    else
      return push_buffer chunk.read
    end # if chunk.read.bytesize > @batch_size_limit
  end # write

  def push_buffer(body)
    post = Net::HTTP::Post.new @splunk_uri.request_uri
    post.body = body
    log.debug "POST #{@splunk_uri}"
    if @test_mode
      log.debug "TEST_MODE Payload: #{body}"
      return
    end
    # retry up to :post_retry_max times
    1.upto(@post_retry_max) do |c|
      response = @http.request @splunk_uri, post
      log.debug "=>(#{c}/#{numfmt(@post_retry_max)}) #{response.code} " +
          "(#{response.message})"
      # TODO check the actual server response too (it's JSON)
      if response.code == "200"  # and...
        # success
        break
      # TODO check 40X response within post_retry_max and retry
      elsif response.code.match(/^50/) and c < @post_retry_max
        # retry
        log.warn "#{@splunk_uri}: Server error #{response.code} (" +
            "#{response.message}). Retrying in #{@post_retry_interval} " +
            "seconds.\n#{response.body}"
        sleep @post_retry_interval
        next
      elsif response.code.match(/^40/)
        # user error
        log.error "#{@splunk_uri}: #{response.code} (#{response.message})\nReq: #{body}\nRes: #{response.body}"
        break
      elsif c < @post_retry_max
        # retry
        log.debug "#{@splunk_uri}: Retrying..."
        sleep @post_retry_interval
        next
      else
        # other errors. fluentd will retry processing on exception
        # FIXME: this may duplicate logs when using multiple buffers
        raise "#{@splunk_uri}: #{response.message}\n#{response.body}"
      end # If response.code
    end # 1.upto(@post_retry_max)
  end # push_buffer

  def numfmt(input)
    input.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  end # numfmt

  # Encode as UTF-8. If 'coerce_to_utf8' is set to true in the config, any
  # non-UTF-8 character would be replaced by the string specified by
  # 'non_utf8_replacement_string'. If 'coerce_to_utf8' is set to false, any
  # non-UTF-8 character would trigger the plugin to error out.
  # Thanks to
  # https://github.com/GoogleCloudPlatform/fluent-plugin-google-cloud/blob/dbc28575/lib/fluent/plugin/out_google_cloud.rb#L1284
  def convert_to_utf8(input)
    if input.is_a?(Hash)
      record = {}
      input.each do |key, value|
        record[convert_to_utf8(key)] = convert_to_utf8(value)
      end

      return record
    end
    return input.map { |value| convert_to_utf8(value) } if input.is_a?(Array)
    return input unless input.respond_to?(:encode)

    if @coerce_to_utf8
      input.encode(
        'utf-8',
        invalid: :replace,
        undef: :replace,
        replace: @non_utf8_replacement_string)
    else
      begin
        input.encode('utf-8')
      rescue EncodingError
        @log.error 'Encountered encoding issues potentially due to non ' \
                   'UTF-8 characters. To allow non-UTF-8 characters and ' \
                   'replace them with spaces, please set "coerce_to_utf8" ' \
                   'to true.'
        raise
      end
    end
  end

  # Environment variables are passed in with the following format:
  # @{ENV['NAME_OF_ENV_VAR']}
  def inject_env_vars_into_fields
    @fields.each { | _, field_value|
      match_data = field_value.to_s.match(/^@\{ENV\['(?<env_name>.+)'\]\}$/)
      if match_data && match_data["env_name"]
        field_value.replace(ENV[match_data["env_name"]])
      end
    }
  end

  def inject_files_into_fields
    @fields.each { | _, field_value |
      match_data = field_value.to_s.match(/^@\{FILE\['(?<file_path>.+)'\]\}$/)
      if match_data && match_data["file_path"]
        field_value.replace(IO.read(match_data["file_path"]))
      end
    }
  end

  def handle_get_time(emitted_at_timestamp, placeholders)
    if @iso8601_time.nil?
      emitted_at_timestamp.to_f
    else
      time = @placeholder_expander.expand(@iso8601_time, placeholders)
      DateTime.iso8601(time).to_time.to_f
    end
  end

end  # class SplunkHTTPEventcollectorOutput
end  # module Fluent
