module Fiveruns::Dash
  
  module Instrument
        
    class Error < ::NameError; end

    def self.handlers
      @handlers ||= []
    end
    
    # We hold onto the metrics themselves so we can dynamically call their
    # context_finders (which may be changed after instrumentation)
    def self.metrics
      @metrics ||= []
    end
    
    # Important: This does not de-instrument
    def self.clear
      handlers.clear
      metrics.clear
    end
        
    # call-seq:
    #  Instrument.add("ClassName#instance_method", ...) { |instance, time, *args| ... }
    #  Instrument.add("ClassName::class_method", ...) { |klass, time, *args| ... }
    #  Instrument.add("ClassName.class_method", ...) { |klass, time, *args| ... }
    #
    # Add a handler to be called every time a method is invoked
    def self.add(*raw_targets, &handler)
      options = raw_targets.last.is_a?(Hash) ? raw_targets.pop : {}
      raw_targets.each do |raw_target|
        begin
          obj, meth = case raw_target
          when /^(.+)#(.+)$/
            [Fiveruns::Dash::Util.constantize($1), $2]
          when /^(.+)(?:\.|::)(.+)$/
            [(class << Fiveruns::Dash::Util.constantize($1); self; end), $2]
          else
            raise Error, "Bad target format: #{raw_target}"
          end
          instrument(obj, meth, options, &handler)
        rescue Fiveruns::Dash::Instrument::Error => em
          raise em
        rescue => e
          Fiveruns::Dash.logger.error "Unable to instrument '#{raw_target}': #{e.message}"
          Fiveruns::Dash.logger.error e.backtrace.join("\n\t")
        end
      end
    end

    def self.reentrant_timing(token, offset, context, obj, args, limit_to_within)
      # token allows us to handle re-entrant timing, see e.g. ar_time
      Thread.current[token] = 0 if Thread.current[token].nil?
      Thread.current[token] = Thread.current[token] + 1
      begin
        start = Time.now
        result = yield
      ensure
        time = Time.now - start
        Thread.current[token] = Thread.current[token] - 1
        if Thread.current[token] == 0
          if !limit_to_within || (Thread.current[:dash_markers] || []).include?(limit_to_within)
            ::Fiveruns::Dash::Instrument.handlers[offset].call(context, obj, time, *args)
          end
        end
      end
      result
    end
    
    def self.timing(offset, context, mark, obj, args, limit_to_within)
      if mark
        Thread.current[:dash_markers] ||= []
        Thread.current[:dash_markers].push mark
      end
      start = Time.now
      begin
        result = yield
      ensure
        time = Time.now - start
        Thread.current[:dash_markers].pop if mark

        if !limit_to_within || (Thread.current[:dash_markers] || []).include?(limit_to_within)
          ::Fiveruns::Dash::Instrument.handlers[offset].call(context, obj, time, *args)
        end
      end
      result
    end
    
    #######
    private
    #######

    def self.instrument(obj, meth, options = {}, &handler)
      handlers << handler
      handler_offset = handlers.size - 1
      identifier = "instrument_#{handler.hash.abs}"
      if options[:metric]
        metrics << options[:metric]
        context_find = "::Fiveruns::Dash.sync { ::Fiveruns::Dash::Instrument.metrics[#{metrics.size - 1}].context_finder.call(self, *args) }"
      else
        context_find = '[]'
      end
      code = wrapping meth, identifier do |without|
        if options[:exceptions]
          <<-EXCEPTIONS
            begin
              #{without}(*args, &block)
            rescue Exception => _e
              _sample = ::Fiveruns::Dash::Instrument.handlers[#{handler_offset}].call(_e, self, *args)
              ::Fiveruns::Dash.session.add_exception(_e, _sample)
              raise
            end
          EXCEPTIONS
        elsif options[:reentrant_token]
          <<-REENTRANT
            ::Fiveruns::Dash::Instrument.reentrant_timing(:id#{options[:reentrant_token]}, #{handler_offset}, #{context_find}, self, args, #{options[:only_within] ? ":#{options[:only_within]}" : 'nil'}) do
              #{without}(*args, &block)
            end
          REENTRANT
        else
          <<-PERFORMANCE
            ::Fiveruns::Dash::Instrument.timing(#{handler_offset}, #{context_find}, self, args, #{options[:mark_as] ? ":#{options[:mark_as]}" : 'nil'}, #{options[:only_within] ? ":#{options[:only_within]}" : 'nil'}) do
              #{without}(*args, &block)
            end
          PERFORMANCE
        end
      end
      obj.module_eval code, __FILE__, __LINE__
      identifier
    rescue SyntaxError => e
      puts "Syntax error (#{e.message})\n#{code}"
      raise
    rescue => e
      raise Error, "Could not attach (#{e.message})"
    end

    def self.wrapping(meth, feature)
      format = meth =~ /^(.*?)(\?|!|=)$/ ? "#{$1}_%s_#{feature}#{$2}" : "#{meth}_%s_#{feature}" 
      <<-DYNAMIC
        def #{format % :with}(*args, &block)
          _trace = Thread.current[:trace]
          if _trace
            _trace.step do
              #{yield(format % :without)}
            end
          else
            #{yield(format % :without)}
          end
        end
        Fiveruns::Dash::Util.chain(self, :#{meth}, :#{feature})
      DYNAMIC
    end
      
  end
  
end