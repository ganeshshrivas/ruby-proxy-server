require 'rack-proxy'
require 'byebug'
require 'cgi'

class ProxyToOther < Rack::Proxy
  def initialize(app)
    @app = app
  end

  def perform_request(env)
    request = Rack::Request.new(env)
    if request.path =~ %r{^/requests}
      backend = URI("https://www.mocky.io/v2/5185415ba171ea3a00704eed/")
      # most backends required host set properly, but rack-proxy doesn't set this for you automatically
      # even when a backend host is passed in via the options
      env["HTTP_HOST"] = backend.host
      env['PATH_INFO'] = "/v2/5185415ba171ea3a00704eed"

      if(env["QUERY_STRING"])
        env["PATH_INFO"] = env["PATH_INFO"] + "?" + env["QUERY_STRING"]
      end
      env["rack.ssl_verify_none"] = true
      env["SERVER_PORT"] = 80
      
      # don't send your sites cookies to target service, unless it is a trusted internal service that can parse all your cookies
      env['HTTP_COOKIE'] = ''
      env
    else
      @app.call(env)
    end
  end


  def rewrite_response(env)
    source_request = Rack::Request.new(env)
      # Initialize request
      if source_request.fullpath == ""
        full_path = URI.parse(env['REQUEST_URI']).request_uri
      else
        full_path = source_request.fullpath
      end

      target_request = Net::HTTP.const_get(source_request.request_method.capitalize).new(full_path)

      # Setup headers
      target_request.initialize_http_header(self.class.extract_http_request_headers(source_request.env))

      # Setup body
      if target_request.request_body_permitted? && source_request.body
        target_request.body_stream    = source_request.body
        target_request.content_length = source_request.content_length.to_i
        target_request.content_type   = source_request.content_type if source_request.content_type
        target_request.body_stream.rewind
      end

      backend = env.delete('rack.backend') || @backend || source_request
      use_ssl = backend.scheme == "https"
      ssl_verify_none = (env.delete('rack.ssl_verify_none') || @ssl_verify_none) == true
      read_timeout = env.delete('http.read_timeout') || @read_timeout

      # Create the response
      if @streaming
        # streaming response (the actual network communication is deferred, a.k.a. streamed)
        target_response = HttpStreamingResponse.new(target_request, backend.host, backend.port)
        target_response.use_ssl = use_ssl
        target_response.read_timeout = read_timeout
        target_response.verify_mode = OpenSSL::SSL::VERIFY_NONE if use_ssl && ssl_verify_none
        target_response.ssl_version = @ssl_version if @ssl_version
      else
        http = Net::HTTP.new(backend.host, backend.port)
        http.use_ssl = use_ssl if use_ssl
        http.read_timeout = read_timeout
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE if use_ssl && ssl_verify_none
        http.ssl_version = @ssl_version if @ssl_version

        target_response = http.start do
          http.request(target_request)
        end
      end

      headers = self.class.normalize_headers(target_response.respond_to?(:headers) ? target_response.headers : target_response.to_hash)
      body    = target_response.body || [""]
      body    = [body] unless body.respond_to?(:each)

      # According to https://tools.ietf.org/html/draft-ietf-httpbis-p1-messaging-14#section-7.1.3.1Acc
      # should remove hop-by-hop header fields
      headers.reject! { |k| ['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade'].include? k.downcase }
    
      params = CGI::parse env["QUERY_STRING"]
      req_errors = validate_params_and_get_errors(params)
      unless(params["proxy"].empty?)
        logger = Rails.logger
        url = env["ORIGINAL_FULLPATH"]
        query_params = params
        req_errors = req_errors.empty? ? "" : req_errors
        logger.info "request params--------#{params}"
        logger.info "request errors--------#{req_errors}"
        begin
          req = Request.new(original_url: url, query_params: query_params, req_errors: req_errors)
          req.save!
        rescue StandardError => e
          logger.error e.message
          logger.error e.backtrace.join("\n")
        end
      end
      [target_response.code, headers, body]
  end

  def validate_params_and_get_errors(params)
    errors = {}
    if params["type"].empty? or params["app_id"].empty?
      errors[:presence] = "type and app_id must present in url"
    end
    unless ["static", "lite", "dynamic"].include? params["type"][0]
      errors[:type_mismatch] = "type is wrong"
    end
    if params["app_id"][0].to_i == 0
      errors[:app_id] = "must be numeric"
    end
    errors
  end
end