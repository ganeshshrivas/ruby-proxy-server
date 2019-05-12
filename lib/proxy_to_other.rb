require 'byebug'
require 'rack-proxy'
require 'byebug'

class ProxyToOther < Rack::Proxy
  def initialize(app)
    @app = app
  end

  def call(env)
    original_host = env["HTTP_HOST"]
    rewrite_env(env)
    if env["HTTP_HOST"] != original_host
      perform_request(env)
    else
      # just regular
      @app.call(env)
    end
  end

  def rewrite_env(env)
    request = Rack::Request.new(env)
    # use rack proxy for anything hitting our host app at /example_service
    if request.path =~ %r{^/requests}
        backend = URI("https://www.mocky.io/v2/5185415ba171ea3a00704eed/")
        # most backends required host set properly, but rack-proxy doesn't set this for you automatically
        # even when a backend host is passed in via the options
        env["HTTP_HOST"] = backend.host

        # This is the only path that needs to be set currently on Rails 5 & greater
        env['PATH_INFO'] = "/v2/5185415ba171ea3a00704eed/"

        env["SERVER_PORT"] = 80
        
        # don't send your sites cookies to target service, unless it is a trusted internal service that can parse all your cookies
        env['HTTP_COOKIE'] = ''
        super(env)
    else
      env["HTTP_HOST"] = "localhost:3000"
    end
    env
  end
end