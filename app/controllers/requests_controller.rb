class RequestsController < ApplicationController
 
 def index
 	param! :type, String, required: true, in: %w(static lite dynamic)
 	param! :app_id, Integer, required: true
 end
 
end
