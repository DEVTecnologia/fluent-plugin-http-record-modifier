module Fluent
  class HttpRecordModifier < Filter
    Plugin.register_filter('http_record_modifier', self)

    def initialize
      require 'socket'
      require 'yajl'
      require 'net/http'
      require 'uri'
      super
    end

    #Based on Filter Record Tranformer that is built-in on Fluent
    config_param :remove_keys, :string, :default => nil
    config_param :keep_keys, :string, :default => nil
    config_param :method, :string, :default => :get
    config_param :rene_record, :bool, :default => false
    config_param :auto_typecast, :bool, :default => false # false for lower version compatibility
    config_param :endpoint_url, :string
    config_param :serializer, :string, :default => :form
    config_param :authentication, :string, :default => nil 
    config_param :username, :string, :default => ''
    config_param :password, :string, :default => ''
    config_param :raise_on_error, :bool, :default => true
    config_param :cache, :bool, :default => true
    config_param :expire, :integer, :default => 600 #10 min
    config_param :renew_time_key, :string, :default => nil

    def configure(conf)
      super
      @method ||= conf['method']
      @map = {}
      # <record></record> directive
      conf.elements.select { |element| element.name == 'record' }.each do |element|
        element.each_pair do |k, v|
          element.has_key?(k) # to suppress unread configuration warning
          @map[k] = parse_value(v)
        end
      end

      @maped_params = {}
      # <params></params> directive
      conf.elements.select { |element| element.name == 'params' }.each do |element|
        element.each_pair do |k, v|
          element.has_key?(k) # to suppress unread configuration warning
          @maped_params[k] = parse_value(v)
        end
      end

      if @remove_keys
        @remove_keys = @remove_keys.split(',')
      end

      if @keep_keys
        raise Fluent::ConfigError, "`renew_record` must be true to use `keep_keys`" unless @renew_record
        @keep_keys = @keep_keys.split(',')
      end

      @request_cache = Cache.new(@cache, @expire)

      @placeholder_expander = PlaceholderExpander.new({
        :log           => log,
        :auto_typecast => @auto_typecast,
      })

      @hostname = Socket.gethostname
    end

    def filter_stream(tag, es)
      new_es = MultiEventStream.new
      tag_parts = tag.split('.')
      tag_prefix = tag_prefix(tag_parts)
      tag_suffix = tag_suffix(tag_parts)
      placeholders = {
        'tag' => tag,
        'tag_parts' => tag_parts,
        'tag_prefix' => tag_prefix,
        'tag_suffix' => tag_suffix,
        'hostname' => @hostname,
      }
      last_record = nil
      es.each do |time, record|
        last_record = record # for debug log
        req, uri = create_request(tag, time, record)
        body = @request_cache.get(uri.to_s)
        if body.nil?
          res = send_request(req, uri)
          body = deserialize_body(res)
          @request_cache.set(uri.to_s, body)
        end
        new_record = reform(time, record, placeholders, body)
        if @renew_time_key && new_record.has_key?(@renew_time_key)
          time = new_record[@renew_time_key].to_i
        end
        new_es.add(time, new_record)
      end
      new_es
    rescue => e
      log.warn "failed to reform records", :error_class => e.class, :error => e.message
      log.warn_backtrace
      log.debug "map:#{@map} record:#{last_record} placeholders:#{placeholders}"
    end

    def deserialize_body(res)
      clean = {}
      body = res.body
      if res.content_type == 'application/json'
        body = Yajl.load(body)
        if body.is_a? Hash
          clean = Yajl.load(res.body)
        end
      end
      clean['body'] = body
      clean
    end

    def format_params(tag, time, record)
      tag_parts = tag.split('.')
      tag_prefix = tag_prefix(tag_parts)
      tag_suffix = tag_suffix(tag_parts)
      placeholders = {
        'tag' => tag,
        'tag_parts' => tag_parts,
        'tag_prefix' => tag_prefix,
        'tag_suffix' => tag_suffix,
        'hostname' => @hostname,
      }
      @placeholder_expander.prepare_placeholders(time, record, placeholders)

      expand_placeholders(@maped_params)
    end

    def set_body(req, tag, time, record)
      if @serializer == :json
        req['Content-Type'] = 'application/json'
      else
        req.set_form_data(record)
      end
      req
    end


    def create_request(tag, time, record)
      url = URI.encode(@endpoint_url.to_s)
      uri = URI.parse(url)
      params = format_params(tag, time, record)
      uri.query = URI.encode_www_form(params)
      req = Net::HTTP.const_get(@method.to_s.capitalize).new(uri)
      unless @method.to_s.capitalize == 'Get'
        set_body(req, tag, time, record)
      end
      return req, uri
    end

    def send_request(req, uri)    
      res = nil

      begin
        if @auth and @auth == :basic
          req.basic_auth(@username, @password)
        end
        res = Net::HTTP.new(uri.host, uri.port).start {|http| http.request(req) }
      rescue => e # rescue all StandardErrors
        # server didn't respond
        $log.warn "Net::HTTP.#{req.method.capitalize} raises exception: #{e.class}, '#{e.message}'"
        raise e if @raise_on_error
      end # end begin
    end # end send_request

    private

    def parse_value(value_str)
      if value_str.start_with?('{', '[')
        JSON.parse(value_str)
      else
        value_str
      end
    rescue => e
      log.warn "failed to parse #{value_str} as json. Assuming #{value_str} is a string", :error_class => e.class, :error => e.message
      value_str # emit as string
    end

    def reform(time, record, opts, res)
      @placeholder_expander.prepare_placeholders(time, res, opts)

      new_record = @renew_record ? {} : record.dup
      @keep_keys.each {|k| new_record[k] = record[k]} if @keep_keys and @renew_record
      new_record.merge!(expand_placeholders(@map))
      @remove_keys.each {|k| new_record.delete(k) } if @remove_keys

      new_record
    end

    def expand_placeholders(value)
      if value.is_a?(String)
        new_value = @placeholder_expander.expand(value)
      elsif value.is_a?(Hash)
        new_value = {}
        value.each_pair do |k, v|
          new_value[@placeholder_expander.expand(k, true)] = expand_placeholders(v)
        end
      elsif value.is_a?(Array)
        new_value = []
        value.each_with_index do |v, i|
          new_value[i] = expand_placeholders(v)
        end
      else
        new_value = value
      end
      new_value
    end

    def tag_prefix(tag_parts)
      return [] if tag_parts.empty?
      tag_prefix = [tag_parts.first]
      1.upto(tag_parts.size-1).each do |i|
        tag_prefix[i] = "#{tag_prefix[i-1]}.#{tag_parts[i]}"
      end
      tag_prefix
    end

    def tag_suffix(tag_parts)
      return [] if tag_parts.empty?
      rev_tag_parts = tag_parts.reverse
      rev_tag_suffix = [rev_tag_parts.first]
      1.upto(tag_parts.size-1).each do |i|
        rev_tag_suffix[i] = "#{rev_tag_parts[i]}.#{rev_tag_suffix[i-1]}"
      end
      rev_tag_suffix.reverse!
    end

    class Cache
      def initialize(cache, expire)
        @data = {}
        @cache = cache
        @expire = expire
      end

      def get(key)
        unless @data.has_key?(key) and @cache
          return nil
        end
        if Time.now.to_i > @data[key]['time'] + @expire
          @data.delete(key)
          return nil
        end
        return @data[key]['value']
      end

      def set(key, value)
        if @cache
          @data[key] = {
            'time' => Time.now.to_i,
            'value' => value
          }
        end
      end
    end

    class PlaceholderExpander
      attr_reader :placeholders, :log

      def initialize(params)
        @log = params[:log]
        @auto_typecast = params[:auto_typecast]
      end

      def prepare_placeholders(time, record, opts)
        placeholders = { '${time}' => Time.at(time).to_s }
        record.each {|key, value| crawl_placeholder(value, placeholders, "#{key}")}
        opts.each do |key, value|
          if value.kind_of?(Array) # tag_parts, etc
            size = value.size
            value.each_with_index { |v, idx|
              placeholders.store("${#{key}[#{idx}]}", v)
              placeholders.store("${#{key}[#{idx-size}]}", v) # support [-1]
            }
          else # string, interger, float, and others?
            placeholders.store("${#{key}}", value)
          end
        end

        @placeholders = placeholders
      end

      def crawl_placeholder (value, placeholder, before, limit = 50)
        if limit >= 0
          if value.kind_of?(Hash) 
            value.each {|key, v| crawl_placeholder(v, placeholder, "#{before}.#{key}", limit - 1)}
          elsif value.kind_of?(Array) # tag_parts, etc
            size = value.size
            value.each_with_index { |v, idx|
              crawl_placeholder(v, placeholder, "#{before}[#{idx}]", limit - 1)
              crawl_placeholder(v, placeholder, "#{before}[#{idx-size}]", limit - 1) #suport [-1]
            }
          end
        end
        # string, interger, float, and others?
        placeholder.store("${#{before}}", value)
      end

      def expand(str, force_stringify=false)
        if @auto_typecast and !force_stringify
          single_placeholder_matched = str.match(/\A(\${[^}]+}|__[A-Z_]+__)\z/)
          if single_placeholder_matched
            log_unknown_placeholder($1)
            return @placeholders[single_placeholder_matched[1]]
          end
        end
        str.gsub(/(\${[^}]+}|__[A-Z_]+__)/) {
          log_unknown_placeholder($1)
          @placeholders[$1]
        }
      end

      private
      def log_unknown_placeholder(placeholder)
        unless @placeholders.include?(placeholder)
          log.warn "unknown placeholder `#{placeholder}` found"
        end
      end
    end
  end
end
