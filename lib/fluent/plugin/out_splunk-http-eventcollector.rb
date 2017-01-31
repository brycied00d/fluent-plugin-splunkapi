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

module Fluent
class SplunkHTTPEventcollectorOutput < BufferedOutput
  Plugin.register_output('splunk-http-eventcollector', self)
  
  config_param :test_mode, :bool, :default => false
  
  config_param :server, :string, :default => 'localhost:8088'
  config_param :verify, :bool, :default => true
  config_param :token, :string, :default => nil
  
  # Event parameters
  config_param :host, :string, :default => nil
  config_param :index, :string, :default => 'main'
  config_param :sourcetype, :string, :default => 'fluent'
  
  config_param :post_retry_max, :integer, :default => 5
  config_param :post_retry_interval, :integer, :default => 5
  
  # TODO Find better upper limits
  config_param :batch_size_limit, :integer, :default => 262144 # 65535
  #config_param :batch_event_limit, :integer, :default => 100
  
  # Called on class load (class initializer)
  def initialize
    super
    $log.debug "splunk-http-eventcollector(initialize) called"
    require 'net/http/persistent'
    require 'openssl'
  end  # initialize
  
  ## This method is called before starting.
  ## 'conf' is a Hash that includes configuration parameters.
  ## If the configuration is invalid, raise Fluent::ConfigError.
  def configure(conf)
    super
    $log.debug "splunk-http-eventcollector(configure) called"
    begin
      @protocol = @verify ? "https" : "http"
      @splunk_uri = URI "https://#{@server}/services/collector"
    rescue
      raise ConfigError, "Unable to parse the server into a URI."
    end
    # TODO Add other robust input/syntax checks.
  end  # configure
  
  ## This method is called when starting.
  ## Open sockets or files here.
  def start
    super
    $log.debug "splunk-http-eventcollector(start) called"
    @http = Net::HTTP::Persistent.new 'fluent-plugin-splunk-http-eventcollector'
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless @verify
    @http.override_headers['Content-Type'] = 'application/json'
    @http.override_headers['User-Agent'] = 'fluent-plugin-splunk-http-eventcollector/0.0.1'
    @http.override_headers['Authorization'] = "Splunk #{@token}"
    
    $log.debug "initialized for splunk-http-eventcollector"
  end
  
  ## This method is called when shutting down.
  ## Shutdown the thread and close sockets or files here.
  def shutdown
    super
    $log.debug "splunk-http-eventcollector(shutdown) called"
    
    @http.shutdown
    $log.debug "shutdown from splunk-http-eventcollector"
  end  # shutdown
  
  ## This method is called when an event reaches to Fluentd. (like unbuffered emit())
  ## Convert the event to a raw string.
  def format(tag, time, record)
    #$log.debug "splunk-http-eventcollector(format) called"
    # Basic object for Splunk. Note explicit type-casting to avoid accidental errors.
    splunk_object = Hash[
        "event" => record["message"],
        "time" => time.to_i,
        "source" => tag.to_s,
        "sourcetype" => @sourcetype.to_s,
        "host" => @host.to_s,
        "index" => @index.to_s
        ]
    json_event = splunk_object.to_json
    #$log.debug "Generated JSON(#{json_event.class.to_s}): #{json_event.to_s}"
    #$log.debug "format: returning: #{[tag, record].to_json.to_s}"
    json_event
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
    $log.debug "splunk-http-eventcollector(write) called"
    
    # Break the concatenated string of JSON-formatted events into an Array
    split_chunk = chunk.read.split("}{").each do |x|
      # Reconstruct the opening{/closing} that #split() strips off.
      x.prepend("{") unless x.start_with?("{")
      x << "}" unless x.end_with?("}")
    end
    $log.debug "Pushing #{numfmt(split_chunk.size)} events (" +
        "#{numfmt(chunk.read.bytesize)} bytes) to Splunk."
    # If fluentd is pushing too much data to Splunk at once, split up the payload
    # Don't care about the number of events so much as the POST size (bytes)
    #if split_chunk.size > @batch_event_limit
    #  $log.warn "Fluentd is attempting to push #{numfmt(split_chunk.size)} " +
    #      "events in a single push to Splunk. The configured limit is " + 
    #      "#{numfmt(@batch_event_limit)}."
    #end
    if chunk.read.bytesize > @batch_size_limit
      $log.warn "Fluentd is attempting to push #{numfmt(chunk.read.bytesize)} " +
          "bytes in a single push to Splunk. The configured limit is " + 
          "#{numfmt(@batch_size_limit)} bytes."
      newbuffer = Array.new
      split_chunk_counter = 0
      split_chunk.each do |c|
        split_chunk_counter = split_chunk_counter + 1
        #$log.debug "(#{numfmt(split_chunk_counter)}/#{numfmt(split_chunk.size)}) " +
        #    "newbuffer.bytesize=#{numfmt(newbuffer.join.bytesize)} + " +
        #    "c.bytesize=#{numfmt(c.bytesize)} ????"
        if newbuffer.join.bytesize + c.bytesize < @batch_size_limit
          #$log.debug "Appended!"
          newbuffer << c
        else
          # Reached the limit - push the current newbuffer.join, and reset
          #$log.debug "Would exceed limit. Flushing newbuffer and continuing."
          $log.debug "(#{numfmt(split_chunk_counter)}/#{numfmt(split_chunk.size)}) " +
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
    $log.debug "POST #{@splunk_uri}"
    if @test_mode
      $log.debug "TEST_MODE Payload: #{body}"
      return
    end
    # retry up to :post_retry_max times
    1.upto(@post_retry_max) do |c|
      response = @http.request @splunk_uri, post
      $log.debug "=>(#{c}/#{numfmt(@post_retry_max)}) #{response.code} " +
          "(#{response.message})"
      # TODO check the actual server response too (it's JSON)
      if response.code == "200"  # and...
        # success
        break
      # TODO check 40X response within post_retry_max and retry
      elsif response.code.match(/^50/) and c < @post_retry_max
        # retry
        $log.warn "#{@splunk_uri}: Server error #{response.code} (" +
            "#{response.message}). Retrying in #{@post_retry_interval} " +
            "seconds.\n#{response.body}"
        sleep @post_retry_interval
        next
      elsif response.code.match(/^40/)
        # user error
        $log.error "#{@splunk_uri}: #{response.code} (#{response.message})\n#{response.body}"
        break
      elsif c < @post_retry_max
        # retry
        $log.debug "#{@splunk_uri}: Retrying..."
        sleep @post_retry_interval
        next
      else
        # other errors. fluentd will retry processing on exception
        # FIXME: this may duplicate logs when using multiple buffers
        raise "#{@splunk_uri}: #{response.message}"
      end # If response.code
    end # 1.upto(@post_retry_max)
  end # push_buffer
  
  def numfmt(input)
    input.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  end # numfmt
end  # class SplunkHTTPEventcollectorOutput
end  # module Fluent
