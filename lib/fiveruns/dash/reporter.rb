require 'thread'

Thread.abort_on_exception = true

module Fiveruns::Dash
    
  class Reporter
    
    attr_accessor :interval
    attr_reader :started_at
    def initialize(session, interval = 60.seconds.to_i)
      @session = session
      @interval = interval
    end
    
    def revive!
      return if !started? || foreground?
      start if !@thread || !@thread.alive?
    end
    
    def alive?
      @thread && @thread.alive? && started?
    end

    def start(run_in_background = true)
      restarted = @started_at ? true : false
      unless defined?(@started_at)
        @started_at = ::Fiveruns::Dash::START_TIME
      end
      setup_for run_in_background
      if @background
        @thread = Thread.new { run(restarted) }
      else
        # Will it be run in foreground?
        run(restarted)
      end
    end
    
    def started?
      @started_at
    end
    
    def foreground?
      started? && !@background
    end
    
    def background?
      started? && @background
    end
    
    def send_trace(trace)
      if trace.data
        payload = TracePayload.new(trace)
        Fiveruns::Dash.logger.debug "Sending trace: #{payload.to_json}"
        Thread.new { Update.new(payload).store(*update_locations) }
      else
        Fiveruns::Dash.logger.debug "No trace to send"      
      end
    end
    
    def ping
      payload = PingPayload.new(@session.info, @started_at)
      Update.new(payload).ping(*update_locations)
    end

    #######
    private
    #######

    def run(restarted)
      Fiveruns::Dash.logger.info "Starting reporter thread; endpoints are #{update_locations.inspect}"
      loop do
        send_info_update
        sleep @interval
        send_data_update
        send_exceptions_update
      end
    end
    
    def setup_for(run_in_background = true)
      @background = run_in_background
    end
    
    def send_info_update
      @info_update_sent ||= begin
        payload = InfoPayload.new(@session.info, @started_at)
        Fiveruns::Dash.logger.debug "Sending info: #{payload.to_json}"
        result = Update.new(payload).store(*update_locations)
        send_fake_info(payload)
        result
      end
    end
    
    def send_exceptions_update
      if @info_update_sent
        data = @session.exception_data
        if data.empty?
          Fiveruns::Dash.logger.debug "No exceptions for this interval"
        else
          payload = ExceptionsPayload.new(data)
          Fiveruns::Dash.logger.debug "Sending exceptions: #{payload.to_json}"
          Update.new(payload).store(*update_locations)
        end        
      else
        # Discard data
        @session.reset
        Fiveruns::Dash.logger.warn "Discarding interval exceptions"
      end
    end
    
    def send_data_update
      if @info_update_sent
        data = @session.data
        payload = DataPayload.new(data)
        Fiveruns::Dash.logger.debug "Sending data: #{payload.to_json}"
        result = Update.new(payload).store(*update_locations)
        send_fake_data(payload)
        result
      else
        # Discard data
        @session.reset
        Fiveruns::Dash.logger.warn "Discarding interval data"
      end
    end
    
    def update_locations
      @update_locations ||= if ENV['DASH_UPDATE']
        ENV['DASH_UPDATE'].strip.split(/\s*,\s*/)
      else
        default_update_locations
      end
    end

    def send_fake_data(payload)
      fake_host_count.times do |idx|
        payload.params[:process_id] = Fiveruns::Dash.process_ids[idx+1]
        Fiveruns::Dash.logger.debug "Sending data: #{payload.to_json}"
        Update.new(payload).store(*update_locations)
      end
    end

    def send_fake_info(payload)
      host = payload.params[:hostname]
      fake_host_count.times do |idx|
        payload.params[:mac] += idx.to_s
        payload.params[:hostname] = host + idx.to_s
        Fiveruns::Dash.logger.debug "Sending info: #{payload.to_json}"
        Update.new(payload).store(*update_locations)
      end
    end

    def fake_host_count
      ENV['DASH_FAKE_HOST_COUNT'].to_i
    end
    
    def default_update_locations
      %w(https://dash-collector.fiveruns.com https://dash-collector02.fiveruns.com)
    end

  end
      
end