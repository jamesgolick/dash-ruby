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
    
    def start(run_in_background = true)
      restarted = @started_at ? true : false
      unless defined?(@started_at)
        @started_at = Time.now.utc
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
    
    #######
    private
    #######

    def run(restarted)
      Fiveruns::Dash.logger.info "Starting reporter thread; endpoints are #{update_locations.inspect}"
      loop do
        send_info_update
        sleep @interval
        send_data_update
      end
    end
    
    def setup_for(run_in_background = true)
      @background = run_in_background
    end
    
    def send_info_update
      @info_update_sent ||= begin
        Fiveruns::Dash.logger.warn "Sending info: #{@session.info}"
        payload = InfoPayload.new(@session.info, @started_at)
        Update.new(payload, @session.configuration).store(*update_locations)
      end
    end
    
    def send_data_update
      if @info_update_sent
        payload = DataPayload.new(@session.data)
        Update.new(payload, @session.configuration).store(*update_locations)
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
    
    def default_update_locations
      %w(https://dash-collector.fiveruns.com https://dash-collector02.fiveruns.com)
    end
          
  end
      
end