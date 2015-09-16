module SalesforceBulkApi
require 'timeout'

  class Connection
    include Concerns::Throttling

    @@XML_HEADER = '<?xml version="1.0" encoding="utf-8" ?>'
    @@API_VERSION = nil
    @@LOGIN_HOST = 'login.salesforce.com'
    @@INSTANCE_HOST = nil # Gets set in login()

    def initialize(api_version,client)
      @client=client
      @session_id = nil
      @server_url = nil
      @instance = nil
      @@API_VERSION = api_version
      @@LOGIN_PATH = "/services/Soap/u/#{@@API_VERSION}"
      @@PATH_PREFIX = "/services/async/#{@@API_VERSION}/"

      login()
    end

    def login()
      client_type = @client.class.to_s
      case client_type
      when "Restforce::Data::Client"
        puts("logging in with Restforce::Data::Client")
        @session_id= @client.options[:oauth_token] || @client.options[:refresh_token]
        @server_url=@client.options[:instance_url]
      else
        puts("logging in with other Client")
        @session_id=@client.oauth_token
        @server_url=@client.instance_url
      end
      puts("Session id: #{@session_id}, server url: #{@server_url}")
      @instance = parse_instance()
      @@INSTANCE_HOST = "#{@instance}.salesforce.com"
    end

    def post_xml(host, path, xml, headers)
      host = host || @@INSTANCE_HOST
      if host != @@LOGIN_HOST # Not login, need to add session id to header
        headers['X-SFDC-Session'] = @session_id
        path = "#{@@PATH_PREFIX}#{path}"
      end
      i = 0
      begin
        count :post
        throttle(http_method: :post, path: path)
        puts("host: #{host}")
        puts("headers: #{headers}")
        https(host).post(path, xml, headers).body
      rescue
        i += 1
        if i < 3
          puts "Request fail #{i}: Retrying #{path}"
          retry
        else
          puts "FATAL: Request to #{path} failed three times."
          raise
        end
      end
    end

    def get_request(host, path, headers)
      host = host || @@INSTANCE_HOST
      path = "#{@@PATH_PREFIX}#{path}"
      if host != @@LOGIN_HOST # Not login, need to add session id to header
        headers['X-SFDC-Session'] = @session_id;
      end

      count :get
      throttle(http_method: :get, path: path)
      https(host).get(path, headers).body
    end

    def https(host)
      req = Net::HTTP.new(host, 443)
      req.use_ssl = true
      req.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req
    end

    def parse_instance()
      @instance = @server_url.match(/https:\/\/[a-z]{2}[0-9]{1,2}/).to_s.gsub("https://","")
      @instance = @server_url.split(".salesforce.com")[0].split("://")[1] if @instance.nil? || @instance.empty?
      return @instance
    end

    def counters
      {
        get: get_counters[:get],
        post: get_counters[:post]
      }
    end

    private

    def get_counters
      @counters ||= Hash.new(0)
    end

    def count(http_method)
      get_counters[http_method] += 1
    end

  end

end
