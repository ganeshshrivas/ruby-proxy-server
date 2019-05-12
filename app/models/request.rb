class Request < ApplicationRecord
 serialize :query_params, Hash
 serialize :error, Hash

 validates :original_url, presence: true
 validates :query_params, presence: true

end
